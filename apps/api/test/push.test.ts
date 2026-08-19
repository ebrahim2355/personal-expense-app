import { describe, expect, it, vi } from 'vitest';

import {
  PushActivityNotifier,
  disabledActivityNotifier,
} from '../src/application/push-notifier.js';
import type { AppConfig } from '../src/config/env.js';
import type { AuthenticatedMember } from '../src/domain/models.js';
import { createLogger } from '../src/infrastructure/logger.js';
import {
  FirebasePushSender,
  createPushSender,
} from '../src/infrastructure/push-sender.js';
import type { DatabaseClient } from '../src/infrastructure/prisma.js';
import { RecordingPushSender } from './support/fake-push.js';

// Hoisted so the module factories below can close over it: `vi.mock` runs before
// every import, and a plain `const` would still be in its temporal dead zone.
const { sendEach } = vi.hoisted(() => ({
  sendEach: vi.fn(),
}));

vi.mock('firebase-admin/app', () => ({
  cert: (value: unknown) => value,
  initializeApp: () => ({ name: 'household-expenses-push' }),
}));

vi.mock('firebase-admin/messaging', () => ({
  getMessaging: () => ({ sendEach }),
}));

const logger = createLogger({ logLevel: 'silent' } as AppConfig);

const actor: AuthenticatedMember = {
  memberId: '11111111-1111-4111-8111-111111111111',
  householdId: '22222222-2222-4222-8222-222222222222',
  memberKey: 'SUMON',
};

const serviceAccount = {
  projectId: 'household-expenses',
  clientEmail: 'pusher@household-expenses.iam.gserviceaccount.com',
  privateKey: 'unused-by-the-mock',
};

interface DeviceRow {
  id: string;
  token: string;
}

interface DeviceStub {
  prisma: DatabaseClient;
  findMany: ReturnType<typeof vi.fn>;
  updateMany: ReturnType<typeof vi.fn>;
}

/**
 * The two `deviceToken` calls the notifier makes, and nothing else. A stub
 * rather than a database because what is under test is the decision — who gets
 * woken, and which rows a rejection retires — not the SQL.
 */
function deviceStub(rows: DeviceRow[]): DeviceStub {
  const findMany = vi.fn().mockResolvedValue(rows);
  const updateMany = vi.fn().mockResolvedValue({ count: 0 });
  return {
    prisma: {
      deviceToken: { findMany, updateMany },
    } as unknown as DatabaseClient,
    findMany,
    updateMany,
  };
}

function notifier(prisma: DatabaseClient, sender: RecordingPushSender) {
  return new PushActivityNotifier(prisma, sender, logger);
}

describe('PushActivityNotifier', () => {
  it('wakes every device in the household except the author’s own', async () => {
    const stub = deviceStub([{ id: 'row-1', token: 'token-1' }]);
    const sender = new RecordingPushSender();

    await notifier(stub.prisma, sender).notifyOtherMembers(actor);

    // Excluding the author saves a pointless radio wake, and it is why the
    // client's own suppression rule is never the only line of defence.
    expect(stub.findMany).toHaveBeenCalledWith({
      where: {
        householdId: actor.householdId,
        memberId: { not: actor.memberId },
        disabledAt: null,
      },
      select: { id: true, token: true },
    });
    expect(sender.batches).toEqual([[{ id: 'row-1', token: 'token-1' }]]);
  });

  it('sends nothing when the other member has no device registered', async () => {
    const stub = deviceStub([]);
    const sender = new RecordingPushSender();

    await notifier(stub.prisma, sender).notifyOtherMembers(actor);

    expect(sender.batches).toEqual([]);
    expect(stub.updateMany).not.toHaveBeenCalled();
  });

  it('disables only the rows Google reported as gone', async () => {
    const stub = deviceStub([
      { id: 'row-live', token: 'token-live' },
      { id: 'row-gone', token: 'token-gone' },
    ]);
    const sender = new RecordingPushSender();
    sender.retire = ['row-gone'];

    await notifier(stub.prisma, sender).notifyOtherMembers(actor);

    // Disabled, not deleted: a phone that stopped receiving pushes is worth
    // being able to see, and re-registering the same token revives the row.
    expect(stub.updateMany).toHaveBeenCalledTimes(1);
    const call = stub.updateMany.mock.calls[0] as [
      { where: unknown; data: { disabledAt: Date } },
    ];
    expect(call[0].where).toEqual({ id: { in: ['row-gone'] } });
    expect(call[0].data.disabledAt).toBeInstanceOf(Date);
  });

  it('swallows a failed send instead of surfacing it to the mutation', async () => {
    const stub = deviceStub([{ id: 'row-1', token: 'token-1' }]);
    const sender = new RecordingPushSender();
    sender.failure = new Error('Firebase is unreachable.');

    // The mutations have already committed and the client still polls, so the
    // worst a failure costs is the delay push exists to remove.
    await expect(
      notifier(stub.prisma, sender).notifyOtherMembers(actor),
    ).resolves.toBeUndefined();
    expect(stub.updateMany).not.toHaveBeenCalled();
  });

  it('swallows a failed device lookup as well', async () => {
    const findMany = vi.fn().mockRejectedValue(new Error('connection lost'));
    const prisma = {
      deviceToken: { findMany, updateMany: vi.fn() },
    } as unknown as DatabaseClient;

    await expect(
      notifier(prisma, new RecordingPushSender()).notifyOtherMembers(actor),
    ).resolves.toBeUndefined();
  });
});

describe('disabledActivityNotifier', () => {
  // The no-credential state has to cost nothing per mutation, not merely skip
  // the network call: an API without Firebase must behave exactly as it did
  // before push existed.
  it('resolves without querying anything', async () => {
    await expect(
      disabledActivityNotifier.notifyOtherMembers(actor),
    ).resolves.toBeUndefined();
  });
});

describe('createPushSender', () => {
  it('returns null when no credential is configured', () => {
    expect(createPushSender(null)).toBeNull();
  });

  it('builds a sender when a credential is configured', () => {
    expect(createPushSender(serviceAccount)).toBeInstanceOf(FirebasePushSender);
  });
});

describe('FirebasePushSender', () => {
  it('sends one data-only high-priority message to every token', async () => {
    sendEach.mockResolvedValue({
      successCount: 2,
      failureCount: 0,
      responses: [{ success: true }, { success: true }],
    });

    const result = await new FirebasePushSender(serviceAccount).send([
      { id: 'row-1', token: 'token-1' },
      { id: 'row-2', token: 'token-2' },
    ]);

    expect(result).toEqual({ delivered: 2, retired: [] });
    // The three things every message must get right: no `notification` block, so
    // the client composes and the toggle still applies; `high`, or Doze queues
    // it; and one collapse key, so a burst of edits wakes the phone once.
    expect(sendEach).toHaveBeenCalledWith([
      {
        token: 'token-1',
        data: { type: 'household-activity' },
        android: {
          priority: 'high',
          ttl: 1_800_000,
          collapseKey: 'household-activity',
        },
      },
      {
        token: 'token-2',
        data: { type: 'household-activity' },
        android: {
          priority: 'high',
          ttl: 1_800_000,
          collapseKey: 'household-activity',
        },
      },
    ]);
  });

  it('retires a token Google says is no longer registered', async () => {
    sendEach.mockResolvedValue({
      successCount: 1,
      failureCount: 1,
      responses: [
        { success: true },
        {
          success: false,
          error: { code: 'messaging/registration-token-not-registered' },
        },
      ],
    });

    const result = await new FirebasePushSender(serviceAccount).send([
      { id: 'row-live', token: 'token-live' },
      { id: 'row-gone', token: 'token-gone' },
    ]);

    expect(result).toEqual({ delivered: 1, retired: ['row-gone'] });
  });

  it('leaves a row alone when the failure is transient', async () => {
    sendEach.mockResolvedValue({
      successCount: 0,
      failureCount: 1,
      responses: [
        { success: false, error: { code: 'messaging/server-unavailable' } },
      ],
    });

    // Retiring a row on an outage would silence a working phone until its next
    // launch, which is a far worse outcome than one missed wake.
    const result = await new FirebasePushSender(serviceAccount).send([
      { id: 'row-1', token: 'token-1' },
    ]);

    expect(result).toEqual({ delivered: 0, retired: [] });
  });

  it('does not call Google at all for an empty batch', async () => {
    sendEach.mockClear();

    const result = await new FirebasePushSender(serviceAccount).send([]);

    expect(result).toEqual({ delivered: 0, retired: [] });
    expect(sendEach).not.toHaveBeenCalled();
  });
});
