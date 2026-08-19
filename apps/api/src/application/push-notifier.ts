import type { AuthenticatedMember } from '../domain/models.js';
import type { AppLogger } from '../infrastructure/logger.js';
import type { DatabaseClient } from '../infrastructure/prisma.js';
import type { PushSender } from '../infrastructure/push-sender.js';

/**
 * Wakes the household's *other* devices once a batch of mutations has committed.
 *
 * An interface so `SyncService` neither knows about Firebase nor needs it
 * configured: the disabled implementation below is what runs when no credential
 * is present, and a recording double is what runs in tests.
 */
export interface HouseholdActivityNotifier {
  notifyOtherMembers(actor: AuthenticatedMember): Promise<void>;
}

/**
 * The no-credential state. It skips the device query as well as the send, so an
 * API running without Firebase does no extra database work per mutation — it
 * behaves exactly as it did before push existed.
 */
export const disabledActivityNotifier: HouseholdActivityNotifier = {
  notifyOtherMembers(): Promise<void> {
    return Promise.resolve();
  },
};

export class PushActivityNotifier implements HouseholdActivityNotifier {
  public constructor(
    private readonly prisma: DatabaseClient,
    private readonly sender: PushSender,
    private readonly logger: AppLogger,
  ) {}

  public async notifyOtherMembers(actor: AuthenticatedMember): Promise<void> {
    // The whole body degrades to a logged warning. The mutations are already
    // committed and the client's poll is still in place, so the worst a failed
    // send costs is the delay push was meant to remove — never a lost write and
    // never a failed request.
    try {
      // Excluding the author is defence in depth rather than the rule itself:
      // the client suppresses its own changes from the feed's `actorMember`
      // regardless. It is here because waking the phone that just made the
      // change spends its radio to tell it something it already knows.
      const devices = await this.prisma.deviceToken.findMany({
        where: {
          householdId: actor.householdId,
          memberId: { not: actor.memberId },
          disabledAt: null,
        },
        select: { id: true, token: true },
      });

      if (devices.length === 0) {
        return;
      }

      const result = await this.sender.send(devices);

      if (result.retired.length > 0) {
        // Disabled rather than deleted: a device that stopped receiving pushes
        // is worth being able to see while diagnosing, and re-registering the
        // same token clears the flag.
        await this.prisma.deviceToken.updateMany({
          where: { id: { in: result.retired } },
          data: { disabledAt: new Date() },
        });
      }

      this.logger.info(
        {
          memberKey: actor.memberKey,
          deviceCount: devices.length,
          delivered: result.delivered,
          retired: result.retired.length,
        },
        'household activity push sent',
      );
    } catch (error) {
      this.logger.warn({ err: error }, 'household activity push failed');
    }
  }
}
