import {
  createHash,
  createHmac,
  randomBytes,
  randomUUID,
  timingSafeEqual,
} from 'node:crypto';

import { jwtVerify, SignJWT } from 'jose';
import { z } from 'zod';

import type { AppConfig } from '../config/env.js';
import { MEMBER_KEYS } from '../domain/constants.js';
import { AppError } from '../domain/errors.js';
import type { AuthenticatedMember } from '../domain/models.js';

const accessClaimsSchema = z.object({
  sub: z.uuid(),
  householdId: z.uuid(),
  memberKey: z.enum(MEMBER_KEYS),
});

interface CursorPayload {
  kind: 'changes';
  householdId: string;
  sequence: string;
}

interface BootstrapPayload {
  kind: 'bootstrap';
  householdId: string;
  watermark: string;
  afterId: string;
}

type OpaquePayload = CursorPayload | BootstrapPayload;

export interface IssuedAccessToken {
  token: string;
  expiresAt: string;
}

export interface IssuedRefreshToken {
  id: string;
  familyId: string;
  rawToken: string;
  tokenHash: string;
  expiresAt: Date;
}

export class TokenService {
  private readonly accessSecret: Uint8Array;
  private readonly cursorSecret: Uint8Array;

  public constructor(private readonly config: AppConfig) {
    this.accessSecret = new TextEncoder().encode(config.jwtAccessSecret);
    this.cursorSecret = new TextEncoder().encode(config.cursorSigningSecret);
  }

  public async issueAccessToken(
    member: AuthenticatedMember,
  ): Promise<IssuedAccessToken> {
    const nowSeconds = Math.floor(Date.now() / 1000);
    const expiresAtSeconds = nowSeconds + this.config.accessTokenTtlSeconds;
    const token = await new SignJWT({
      householdId: member.householdId,
      memberKey: member.memberKey,
    })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setSubject(member.memberId)
      .setIssuer(this.config.jwtIssuer)
      .setAudience(this.config.jwtAudience)
      .setIssuedAt(nowSeconds)
      .setExpirationTime(expiresAtSeconds)
      .setJti(randomUUID())
      .sign(this.accessSecret);

    return {
      token,
      expiresAt: new Date(expiresAtSeconds * 1000).toISOString(),
    };
  }

  public async verifyAccessToken(token: string): Promise<AuthenticatedMember> {
    try {
      const verified = await jwtVerify(token, this.accessSecret, {
        algorithms: ['HS256'],
        issuer: this.config.jwtIssuer,
        audience: this.config.jwtAudience,
      });
      const claims = accessClaimsSchema.parse(verified.payload);

      return {
        memberId: claims.sub,
        householdId: claims.householdId,
        memberKey: claims.memberKey,
      };
    } catch {
      throw new AppError(401, 'UNAUTHORIZED', 'Authentication is required.');
    }
  }

  public issueRefreshToken(
    familyId: string = randomUUID(),
    now = new Date(),
  ): IssuedRefreshToken {
    const id = randomUUID();
    const secret = randomBytes(32).toString('base64url');
    const rawToken = `${id}.${secret}`;
    const expiresAt = new Date(now);
    expiresAt.setUTCDate(
      expiresAt.getUTCDate() + this.config.refreshTokenTtlDays,
    );

    return {
      id,
      familyId,
      rawToken,
      tokenHash: this.hashOpaqueToken(rawToken),
      expiresAt,
    };
  }

  public parseRefreshToken(rawToken: string): string {
    const [id, secret, extra] = rawToken.split('.');
    if (
      extra !== undefined ||
      id === undefined ||
      secret === undefined ||
      !z.uuid().safeParse(id).success ||
      !/^[A-Za-z0-9_-]{43}$/.test(secret)
    ) {
      throw new AppError(
        401,
        'INVALID_REFRESH_TOKEN',
        'The refresh token is invalid.',
      );
    }

    return id;
  }

  public hashOpaqueToken(rawToken: string): string {
    return createHash('sha256').update(rawToken, 'utf8').digest('hex');
  }

  public tokenHashesMatch(left: string, right: string): boolean {
    const leftBytes = Buffer.from(left, 'hex');
    const rightBytes = Buffer.from(right, 'hex');

    return (
      leftBytes.length === rightBytes.length &&
      timingSafeEqual(leftBytes, rightBytes)
    );
  }

  public encodeChangeCursor(householdId: string, sequence: bigint): string {
    return this.encodeOpaque({
      kind: 'changes',
      householdId,
      sequence: sequence.toString(),
    });
  }

  public decodeChangeCursor(token: string, householdId: string): bigint {
    const payload = this.decodeOpaque(token);
    if (payload.kind !== 'changes' || payload.householdId !== householdId) {
      throw new AppError(
        422,
        'INVALID_CURSOR',
        'The change cursor is invalid.',
      );
    }

    try {
      const sequence = BigInt(payload.sequence);
      if (sequence < 0n) {
        throw new Error('negative');
      }
      return sequence;
    } catch {
      throw new AppError(
        422,
        'INVALID_CURSOR',
        'The change cursor is invalid.',
      );
    }
  }

  public encodeBootstrapToken(
    householdId: string,
    watermark: bigint,
    afterId: string,
  ): string {
    return this.encodeOpaque({
      kind: 'bootstrap',
      householdId,
      watermark: watermark.toString(),
      afterId,
    });
  }

  public decodeBootstrapToken(
    token: string,
    householdId: string,
  ): { watermark: bigint; afterId: string } {
    const payload = this.decodeOpaque(token);
    if (
      payload.kind !== 'bootstrap' ||
      payload.householdId !== householdId ||
      !z.uuid().safeParse(payload.afterId).success
    ) {
      throw new AppError(
        422,
        'INVALID_PAGE_TOKEN',
        'The bootstrap page token is invalid.',
      );
    }

    try {
      const watermark = BigInt(payload.watermark);
      if (watermark < 0n) {
        throw new Error('negative');
      }
      return { watermark, afterId: payload.afterId };
    } catch {
      throw new AppError(
        422,
        'INVALID_PAGE_TOKEN',
        'The bootstrap page token is invalid.',
      );
    }
  }

  private encodeOpaque(payload: OpaquePayload): string {
    const encoded = Buffer.from(JSON.stringify(payload), 'utf8').toString(
      'base64url',
    );
    const signature = createHmac('sha256', this.cursorSecret)
      .update(encoded, 'utf8')
      .digest('base64url');
    return `${encoded}.${signature}`;
  }

  private decodeOpaque(token: string): OpaquePayload {
    const [encoded, suppliedSignature, extra] = token.split('.');
    if (
      extra !== undefined ||
      encoded === undefined ||
      suppliedSignature === undefined
    ) {
      throw new AppError(422, 'INVALID_CURSOR', 'The cursor is invalid.');
    }

    const expectedSignature = createHmac('sha256', this.cursorSecret)
      .update(encoded, 'utf8')
      .digest();
    const suppliedBytes = Buffer.from(suppliedSignature, 'base64url');
    if (
      expectedSignature.length !== suppliedBytes.length ||
      !timingSafeEqual(expectedSignature, suppliedBytes)
    ) {
      throw new AppError(422, 'INVALID_CURSOR', 'The cursor is invalid.');
    }

    try {
      const decoded: unknown = JSON.parse(
        Buffer.from(encoded, 'base64url').toString('utf8'),
      );
      const base = z
        .object({
          kind: z.enum(['changes', 'bootstrap']),
          householdId: z.uuid(),
        })
        .passthrough()
        .parse(decoded);

      if (base.kind === 'changes') {
        return z
          .object({
            kind: z.literal('changes'),
            householdId: z.uuid(),
            sequence: z.string().regex(/^\d+$/),
          })
          .parse(decoded);
      }

      return z
        .object({
          kind: z.literal('bootstrap'),
          householdId: z.uuid(),
          watermark: z.string().regex(/^\d+$/),
          afterId: z.uuid(),
        })
        .parse(decoded);
    } catch {
      throw new AppError(422, 'INVALID_CURSOR', 'The cursor is invalid.');
    }
  }
}
