import * as argon2 from 'argon2';

import type { AppConfig } from '../config/env.js';
import { MEMBER_KEYS, type MemberKey } from '../domain/constants.js';
import { AppError } from '../domain/errors.js';
import type { AuthenticatedMember, MemberView } from '../domain/models.js';
import { Prisma } from '../generated/prisma/client.js';
import type { DatabaseClient } from '../infrastructure/prisma.js';
import type { TokenService } from '../infrastructure/token-service.js';
import { type IssuedRefreshToken } from '../infrastructure/token-service.js';

interface AuthResponse {
  member: MemberView;
  accessToken: string;
  accessTokenExpiresAt: string;
  refreshToken: string;
  refreshTokenExpiresAt: string;
}

class RefreshReuseDetected extends Error {
  public constructor(public readonly familyId: string) {
    super('Refresh token reuse detected.');
  }
}

const memberSelect = {
  id: true,
  householdId: true,
  key: true,
  displayName: true,
} satisfies Prisma.MemberSelect;

type SelectedMember = Prisma.MemberGetPayload<{ select: typeof memberSelect }>;

function memberIdentity(member: SelectedMember): AuthenticatedMember {
  return {
    memberId: member.id,
    householdId: member.householdId,
    memberKey: member.key,
  };
}

function memberView(member: SelectedMember): MemberView {
  return {
    id: member.id,
    householdId: member.householdId,
    key: member.key,
    displayName: member.displayName,
  };
}

export class AuthService {
  public constructor(
    private readonly prisma: DatabaseClient,
    private readonly tokens: TokenService,
    private readonly config: AppConfig,
  ) {}

  public async login(memberKey: MemberKey, pin: string): Promise<AuthResponse> {
    const member = await this.prisma.member.findFirst({
      where: {
        key: memberKey,
        disabledAt: null,
      },
      select: {
        ...memberSelect,
        pinHash: true,
      },
    });

    const valid =
      member !== null &&
      (await argon2.verify(member.pinHash, `${pin}${this.config.pinPepper}`));

    if (!valid || member === null) {
      throw new AppError(401, 'INVALID_CREDENTIALS', 'Invalid member or PIN.');
    }

    const identity = memberIdentity(member);
    const access = await this.tokens.issueAccessToken(identity);
    const refresh = this.tokens.issueRefreshToken();
    await this.persistRefreshToken(member.id, refresh);

    return {
      member: memberView(member),
      accessToken: access.token,
      accessTokenExpiresAt: access.expiresAt,
      refreshToken: refresh.rawToken,
      refreshTokenExpiresAt: refresh.expiresAt.toISOString(),
    };
  }

  public async refresh(rawToken: string): Promise<AuthResponse> {
    const tokenId = this.tokens.parseRefreshToken(rawToken);
    const suppliedHash = this.tokens.hashOpaqueToken(rawToken);
    const now = new Date();

    try {
      const rotated = await this.prisma.$transaction(
        async (transaction) => {
          const existing = await transaction.refreshToken.findUnique({
            where: { id: tokenId },
            include: {
              member: {
                select: {
                  ...memberSelect,
                  disabledAt: true,
                },
              },
            },
          });

          if (
            existing === null ||
            !this.tokens.tokenHashesMatch(existing.tokenHash, suppliedHash) ||
            existing.member.disabledAt !== null
          ) {
            return null;
          }

          if (
            existing.revokedAt !== null ||
            existing.replacedByTokenId !== null
          ) {
            throw new RefreshReuseDetected(existing.familyId);
          }

          if (existing.expiresAt <= now) {
            await transaction.refreshToken.updateMany({
              where: { id: existing.id, revokedAt: null },
              data: { revokedAt: now, lastUsedAt: now },
            });
            return null;
          }

          const replacement = this.tokens.issueRefreshToken(
            existing.familyId,
            now,
          );
          await transaction.refreshToken.create({
            data: {
              id: replacement.id,
              memberId: existing.memberId,
              familyId: replacement.familyId,
              tokenHash: replacement.tokenHash,
              expiresAt: replacement.expiresAt,
            },
          });

          const updated = await transaction.refreshToken.updateMany({
            where: {
              id: existing.id,
              revokedAt: null,
              replacedByTokenId: null,
            },
            data: {
              revokedAt: now,
              lastUsedAt: now,
              replacedByTokenId: replacement.id,
            },
          });

          if (updated.count !== 1) {
            throw new RefreshReuseDetected(existing.familyId);
          }

          return {
            member: existing.member,
            replacement,
          };
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );

      if (rotated === null) {
        throw new AppError(
          401,
          'INVALID_REFRESH_TOKEN',
          'The refresh token is invalid.',
        );
      }

      const identity = memberIdentity(rotated.member);
      const access = await this.tokens.issueAccessToken(identity);

      return {
        member: memberView(rotated.member),
        accessToken: access.token,
        accessTokenExpiresAt: access.expiresAt,
        refreshToken: rotated.replacement.rawToken,
        refreshTokenExpiresAt: rotated.replacement.expiresAt.toISOString(),
      };
    } catch (error) {
      if (error instanceof RefreshReuseDetected) {
        await this.prisma.refreshToken.updateMany({
          where: { familyId: error.familyId, revokedAt: null },
          data: { revokedAt: now },
        });
        throw new AppError(
          401,
          'INVALID_REFRESH_TOKEN',
          'The refresh token is invalid.',
        );
      }

      throw error;
    }
  }

  public async logout(
    identity: AuthenticatedMember,
    rawToken: string,
  ): Promise<void> {
    let tokenId: string;
    try {
      tokenId = this.tokens.parseRefreshToken(rawToken);
    } catch {
      return;
    }

    const tokenHash = this.tokens.hashOpaqueToken(rawToken);
    await this.prisma.refreshToken.updateMany({
      where: {
        id: tokenId,
        memberId: identity.memberId,
        tokenHash,
        revokedAt: null,
        member: {
          householdId: identity.householdId,
        },
      },
      data: { revokedAt: new Date() },
    });
  }

  public async currentMember(
    identity: AuthenticatedMember,
  ): Promise<MemberView> {
    const member = await this.prisma.member.findFirst({
      where: {
        id: identity.memberId,
        householdId: identity.householdId,
        key: identity.memberKey,
        disabledAt: null,
      },
      select: memberSelect,
    });

    if (member === null) {
      throw new AppError(401, 'UNAUTHORIZED', 'Authentication is required.');
    }

    return memberView(member);
  }

  public async authenticateAccessToken(
    rawToken: string,
  ): Promise<AuthenticatedMember> {
    const identity = await this.tokens.verifyAccessToken(rawToken);
    await this.currentMember(identity);
    return identity;
  }

  private async persistRefreshToken(
    memberId: string,
    refresh: IssuedRefreshToken,
  ): Promise<void> {
    await this.prisma.refreshToken.create({
      data: {
        id: refresh.id,
        memberId,
        familyId: refresh.familyId,
        tokenHash: refresh.tokenHash,
        expiresAt: refresh.expiresAt,
      },
    });
  }
}

export function isMemberKey(value: string): value is MemberKey {
  return MEMBER_KEYS.some((memberKey) => memberKey === value);
}
