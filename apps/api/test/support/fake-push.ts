import type { HouseholdActivityNotifier } from '../../src/application/push-notifier.js';
import type { AuthenticatedMember } from '../../src/domain/models.js';
import type {
  PushResult,
  PushSender,
  PushTarget,
} from '../../src/infrastructure/push-sender.js';

/**
 * A notifier that records who it was asked to notify.
 *
 * The push is fired without being awaited, so a test cannot simply read
 * `actors` after the call returns — see `settle()`.
 */
export class RecordingActivityNotifier implements HouseholdActivityNotifier {
  public readonly actors: AuthenticatedMember[] = [];

  /** Set to make the notifier reject, proving a failed send costs nothing. */
  public failure: Error | null = null;

  public notifyOtherMembers(actor: AuthenticatedMember): Promise<void> {
    this.actors.push(actor);
    return this.failure === null
      ? Promise.resolve()
      : Promise.reject(this.failure);
  }

  public reset(): void {
    this.actors.length = 0;
    this.failure = null;
  }

  /**
   * Yields to the microtask queue so a fire-and-forget push has run before the
   * assertion reads `actors`. One turn is enough: `notifyOtherMembers` is called
   * synchronously inside `applyMutations`, and only its result is deferred.
   */
  public static settle(): Promise<void> {
    return Promise.resolve();
  }
}

/** A sender that records its targets and replays a scripted outcome. */
export class RecordingPushSender implements PushSender {
  public readonly batches: PushTarget[][] = [];

  /** Row ids to report as permanently undeliverable on the next send. */
  public retire: string[] = [];

  /** Set to make the send reject, standing in for an outage or a bad key. */
  public failure: Error | null = null;

  public send(targets: PushTarget[]): Promise<PushResult> {
    this.batches.push(targets);

    if (this.failure !== null) {
      return Promise.reject(this.failure);
    }

    const retired = this.retire.filter((id) =>
      targets.some((target) => target.id === id),
    );
    return Promise.resolve({
      delivered: targets.length - retired.length,
      retired,
    });
  }
}
