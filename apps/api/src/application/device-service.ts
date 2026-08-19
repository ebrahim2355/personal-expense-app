import type { DevicePlatform } from '../domain/constants.js';
import type { AuthenticatedMember } from '../domain/models.js';
import type { DatabaseClient } from '../infrastructure/prisma.js';
import type { TokenService } from '../infrastructure/token-service.js';

/**
 * Owns the set of devices that may be woken by a push.
 *
 * Registration is an upsert keyed on the token's hash, so the client is free to
 * call it on every launch: an unchanged token costs one write of `lastSeenAt`
 * and nothing else. That matters because the client cannot reliably tell a
 * token it has already registered from one the server never received.
 */
export class DeviceService {
  public constructor(
    private readonly prisma: DatabaseClient,
    private readonly tokens: TokenService,
  ) {}

  public async register(
    identity: AuthenticatedMember,
    token: string,
    platform: DevicePlatform,
  ): Promise<void> {
    const tokenHash = this.tokens.hashOpaqueToken(token);
    const now = new Date();

    await this.prisma.deviceToken.upsert({
      where: { tokenHash },
      create: {
        householdId: identity.householdId,
        memberId: identity.memberId,
        platform,
        tokenHash,
        token,
      },
      // `memberId` is rewritten deliberately. An FCM token belongs to the app
      // install, not to the signed-in member, so a phone that signs out and
      // back in as the other member keeps it. Leaving the old owner in place
      // would aim this device's pushes at the wrong person: it would be woken
      // for its own changes and silent for the other member's.
      update: {
        householdId: identity.householdId,
        memberId: identity.memberId,
        platform,
        token,
        lastSeenAt: now,
        // A token Google previously rejected is live again if the client is
        // presenting it, so re-registering has to clear the flag or this
        // device would never be woken again.
        disabledAt: null,
      },
    });
  }

  public async unregister(
    identity: AuthenticatedMember,
    token: string,
  ): Promise<void> {
    const tokenHash = this.tokens.hashOpaqueToken(token);

    // Scoped to the household rather than to the member: the caller is the
    // device that owns this token, and the row's member is whoever signed in
    // last, which may already be the other member. Delete rather than disable —
    // the device asked to stop being woken, and it can register again freely.
    //
    // `deleteMany` makes an unknown token a success, matching logout's stance
    // that an already invalid token is also accepted. A sign-out must never
    // fail because the server had nothing to forget.
    await this.prisma.deviceToken.deleteMany({
      where: { tokenHash, householdId: identity.householdId },
    });
  }
}
