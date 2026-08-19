import { cert, initializeApp } from 'firebase-admin/app';
import {
  getMessaging,
  type Message,
  type Messaging,
} from 'firebase-admin/messaging';

import type { FirebaseServiceAccount } from '../config/env.js';

/**
 * One registered device, paired with the row it came from so a token Google
 * rejects can be traced back and retired.
 */
export interface PushTarget {
  id: string;
  token: string;
}

export interface PushResult {
  delivered: number;
  /**
   * Rows whose token Google says will never be deliverable again — an
   * uninstalled app, or a token replaced by a rotation the server never heard
   * about. Reported rather than deleted here so the caller owns every database
   * write and this class stays a pure boundary to Google.
   */
  retired: string[];
}

/** The boundary to Google. Faked wholesale in tests. */
export interface PushSender {
  send(targets: PushTarget[]): Promise<PushResult>;
}

/**
 * Why the payload carries no detail: the tray draws a server-composed
 * `notification` block before any Dart runs, which would bypass both the
 * author-suppression rule and the household-activity switch — and that switch
 * exists only in the device's own database, where the server cannot read it. So
 * the message is a nudge, the client syncs, and the client decides what to say.
 * Amounts, notes, and member names never reach Google as a side effect.
 */
const PUSH_DATA: Record<string, string> = { type: 'household-activity' };

/**
 * A data-only message defaults to `normal` priority, which Doze queues until the
 * next maintenance window — exactly the delay push exists to remove. `high` is
 * what buys the immediate wake.
 */
const PUSH_PRIORITY = 'high';

/**
 * Half an hour. After that the client's fifteen-minute poll has already brought
 * the change in, so a late wake would spend radio and battery to announce
 * something the device already knows.
 *
 * Milliseconds, not the `1800s` duration string of the FCM HTTP API: the admin
 * SDK takes a number here and silently means milliseconds.
 */
const PUSH_TTL_MILLISECONDS = 1_800_000;

/**
 * One burst of queued edits should wake the phone once. FCM replaces an
 * undelivered message that shares this key rather than stacking it, and since
 * every message says the same thing — "sync, there is something new" — the
 * newest is always a complete substitute for the ones before it.
 */
const PUSH_COLLAPSE_KEY = 'household-activity';

/**
 * The error codes that mean a token is permanently gone. Everything else — a
 * quota rejection, an unavailable backend, a network failure — is transient and
 * must leave the row alone, because deleting it would silence a working phone
 * until its next launch.
 */
const RETIRED_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-argument',
  'messaging/invalid-registration-token',
]);

function errorCode(error: unknown): string | undefined {
  if (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    typeof error.code === 'string'
  ) {
    return error.code;
  }
  return undefined;
}

export class FirebasePushSender implements PushSender {
  private readonly messaging: Messaging;

  public constructor(serviceAccount: FirebaseServiceAccount) {
    // A named app rather than the default one: nothing else in this process
    // uses Firebase, and a named instance keeps it that way explicitly.
    const app = initializeApp(
      { credential: cert(serviceAccount) },
      'household-expenses-push',
    );
    this.messaging = getMessaging(app);
  }

  public async send(targets: PushTarget[]): Promise<PushResult> {
    if (targets.length === 0) {
      return { delivered: 0, retired: [] };
    }

    // One message per token through `sendEach` rather than the multicast helper:
    // multicast now targets Firebase Installation IDs, and the token-based
    // overload is deprecated. `sendEach` still takes registration tokens, which
    // is what the client has, and answers with the same positional batch.
    const messages: Message[] = targets.map((target) => ({
      token: target.token,
      data: PUSH_DATA,
      android: {
        priority: PUSH_PRIORITY,
        ttl: PUSH_TTL_MILLISECONDS,
        collapseKey: PUSH_COLLAPSE_KEY,
      },
    }));
    const response = await this.messaging.sendEach(messages);

    // Responses come back positionally, one per token in the order supplied.
    const retired = response.responses
      .map((result, index) =>
        result.success ||
        !RETIRED_TOKEN_CODES.has(errorCode(result.error) ?? '')
          ? undefined
          : targets[index]?.id,
      )
      .filter((id): id is string => id !== undefined);

    return { delivered: response.successCount, retired };
  }
}

/**
 * Builds a sender when a credential is configured, and null when it is not.
 * Null is a supported state, not a failure: the API serves every route, and
 * clients fall back to the background poll they used before push existed.
 */
export function createPushSender(
  serviceAccount: FirebaseServiceAccount | null,
): PushSender | null {
  return serviceAccount === null
    ? null
    : new FirebasePushSender(serviceAccount);
}
