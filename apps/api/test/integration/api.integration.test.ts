import { randomUUID } from 'node:crypto';

import * as argon2 from 'argon2';
import request from 'supertest';
import { z } from 'zod';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

import { AuthService } from '../../src/application/auth-service.js';
import { DeviceService } from '../../src/application/device-service.js';
import {
  SyncService,
  lockHouseholdWrites,
} from '../../src/application/sync-service.js';
import { createApp } from '../../src/app.js';
import type { AppConfig } from '../../src/config/env.js';
import { MAX_AMOUNT_MINOR } from '../../src/domain/constants.js';
import type { AuthenticatedMember } from '../../src/domain/models.js';
import { Prisma } from '../../src/generated/prisma/client.js';
import { createLogger } from '../../src/infrastructure/logger.js';
import { createPrismaClient } from '../../src/infrastructure/prisma.js';
import { TokenService } from '../../src/infrastructure/token-service.js';
import { RecordingActivityNotifier } from '../support/fake-push.js';
import { checkedTestDatabaseUrl } from '../support/test-database.js';

const checkedDatabaseUrl = checkedTestDatabaseUrl(
  process.env.TEST_DATABASE_URL,
);
const databaseUrl =
  checkedDatabaseUrl ??
  'postgresql://integration-tests-disabled:unused@127.0.0.1:1/unused';
const hasTestDatabase = checkedDatabaseUrl !== undefined;
const integration = describe.skipIf(!hasTestDatabase);
const pinPepper = 'integration-test-pepper';
const sumonPin = '111111';
const ebrahimPin = '222222';

const config: AppConfig = {
  nodeEnv: 'test',
  port: 3000,
  databaseUrl,
  jwtAccessSecret: 'integration-access-secret-32-characters-minimum',
  cursorSigningSecret: 'integration-cursor-secret-32-characters-minimum',
  jwtIssuer: 'integration-tests',
  jwtAudience: 'integration-mobile',
  accessTokenTtlSeconds: 600,
  refreshTokenTtlDays: 30,
  pinPepper,
  corsAllowedOrigins: new Set<string>(),
  trustProxyHops: 0,
  jsonBodyLimit: '64kb',
  rateLimitMax: 10_000,
  authRateLimitMax: 10_000,
  rateLimitWindowMs: 60_000,
  databasePoolMax: 10,
  databaseConnectionTimeoutMs: 5000,
  logLevel: 'silent',
  firebaseServiceAccount: null,
};

const prisma = createPrismaClient(config);
const tokenService = new TokenService(config);
const authService = new AuthService(prisma, tokenService, config);
const activityNotifier = new RecordingActivityNotifier();
const syncService = new SyncService(prisma, tokenService, activityNotifier);
const deviceService = new DeviceService(prisma, tokenService);
const app = createApp({
  config,
  prisma,
  authService,
  syncService,
  deviceService,
  logger: createLogger(config),
});

const expenseSchema = z.object({
  id: z.uuid(),
  amountMinor: z.number().int(),
  category: z.string(),
  payer: z.string(),
  occurredAt: z.string(),
  note: z.string().nullable(),
  periodId: z.uuid(),
  version: z.number().int(),
  updatedAt: z.string(),
  deletedAt: z.string().nullable(),
});

const periodSchema = z.object({
  id: z.uuid(),
  sequenceNumber: z.number().int(),
  startedAt: z.string(),
  closedAt: z.string().nullable(),
  note: z.string().nullable(),
  version: z.number().int(),
  updatedAt: z.string(),
});

const loanSchema = z.object({
  id: z.uuid(),
  debtor: z.enum(['SUMON', 'EBRAHIM']),
  amountMinor: z.number().int(),
  occurredAt: z.string(),
  note: z.string().nullable(),
  version: z.number().int(),
  updatedAt: z.string(),
  deletedAt: z.string().nullable(),
});

// Every payload-carrying response is discriminated on entityType, so a result
// that names one entity and carries another's snapshot fails to parse instead of
// quietly passing an assertion that only reads the key it expected.
const entityPayloadSchema = z.discriminatedUnion('entityType', [
  z.object({ entityType: z.literal('EXPENSE'), expense: expenseSchema }),
  z.object({ entityType: z.literal('PERIOD'), period: periodSchema }),
  z.object({ entityType: z.literal('LOAN'), loan: loanSchema }),
]);

const appliedShape = {
  mutationId: z.uuid(),
  status: z.literal('APPLIED'),
} as const;

const conflictShape = {
  mutationId: z.uuid(),
  status: z.literal('CONFLICT'),
  code: z.enum(['ENTITY_EXISTS', 'VERSION_CONFLICT']),
} as const;

const mutationResultSchema = z.discriminatedUnion('status', [
  z.discriminatedUnion('entityType', [
    z.object({
      ...appliedShape,
      entityType: z.literal('EXPENSE'),
      expense: expenseSchema,
    }),
    z.object({
      ...appliedShape,
      entityType: z.literal('PERIOD'),
      period: periodSchema,
    }),
    z.object({
      ...appliedShape,
      entityType: z.literal('LOAN'),
      loan: loanSchema,
    }),
  ]),
  z.discriminatedUnion('entityType', [
    z.object({
      ...conflictShape,
      entityType: z.literal('EXPENSE'),
      expense: expenseSchema,
    }),
    z.object({
      ...conflictShape,
      entityType: z.literal('PERIOD'),
      period: periodSchema,
    }),
    z.object({
      ...conflictShape,
      entityType: z.literal('LOAN'),
      loan: loanSchema,
    }),
  ]),
  z.object({
    mutationId: z.uuid(),
    status: z.literal('REJECTED'),
    code: z.string(),
    details: z
      .array(
        z.object({
          path: z.string(),
          code: z.string(),
          message: z.string(),
        }),
      )
      .optional(),
  }),
]);

const mutationResponseSchema = z.object({
  results: z.array(mutationResultSchema),
});

const authResponseSchema = z.object({
  accessToken: z.string(),
  refreshToken: z.string(),
  member: z.object({ key: z.enum(['SUMON', 'EBRAHIM']) }),
});

const changeShape = {
  cursor: z.string(),
  operation: z.enum(['CREATED', 'UPDATED', 'DELETED']),
  actorMember: z.enum(['SUMON', 'EBRAHIM']),
  originMutationId: z.uuid(),
} as const;

const changeSchema = z.discriminatedUnion('entityType', [
  z.object({
    ...changeShape,
    entityType: z.literal('EXPENSE'),
    expense: expenseSchema,
  }),
  z.object({
    ...changeShape,
    entityType: z.literal('PERIOD'),
    period: periodSchema,
  }),
  z.object({
    ...changeShape,
    entityType: z.literal('LOAN'),
    loan: loanSchema,
  }),
]);

const changePageSchema = z.object({
  changes: z.array(changeSchema),
  nextCursor: z.string(),
  hasMore: z.boolean(),
});

const bootstrapPageSchema = z.object({
  items: z.array(entityPayloadSchema),
  watermarkCursor: z.string(),
  nextPageToken: z.string().nullable(),
  hasMore: z.boolean(),
});

type EntityPayloadView = z.infer<typeof entityPayloadSchema>;

/**
 * Reads one payload key out of any envelope that carries it — a mutation
 * result, a change, or a bootstrap item — and fails loudly when the envelope
 * describes a different entity.
 */
function expenseOf(value: unknown): z.infer<typeof expenseSchema> {
  return z.object({ expense: expenseSchema }).parse(value).expense;
}

function periodOf(value: unknown): z.infer<typeof periodSchema> {
  return z.object({ period: periodSchema }).parse(value).period;
}

function loanOf(value: unknown): z.infer<typeof loanSchema> {
  return z.object({ loan: loanSchema }).parse(value).loan;
}

function expenseIdsOf(
  values: { entityType: 'EXPENSE' | 'PERIOD' | 'LOAN' }[],
): string[] {
  return values.flatMap((value) =>
    value.entityType === 'EXPENSE' ? [expenseOf(value).id] : [],
  );
}

type EntityTypeName = 'EXPENSE' | 'PERIOD' | 'LOAN';
type OperationName = 'CREATE' | 'UPDATE' | 'DELETE';

interface ExpenseFields {
  amountMinor: number;
  category:
    | 'GROCERIES'
    | 'UTILITIES'
    | 'TRANSPORT'
    | 'HOUSEHOLD'
    | 'MEDICINE'
    | 'OTHER';
  payer: 'SUMON' | 'EBRAHIM';
  occurredAt: string;
  note: string | null;
  periodId?: string;
}

interface PeriodFields {
  sequenceNumber: number;
  startedAt: string;
  closedAt: string | null;
  note: string | null;
}

interface LoanFields {
  debtor: 'SUMON' | 'EBRAHIM';
  amountMinor: number;
  occurredAt: string;
  note: string | null;
}

const defaultExpense: ExpenseFields = {
  amountMinor: 40_000,
  category: 'GROCERIES',
  payer: 'SUMON',
  occurredAt: '2026-08-13T10:30:00+06:00',
  note: 'Market',
};

const defaultLoan: LoanFields = {
  debtor: 'EBRAHIM',
  amountMinor: 50_000,
  occurredAt: '2026-08-13T10:30:00+06:00',
  note: 'Rickshaw fare',
};

const firstPeriodStartedAt = '2026-08-01T00:00:00+06:00';

let primarySumon: AuthenticatedMember;
let openPeriodId: string;

function createMutation(
  entityType: 'EXPENSE',
  operation: OperationName,
  entityId: string,
  baseVersion: number,
  payload?: ExpenseFields,
  mutationId?: string,
): Record<string, unknown>;
function createMutation(
  entityType: 'PERIOD',
  operation: OperationName,
  entityId: string,
  baseVersion: number,
  payload?: PeriodFields,
  mutationId?: string,
): Record<string, unknown>;
function createMutation(
  entityType: 'LOAN',
  operation: OperationName,
  entityId: string,
  baseVersion: number,
  payload?: LoanFields,
  mutationId?: string,
): Record<string, unknown>;
function createMutation(
  entityType: EntityTypeName,
  operation: OperationName,
  entityId: string,
  baseVersion: number,
  payload?: ExpenseFields | PeriodFields | LoanFields,
  mutationId: string = randomUUID(),
): Record<string, unknown> {
  const payloadKey =
    entityType === 'EXPENSE'
      ? 'expense'
      : entityType === 'PERIOD'
        ? 'period'
        : 'loan';

  return {
    mutationId,
    entityId,
    entityType,
    operation,
    baseVersion,
    ...(payload === undefined ? {} : { [payloadKey]: payload }),
  };
}

async function login(
  member: 'SUMON' | 'EBRAHIM',
  pin: string,
): Promise<z.infer<typeof authResponseSchema>> {
  const response = await request(app)
    .post('/v1/auth/login')
    .send({ member, pin });
  expect(response.status).toBe(200);
  return authResponseSchema.parse(response.body as unknown);
}

async function postMutations(
  accessToken: string,
  mutations: Record<string, unknown>[],
): Promise<z.infer<typeof mutationResponseSchema>> {
  const response = await request(app)
    .post('/v1/sync/mutations')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({ mutations });
  expect(response.status).toBe(200);
  return mutationResponseSchema.parse(response.body as unknown);
}

async function pullChanges(
  accessToken: string,
  query: string,
): Promise<z.infer<typeof changePageSchema>> {
  const response = await request(app)
    .get(query)
    .set('Authorization', `Bearer ${accessToken}`);
  expect(response.status).toBe(200);
  return changePageSchema.parse(response.body as unknown);
}

interface Gate {
  readonly reached: Promise<void>;
  open: () => void;
}

function createGate(): Gate {
  let opener: (() => void) | undefined;
  const reached = new Promise<void>((resolve) => {
    opener = resolve;
  });
  return {
    reached,
    open: (): void => {
      opener?.();
    },
  };
}

// Expenses reference periods and loans reference members under `onDelete:
// Restrict`, so the dependants have to go before the rows they point at.
async function clearMutableData(): Promise<void> {
  await prisma.processedMutation.deleteMany();
  await prisma.expenseChange.deleteMany();
  await prisma.expense.deleteMany();
  await prisma.loanEntry.deleteMany();
  await prisma.spendingPeriod.deleteMany();
  await prisma.refreshToken.deleteMany();
  await prisma.deviceToken.deleteMany();
}

/** Provisions the open period every expense needs, as `bootstrap.ts` does. */
async function openPrimaryPeriod(): Promise<string> {
  const period = await prisma.spendingPeriod.create({
    data: {
      id: randomUUID(),
      householdId: primarySumon.householdId,
      sequenceNumber: 1,
      startedAt: new Date(firstPeriodStartedAt),
    },
  });

  return period.id;
}

async function collectBootstrap(
  accessToken: string,
  limit: number,
): Promise<EntityPayloadView[]> {
  const items: EntityPayloadView[] = [];
  let pageToken: string | null = null;
  let watermark: string | undefined;

  do {
    const query =
      pageToken === null
        ? `/v1/sync/bootstrap?limit=${String(limit)}`
        : `/v1/sync/bootstrap?limit=${String(limit)}&pageToken=${encodeURIComponent(pageToken)}`;
    const response = await request(app)
      .get(query)
      .set('Authorization', `Bearer ${accessToken}`);
    const page = bootstrapPageSchema.parse(response.body as unknown);
    watermark ??= page.watermarkCursor;
    expect(page.watermarkCursor).toBe(watermark);
    items.push(...page.items);
    pageToken = page.nextPageToken;
  } while (pageToken !== null);

  return items;
}

integration('PostgreSQL API integration', () => {
  beforeAll(async () => {
    await clearMutableData();
    await prisma.member.deleteMany();
    await prisma.household.deleteMany();

    const pinHash = await argon2.hash(`${sumonPin}${pinPepper}`, {
      type: argon2.argon2id,
      memoryCost: 19_456,
      timeCost: 2,
      parallelism: 1,
    });
    const ebrahimHash = await argon2.hash(`${ebrahimPin}${pinPepper}`, {
      type: argon2.argon2id,
      memoryCost: 19_456,
      timeCost: 2,
      parallelism: 1,
    });

    const primary = await prisma.household.create({
      data: { slug: `primary-${randomUUID()}`, name: 'Primary test household' },
    });
    const primaryMembers = await Promise.all([
      prisma.member.create({
        data: {
          householdId: primary.id,
          key: 'SUMON',
          displayName: 'Sumon',
          pinHash,
        },
      }),
      prisma.member.create({
        data: {
          householdId: primary.id,
          key: 'EBRAHIM',
          displayName: 'Ebrahim',
          pinHash: ebrahimHash,
        },
      }),
    ]);

    const primaryMember = primaryMembers[0];
    if (primaryMember === undefined) {
      throw new Error('Test members were not created.');
    }

    primarySumon = {
      memberId: primaryMember.id,
      householdId: primary.id,
      memberKey: 'SUMON',
    };
    openPeriodId = await openPrimaryPeriod();
  }, 30_000);

  beforeEach(async () => {
    await clearMutableData();
    activityNotifier.reset();
    openPeriodId = await openPrimaryPeriod();
  });

  afterAll(async () => {
    await clearMutableData();
    await prisma.member.deleteMany();
    await prisma.household.deleteMany();
    await prisma.$disconnect();
  });

  it('authenticates valid credentials, rejects failures, rotates refresh tokens, and logs out', async () => {
    const failed = await request(app)
      .post('/v1/auth/login')
      .send({ member: 'SUMON', pin: '999999' });
    expect(failed.status).toBe(401);
    expect(
      z
        .object({ error: z.object({ code: z.literal('INVALID_CREDENTIALS') }) })
        .parse(failed.body as unknown),
    ).toBeDefined();

    const unauthorized = await request(app).get('/v1/auth/me');
    expect(unauthorized.status).toBe(401);

    const session = await login('SUMON', sumonPin);
    const me = await request(app)
      .get('/v1/auth/me')
      .set('Authorization', `Bearer ${session.accessToken}`);
    expect(me.status).toBe(200);

    const refreshedResponse = await request(app)
      .post('/v1/auth/refresh')
      .send({ refreshToken: session.refreshToken });
    expect(refreshedResponse.status).toBe(200);
    const refreshed = authResponseSchema.parse(
      refreshedResponse.body as unknown,
    );
    expect(refreshed.refreshToken).not.toBe(session.refreshToken);

    const reused = await request(app)
      .post('/v1/auth/refresh')
      .send({ refreshToken: session.refreshToken });
    expect(reused.status).toBe(401);

    const revokedFamily = await request(app)
      .post('/v1/auth/refresh')
      .send({ refreshToken: refreshed.refreshToken });
    expect(revokedFamily.status).toBe(401);

    const logoutSession = await login('EBRAHIM', ebrahimPin);
    const logout = await request(app)
      .post('/v1/auth/logout')
      .set('Authorization', `Bearer ${logoutSession.accessToken}`)
      .send({ refreshToken: logoutSession.refreshToken });
    expect(logout.status).toBe(204);

    const loggedOutRefresh = await request(app)
      .post('/v1/auth/refresh')
      .send({ refreshToken: logoutSession.refreshToken });
    expect(loggedOutRefresh.status).toBe(401);
  });

  it('serializes concurrent refresh reuse and revokes the issued family', async () => {
    const session = await login('SUMON', sumonPin);
    const responses = await Promise.all([
      request(app)
        .post('/v1/auth/refresh')
        .send({ refreshToken: session.refreshToken }),
      request(app)
        .post('/v1/auth/refresh')
        .send({ refreshToken: session.refreshToken }),
    ]);

    expect(responses.map((response) => response.status).sort()).toEqual([
      200, 401,
    ]);
    const successfulResponse = responses.find(
      (response) => response.status === 200,
    );
    expect(successfulResponse).toBeDefined();
    if (successfulResponse === undefined) {
      throw new Error('Expected one concurrent refresh request to succeed.');
    }
    const successful = authResponseSchema.parse(
      successfulResponse.body as unknown,
    );

    const revokedReplacement = await request(app)
      .post('/v1/auth/refresh')
      .send({ refreshToken: successful.refreshToken });
    expect(revokedReplacement.status).toBe(401);
  }, 30_000);

  it('creates exactly one expense when a mutation response is retried', async () => {
    const session = await login('SUMON', sumonPin);
    const entityId = randomUUID();
    const mutationId = randomUUID();
    const mutation = createMutation(
      'EXPENSE',
      'CREATE',
      entityId,
      0,
      defaultExpense,
      mutationId,
    );

    const first = await postMutations(session.accessToken, [mutation]);
    const retried = await postMutations(session.accessToken, [mutation]);

    expect(first.results[0]).toEqual(retried.results[0]);
    expect(first.results[0]?.status).toBe('APPLIED');
    expect(await prisma.expense.count({ where: { id: entityId } })).toBe(1);
    expect(
      await prisma.processedMutation.count({ where: { mutationId } }),
    ).toBe(1);
    expect(
      await prisma.expenseChange.count({
        where: { originMutationId: mutationId },
      }),
    ).toBe(1);
  });

  it('merges two offline clients without loss or duplicate rows', async () => {
    const [sumon, ebrahim] = await Promise.all([
      login('SUMON', sumonPin),
      login('EBRAHIM', ebrahimPin),
    ]);
    const sumonEntity = randomUUID();
    const ebrahimEntity = randomUUID();

    const [sumonResult, ebrahimResult] = await Promise.all([
      postMutations(sumon.accessToken, [
        createMutation('EXPENSE', 'CREATE', sumonEntity, 0, defaultExpense),
      ]),
      postMutations(ebrahim.accessToken, [
        createMutation('EXPENSE', 'CREATE', ebrahimEntity, 0, {
          ...defaultExpense,
          amountMinor: 25_000,
          payer: 'EBRAHIM',
        }),
      ]),
    ]);

    expect(sumonResult.results[0]?.status).toBe('APPLIED');
    expect(ebrahimResult.results[0]?.status).toBe('APPLIED');
    expect(await prisma.expense.count()).toBe(2);
    expect(await prisma.expenseChange.count()).toBe(2);

    const page = await pullChanges(
      sumon.accessToken,
      '/v1/sync/changes?limit=10',
    );
    expect(new Set(expenseIdsOf(page.changes))).toEqual(
      new Set([sumonEntity, ebrahimEntity]),
    );
    // Each change names its own author, which is how a pulling device tells the
    // other member's activity apart from its own writes echoing back.
    const authorByEntity = new Map(
      page.changes.map((change) => [expenseOf(change).id, change.actorMember]),
    );
    expect(authorByEntity.get(sumonEntity)).toBe('SUMON');
    expect(authorByEntity.get(ebrahimEntity)).toBe('EBRAHIM');
  });

  it('propagates updates and soft-delete tombstones', async () => {
    const session = await login('SUMON', sumonPin);
    const entityId = randomUUID();
    await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'CREATE', entityId, 0, defaultExpense),
    ]);
    const initialPage = await pullChanges(
      session.accessToken,
      '/v1/sync/changes?limit=10',
    );

    const updated = await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'UPDATE', entityId, 1, {
        ...defaultExpense,
        amountMinor: 55_500,
        note: 'Updated',
      }),
    ]);
    expect(expenseOf(updated.results[0]).version).toBe(2);

    const deleted = await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'DELETE', entityId, 2),
    ]);
    expect(expenseOf(deleted.results[0]).version).toBe(3);
    expect(expenseOf(deleted.results[0]).deletedAt).not.toBeNull();

    const page = await pullChanges(
      session.accessToken,
      `/v1/sync/changes?limit=10&cursor=${encodeURIComponent(initialPage.nextCursor)}`,
    );
    expect(page.changes.map((change) => change.operation)).toEqual([
      'UPDATED',
      'DELETED',
    ]);
    expect(expenseOf(page.changes[1]).deletedAt).not.toBeNull();

    const stored = await prisma.expense.findUnique({ where: { id: entityId } });
    expect(stored).not.toBeNull();
    expect(stored?.deletedAt).not.toBeNull();
  });

  it('returns the authoritative server entity for a stale baseVersion', async () => {
    const session = await login('SUMON', sumonPin);
    const entityId = randomUUID();
    await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'CREATE', entityId, 0, defaultExpense),
    ]);
    await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'UPDATE', entityId, 1, {
        ...defaultExpense,
        amountMinor: 70_000,
      }),
    ]);

    const siblingEntityId = randomUUID();
    const stale = await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'UPDATE', entityId, 1, {
        ...defaultExpense,
        amountMinor: 90_000,
      }),
      createMutation('EXPENSE', 'CREATE', siblingEntityId, 0, defaultExpense),
    ]);

    expect(stale.results[0]).toMatchObject({
      status: 'CONFLICT',
      code: 'VERSION_CONFLICT',
      entityType: 'EXPENSE',
      expense: { id: entityId, version: 2, amountMinor: 70_000 },
    });
    expect(stale.results[1]).toMatchObject({
      status: 'APPLIED',
      entityType: 'EXPENSE',
      expense: { id: siblingEntityId, version: 1 },
    });
    expect(
      (await prisma.expense.findUnique({ where: { id: entityId } }))
        ?.amountMinor,
    ).toBe(70_000n);
    expect(await prisma.expense.count()).toBe(2);
  });

  it('paginates change cursors and bootstraps tombstones', async () => {
    const session = await login('SUMON', sumonPin);
    const entityIds = [randomUUID(), randomUUID(), randomUUID()];
    await postMutations(
      session.accessToken,
      entityIds.map((entityId, index) =>
        createMutation('EXPENSE', 'CREATE', entityId, 0, {
          ...defaultExpense,
          amountMinor: 10_000 + index * 100,
        }),
      ),
    );
    const deletedId = entityIds[1];
    if (deletedId === undefined) {
      throw new Error('Missing test entity ID.');
    }
    await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'DELETE', deletedId, 1),
    ]);

    const firstPull = await pullChanges(
      session.accessToken,
      '/v1/sync/changes?limit=2',
    );
    expect(firstPull.changes).toHaveLength(2);
    expect(firstPull.hasMore).toBe(true);

    const secondPull = await pullChanges(
      session.accessToken,
      `/v1/sync/changes?limit=2&cursor=${encodeURIComponent(firstPull.nextCursor)}`,
    );
    expect(secondPull.changes).toHaveLength(2);
    expect(secondPull.hasMore).toBe(false);
    expect(secondPull.changes.at(-1)?.operation).toBe('DELETED');

    const bootstrapItems = await collectBootstrap(session.accessToken, 1);

    // The open period arrives ahead of the three expenses that reference it.
    expect(bootstrapItems.map((item) => item.entityType)).toEqual([
      'PERIOD',
      'EXPENSE',
      'EXPENSE',
      'EXPENSE',
    ]);
    expect(periodOf(bootstrapItems[0]).id).toBe(openPeriodId);
    expect(
      bootstrapItems
        .slice(1)
        .map((item) => expenseOf(item))
        .find((expense) => expense.id === deletedId)?.deletedAt,
    ).not.toBeNull();
  });

  it('walks periods, expenses, and loans in order across bootstrap pages', async () => {
    const session = await login('SUMON', sumonPin);
    await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'CREATE', randomUUID(), 0, defaultExpense),
      createMutation('LOAN', 'CREATE', randomUUID(), 0, defaultLoan),
    ]);

    const paged = await collectBootstrap(session.accessToken, 1);
    const single = await collectBootstrap(session.accessToken, 50);

    expect(paged.map((item) => item.entityType)).toEqual([
      'PERIOD',
      'EXPENSE',
      'LOAN',
    ]);
    expect(single).toEqual(paged);
    expect(loanOf(paged[2]).debtor).toBe('EBRAHIM');
  });

  it('delivers a change whose sequence was allocated before a later change committed', async () => {
    const householdId = primarySumon.householdId;
    const allocatedFirstId = randomUUID();
    const committedFirstId = randomUUID();
    const allocated = createGate();
    const release = createGate();
    const occurredAt = new Date('2026-08-13T04:30:00.000Z');
    const changedAt = new Date('2026-08-13T05:30:00.000Z');

    // A mutation from the other device that has already taken its change
    // sequence number but has not committed yet. The fixture writes at Read
    // Committed so it stays out of Serializable conflict detection: on a nearly
    // empty table those predicate locks cover whole index pages and would abort
    // one of the two writers, hiding the ordering hazard under test.
    const inFlight = prisma.$transaction(
      async (transaction) => {
        await lockHouseholdWrites(transaction, householdId);
        await transaction.expense.create({
          data: {
            id: allocatedFirstId,
            householdId,
            amountMinor: 30_000n,
            category: 'GROCERIES',
            payerId: primarySumon.memberId,
            periodId: openPeriodId,
            occurredAt,
            note: 'Allocated first',
            version: 1,
            createdAt: changedAt,
            updatedAt: changedAt,
          },
        });
        const change = await transaction.expenseChange.create({
          data: {
            householdId,
            entityId: allocatedFirstId,
            entityType: 'EXPENSE',
            entityVersion: 1,
            operation: 'CREATED',
            actorMemberKey: 'SUMON',
            originMutationId: randomUUID(),
            snapshot: {
              id: allocatedFirstId,
              amountMinor: 30_000,
              category: 'GROCERIES',
              payer: 'SUMON',
              occurredAt: occurredAt.toISOString(),
              note: 'Allocated first',
              periodId: openPeriodId,
              version: 1,
              updatedAt: changedAt.toISOString(),
              deletedAt: null,
            },
            changedAt,
          },
        });
        await transaction.expense.update({
          where: { id: allocatedFirstId },
          data: { lastChangeSequence: change.sequence },
        });
        allocated.open();
        await release.reached;
      },
      {
        isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted,
        timeout: 20_000,
        maxWait: 10_000,
      },
    );
    await allocated.reached;

    const push = syncService.applyMutations(primarySumon, [
      createMutation('EXPENSE', 'CREATE', committedFirstId, 0, {
        ...defaultExpense,
        amountMinor: 12_300,
      }) as never,
    ]);
    await new Promise<void>((resolve) => {
      setTimeout(resolve, 500);
    });

    // This is the poll that used to strand the earlier change: whatever it
    // reports, the cursor it hands back must not skip the in-flight sequence.
    const firstPage = await syncService.getChanges(primarySumon, undefined, 50);
    release.open();
    await inFlight;
    const pushed = await push;
    expect(pushed[0]?.status).toBe('APPLIED');

    const secondPage = await syncService.getChanges(
      primarySumon,
      firstPage.nextCursor,
      50,
    );
    const delivered = expenseIdsOf([
      ...firstPage.changes,
      ...secondPage.changes,
    ]);
    expect(delivered).toEqual([allocatedFirstId, committedFirstId]);
    expect(await prisma.expenseChange.count({ where: { householdId } })).toBe(
      2,
    );
  }, 40_000);

  it('scopes service reads and writes to the authenticated household', async () => {
    const isolatedHousehold = await prisma.household.create({
      data: {
        slug: `isolated-${randomUUID()}`,
        name: 'Isolated test household',
      },
    });
    const isolatedMember = await prisma.member.create({
      data: {
        householdId: isolatedHousehold.id,
        key: 'SUMON',
        displayName: 'Sumon',
        pinHash: 'not-used-by-this-service-level-test',
      },
    });
    // The isolated household is provisioned well enough to record its own
    // expenses, so the only thing it is missing is the entity under test. That
    // keeps the rejection specific: a household that had no open period would
    // report PERIOD_NOT_FOUND and hide whether the expense leaked.
    const isolatedPeriod = await prisma.spendingPeriod.create({
      data: {
        id: randomUUID(),
        householdId: isolatedHousehold.id,
        sequenceNumber: 1,
        startedAt: new Date(firstPeriodStartedAt),
      },
    });
    const isolatedSumon: AuthenticatedMember = {
      memberId: isolatedMember.id,
      householdId: isolatedHousehold.id,
      memberKey: 'SUMON',
    };
    const entityId = randomUUID();

    try {
      const created = await syncService.applyMutations(primarySumon, [
        createMutation(
          'EXPENSE',
          'CREATE',
          entityId,
          0,
          defaultExpense,
        ) as never,
      ]);
      expect(created[0]?.status).toBe('APPLIED');

      const crossHousehold = await syncService.applyMutations(isolatedSumon, [
        createMutation('EXPENSE', 'UPDATE', entityId, 1, {
          ...defaultExpense,
          amountMinor: 99_900,
        }) as never,
      ]);
      expect(crossHousehold[0]).toMatchObject({
        status: 'REJECTED',
        code: 'ENTITY_NOT_FOUND',
      });

      const isolatedChanges = await syncService.getChanges(
        isolatedSumon,
        undefined,
        10,
      );
      const isolatedBootstrap = await syncService.bootstrap(
        isolatedSumon,
        undefined,
        10,
      );
      expect(isolatedChanges.changes).toEqual([]);
      expect(isolatedBootstrap.items.map((item) => item.entityType)).toEqual([
        'PERIOD',
      ]);
      expect(periodOf(isolatedBootstrap.items[0]).id).toBe(isolatedPeriod.id);
      expect(
        (await prisma.expense.findUniqueOrThrow({ where: { id: entityId } }))
          .amountMinor,
      ).toBe(40_000n);
      expect(
        await prisma.expense.count({
          where: { householdId: isolatedSumon.householdId },
        }),
      ).toBe(0);
    } finally {
      await prisma.processedMutation.deleteMany({
        where: { householdId: isolatedHousehold.id },
      });
      await prisma.expenseChange.deleteMany({
        where: { householdId: isolatedHousehold.id },
      });
      await prisma.expense.deleteMany({
        where: { householdId: isolatedHousehold.id },
      });
      await prisma.loanEntry.deleteMany({
        where: { householdId: isolatedHousehold.id },
      });
      await prisma.spendingPeriod.deleteMany({
        where: { householdId: isolatedHousehold.id },
      });
      await prisma.member.deleteMany({
        where: { householdId: isolatedHousehold.id },
      });
      await prisma.household.delete({ where: { id: isolatedHousehold.id } });
    }
  });

  it('returns a per-mutation validation rejection without applying sibling-invalid data', async () => {
    const session = await login('SUMON', sumonPin);
    const validEntity = randomUUID();
    const response = await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'CREATE', randomUUID(), 0, {
        ...defaultExpense,
        amountMinor: 0,
      }),
      createMutation('EXPENSE', 'CREATE', validEntity, 0, defaultExpense),
    ]);

    expect(response.results[0]).toMatchObject({
      status: 'REJECTED',
      code: 'INVALID_MUTATION',
    });
    expect(response.results[1]?.status).toBe('APPLIED');
    expect(await prisma.expense.count()).toBe(1);
  });

  it.each([99, 150, 12_345, MAX_AMOUNT_MINOR])(
    'rejects the non-whole-taka amount %s',
    async (amountMinor) => {
      const session = await login('SUMON', sumonPin);
      const response = await postMutations(session.accessToken, [
        createMutation('EXPENSE', 'CREATE', randomUUID(), 0, {
          ...defaultExpense,
          amountMinor,
        }),
        createMutation('LOAN', 'CREATE', randomUUID(), 0, {
          ...defaultLoan,
          amountMinor,
        }),
      ]);

      expect(response.results[0]).toMatchObject({
        status: 'REJECTED',
        code: 'INVALID_MUTATION',
      });
      expect(response.results[1]).toMatchObject({
        status: 'REJECTED',
        code: 'INVALID_MUTATION',
      });
      expect(await prisma.expense.count()).toBe(0);
      expect(await prisma.loanEntry.count()).toBe(0);
    },
  );

  it('accepts one taka, the smallest amount the contract allows', async () => {
    const session = await login('SUMON', sumonPin);
    const response = await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'CREATE', randomUUID(), 0, {
        ...defaultExpense,
        amountMinor: 100,
      }),
    ]);

    expect(expenseOf(response.results[0]).amountMinor).toBe(100);
  });

  it('stores offset timestamps as UTC instants', async () => {
    const session = await login('SUMON', sumonPin);
    const entityId = randomUUID();
    await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'CREATE', entityId, 0, {
        ...defaultExpense,
        occurredAt: '2026-08-01T00:00:00+06:00',
      }),
    ]);

    const stored = await prisma.expense.findUnique({ where: { id: entityId } });
    expect(stored?.occurredAt.toISOString()).toBe('2026-07-31T18:00:00.000Z');
  });

  it('files an expense in the open period when periodId is omitted', async () => {
    const session = await login('SUMON', sumonPin);
    const response = await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'CREATE', randomUUID(), 0, defaultExpense),
    ]);

    expect(expenseOf(response.results[0]).periodId).toBe(openPeriodId);
  });

  it('honours an explicitly named period', async () => {
    const session = await login('SUMON', sumonPin);
    const response = await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'CREATE', randomUUID(), 0, {
        ...defaultExpense,
        periodId: openPeriodId,
      }),
    ]);

    expect(expenseOf(response.results[0]).periodId).toBe(openPeriodId);
  });

  it('rejects an expense that names a period the household does not have', async () => {
    const session = await login('SUMON', sumonPin);
    const response = await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'CREATE', randomUUID(), 0, {
        ...defaultExpense,
        periodId: randomUUID(),
      }),
    ]);

    expect(response.results[0]).toMatchObject({
      status: 'REJECTED',
      code: 'PERIOD_NOT_FOUND',
    });
    expect(await prisma.expense.count()).toBe(0);
  });

  it('admits an offline expense into the period it was recorded in, even once closed', async () => {
    const session = await login('SUMON', sumonPin);
    const nextPeriodId = randomUUID();
    const closed = await postMutations(session.accessToken, [
      createMutation('PERIOD', 'UPDATE', openPeriodId, 1, {
        sequenceNumber: 1,
        startedAt: firstPeriodStartedAt,
        closedAt: '2026-08-31T23:59:00+06:00',
        note: null,
      }),
      createMutation('PERIOD', 'CREATE', nextPeriodId, 0, {
        sequenceNumber: 2,
        startedAt: '2026-09-01T00:00:00+06:00',
        closedAt: null,
        note: null,
      }),
    ]);
    expect(closed.results.map((result) => result.status)).toEqual([
      'APPLIED',
      'APPLIED',
    ]);

    const late = await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'CREATE', randomUUID(), 0, {
        ...defaultExpense,
        periodId: openPeriodId,
      }),
      createMutation('EXPENSE', 'CREATE', randomUUID(), 0, defaultExpense),
    ]);

    expect(expenseOf(late.results[0]).periodId).toBe(openPeriodId);
    // An expense that names nothing lands in whichever period is open now.
    expect(expenseOf(late.results[1]).periodId).toBe(nextPeriodId);
  });

  it('closes one period and opens the next in a single batch', async () => {
    const session = await login('SUMON', sumonPin);
    const nextPeriodId = randomUUID();
    const response = await postMutations(session.accessToken, [
      createMutation('PERIOD', 'UPDATE', openPeriodId, 1, {
        sequenceNumber: 1,
        startedAt: firstPeriodStartedAt,
        closedAt: '2026-08-31T23:59:00+06:00',
        note: null,
      }),
      createMutation('PERIOD', 'CREATE', nextPeriodId, 0, {
        sequenceNumber: 2,
        startedAt: '2026-09-01T00:00:00+06:00',
        closedAt: null,
        note: null,
      }),
    ]);

    expect(periodOf(response.results[0])).toMatchObject({
      id: openPeriodId,
      version: 2,
    });
    expect(periodOf(response.results[0]).closedAt).not.toBeNull();
    expect(periodOf(response.results[1])).toMatchObject({
      id: nextPeriodId,
      sequenceNumber: 2,
      closedAt: null,
      version: 1,
    });
    expect(
      await prisma.spendingPeriod.count({
        where: { householdId: primarySumon.householdId, closedAt: null },
      }),
    ).toBe(1);

    const page = await pullChanges(
      session.accessToken,
      '/v1/sync/changes?limit=10',
    );
    expect(
      page.changes.map((change) => [change.entityType, change.operation]),
    ).toEqual([
      ['PERIOD', 'UPDATED'],
      ['PERIOD', 'CREATED'],
    ]);
  });

  it('keeps a household to one open period at a time', async () => {
    const session = await login('SUMON', sumonPin);
    const response = await postMutations(session.accessToken, [
      createMutation('PERIOD', 'CREATE', randomUUID(), 0, {
        sequenceNumber: 2,
        startedAt: '2026-09-01T00:00:00+06:00',
        closedAt: null,
        note: null,
      }),
    ]);

    expect(response.results[0]).toMatchObject({
      status: 'REJECTED',
      code: 'PERIOD_ALREADY_OPEN',
    });
    expect(
      await prisma.spendingPeriod.count({
        where: { householdId: primarySumon.householdId },
      }),
    ).toBe(1);
  });

  it('refuses to reopen a settled period or to delete one', async () => {
    const session = await login('SUMON', sumonPin);
    await postMutations(session.accessToken, [
      createMutation('PERIOD', 'UPDATE', openPeriodId, 1, {
        sequenceNumber: 1,
        startedAt: firstPeriodStartedAt,
        closedAt: '2026-08-31T23:59:00+06:00',
        note: null,
      }),
    ]);

    const refused = await postMutations(session.accessToken, [
      createMutation('PERIOD', 'UPDATE', openPeriodId, 2, {
        sequenceNumber: 1,
        startedAt: firstPeriodStartedAt,
        closedAt: null,
        note: null,
      }),
      createMutation('PERIOD', 'DELETE', openPeriodId, 2),
    ]);

    expect(refused.results[0]).toMatchObject({
      status: 'REJECTED',
      code: 'INVALID_MUTATION',
    });
    expect(refused.results[1]).toMatchObject({
      status: 'REJECTED',
      code: 'INVALID_MUTATION',
    });
    expect(
      (
        await prisma.spendingPeriod.findUniqueOrThrow({
          where: { id: openPeriodId },
        })
      ).closedAt,
    ).not.toBeNull();
  });

  it('records, edits, and soft-deletes a loan without touching expenses', async () => {
    const session = await login('SUMON', sumonPin);
    const loanId = randomUUID();

    const created = await postMutations(session.accessToken, [
      createMutation('LOAN', 'CREATE', loanId, 0, defaultLoan),
    ]);
    expect(created.results[0]).toMatchObject({
      status: 'APPLIED',
      entityType: 'LOAN',
    });
    expect(loanOf(created.results[0])).toMatchObject({
      id: loanId,
      debtor: 'EBRAHIM',
      amountMinor: 50_000,
      version: 1,
      deletedAt: null,
    });

    const updated = await postMutations(session.accessToken, [
      createMutation('LOAN', 'UPDATE', loanId, 1, {
        ...defaultLoan,
        debtor: 'SUMON',
        amountMinor: 20_000,
        note: 'Corrected',
      }),
    ]);
    expect(loanOf(updated.results[0])).toMatchObject({
      debtor: 'SUMON',
      amountMinor: 20_000,
      note: 'Corrected',
      version: 2,
    });

    const deleted = await postMutations(session.accessToken, [
      createMutation('LOAN', 'DELETE', loanId, 2),
    ]);
    expect(loanOf(deleted.results[0]).version).toBe(3);
    expect(loanOf(deleted.results[0]).deletedAt).not.toBeNull();

    const page = await pullChanges(
      session.accessToken,
      '/v1/sync/changes?limit=10',
    );
    expect(
      page.changes.map((change) => [change.entityType, change.operation]),
    ).toEqual([
      ['LOAN', 'CREATED'],
      ['LOAN', 'UPDATED'],
      ['LOAN', 'DELETED'],
    ]);
    expect(await prisma.expense.count()).toBe(0);
    expect(
      (await prisma.loanEntry.findUniqueOrThrow({ where: { id: loanId } }))
        .deletedAt,
    ).not.toBeNull();
  });

  it('replays a period and a loan receipt without writing twice', async () => {
    const session = await login('SUMON', sumonPin);
    const loanId = randomUUID();
    const batch = [
      createMutation('PERIOD', 'UPDATE', openPeriodId, 1, {
        sequenceNumber: 1,
        startedAt: firstPeriodStartedAt,
        closedAt: '2026-08-31T23:59:00+06:00',
        note: null,
      }),
      createMutation('LOAN', 'CREATE', loanId, 0, defaultLoan),
    ];

    const first = await postMutations(session.accessToken, batch);
    const replayed = await postMutations(session.accessToken, batch);

    expect(replayed.results).toEqual(first.results);
    expect(await prisma.expenseChange.count()).toBe(2);
    expect(
      (
        await prisma.spendingPeriod.findUniqueOrThrow({
          where: { id: openPeriodId },
        })
      ).version,
    ).toBe(2);
    expect(await prisma.loanEntry.count({ where: { id: loanId } })).toBe(1);
  });

  it('registers a device once per token and stops waking it on unregister', async () => {
    const session = await login('SUMON', sumonPin);
    const token = `d${'0'.repeat(150)}`;

    const registered = await request(app)
      .post('/v1/devices')
      .set('Authorization', `Bearer ${session.accessToken}`)
      .send({ token, platform: 'ANDROID' });
    expect(registered.status).toBe(204);

    // The client re-registers on every launch because it cannot tell a token the
    // server already has from one that never arrived. That must stay one row.
    const again = await request(app)
      .post('/v1/devices')
      .set('Authorization', `Bearer ${session.accessToken}`)
      .send({ token, platform: 'ANDROID' });
    expect(again.status).toBe(204);

    const stored = await prisma.deviceToken.findMany();
    expect(stored).toHaveLength(1);
    expect(stored[0]?.token).toBe(token);
    expect(stored[0]?.memberId).toBe(primarySumon.memberId);
    expect(stored[0]?.householdId).toBe(primarySumon.householdId);
    expect(stored[0]?.disabledAt).toBeNull();

    const removed = await request(app)
      .post('/v1/devices/unregister')
      .set('Authorization', `Bearer ${session.accessToken}`)
      .send({ token });
    expect(removed.status).toBe(204);
    expect(await prisma.deviceToken.count()).toBe(0);

    // A sign-out must never fail because the server had nothing to forget.
    const removedAgain = await request(app)
      .post('/v1/devices/unregister')
      .set('Authorization', `Bearer ${session.accessToken}`)
      .send({ token });
    expect(removedAgain.status).toBe(204);
  });

  it('moves a device to whichever member signed in last', async () => {
    const token = `s${'1'.repeat(150)}`;
    const sumon = await login('SUMON', sumonPin);
    const ebrahim = await login('EBRAHIM', ebrahimPin);

    await request(app)
      .post('/v1/devices')
      .set('Authorization', `Bearer ${sumon.accessToken}`)
      .send({ token, platform: 'ANDROID' });
    await request(app)
      .post('/v1/devices')
      .set('Authorization', `Bearer ${ebrahim.accessToken}`)
      .send({ token, platform: 'ANDROID' });

    // An FCM token belongs to the install, not the member. Leaving the first
    // owner in place would wake this phone for its own changes and leave it
    // silent for the other member's — precisely backwards.
    const stored = await prisma.deviceToken.findMany();
    expect(stored).toHaveLength(1);
    expect(stored[0]?.memberId).not.toBe(primarySumon.memberId);
  });

  it('rejects a device registration that is unauthenticated or malformed', async () => {
    const token = `x${'2'.repeat(150)}`;
    const session = await login('SUMON', sumonPin);

    const anonymous = await request(app)
      .post('/v1/devices')
      .send({ token, platform: 'ANDROID' });
    expect(anonymous.status).toBe(401);

    const extraField = await request(app)
      .post('/v1/devices')
      .set('Authorization', `Bearer ${session.accessToken}`)
      .send({ token, platform: 'ANDROID', nickname: 'phone' });
    expect(extraField.status).toBe(422);

    const shortToken = await request(app)
      .post('/v1/devices')
      .set('Authorization', `Bearer ${session.accessToken}`)
      .send({ token: 'too-short', platform: 'ANDROID' });
    expect(shortToken.status).toBe(422);

    const foreignPlatform = await request(app)
      .post('/v1/devices')
      .set('Authorization', `Bearer ${session.accessToken}`)
      .send({ token, platform: 'IOS' });
    expect(foreignPlatform.status).toBe(422);

    expect(await prisma.deviceToken.count()).toBe(0);
  });

  it('wakes the household only when a mutation actually landed', async () => {
    const session = await login('SUMON', sumonPin);
    const batch = [
      createMutation('EXPENSE', 'CREATE', randomUUID(), 0, defaultExpense),
    ];

    await postMutations(session.accessToken, batch);
    await RecordingActivityNotifier.settle();
    expect(activityNotifier.actors).toHaveLength(1);
    expect(activityNotifier.actors[0]?.memberId).toBe(primarySumon.memberId);

    // The replay is deduplicated, so it adds nothing to the change feed and
    // there is nothing for the other phone to come and fetch.
    await postMutations(session.accessToken, batch);
    await RecordingActivityNotifier.settle();
    expect(activityNotifier.actors).toHaveLength(1);
  });

  it('applies a mutation even when the push fails outright', async () => {
    const session = await login('SUMON', sumonPin);
    activityNotifier.failure = new Error('Firebase is unreachable.');
    const expenseId = randomUUID();

    const response = await postMutations(session.accessToken, [
      createMutation('EXPENSE', 'CREATE', expenseId, 0, defaultExpense),
    ]);
    await RecordingActivityNotifier.settle();

    expect(response.results[0]?.status).toBe('APPLIED');
    expect(await prisma.expense.count({ where: { id: expenseId } })).toBe(1);
  });
});
