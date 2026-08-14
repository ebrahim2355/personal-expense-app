import { randomUUID } from 'node:crypto';

import * as argon2 from 'argon2';
import request from 'supertest';
import { z } from 'zod';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

import { AuthService } from '../../src/application/auth-service.js';
import { SyncService } from '../../src/application/sync-service.js';
import { createApp } from '../../src/app.js';
import type { AppConfig } from '../../src/config/env.js';
import type { AuthenticatedMember } from '../../src/domain/models.js';
import { createLogger } from '../../src/infrastructure/logger.js';
import { createPrismaClient } from '../../src/infrastructure/prisma.js';
import { TokenService } from '../../src/infrastructure/token-service.js';
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
};

const prisma = createPrismaClient(config);
const tokenService = new TokenService(config);
const authService = new AuthService(prisma, tokenService, config);
const syncService = new SyncService(prisma, tokenService);
const app = createApp({
  config,
  prisma,
  authService,
  syncService,
  logger: createLogger(config),
});

const expenseSchema = z.object({
  id: z.uuid(),
  amountMinor: z.number().int(),
  category: z.string(),
  payer: z.string(),
  occurredAt: z.string(),
  note: z.string().nullable(),
  version: z.number().int(),
  updatedAt: z.string(),
  deletedAt: z.string().nullable(),
});

const mutationResultSchema = z.object({
  mutationId: z.uuid(),
  status: z.enum(['APPLIED', 'CONFLICT', 'REJECTED']),
  code: z.string().optional(),
  expense: expenseSchema.optional(),
});

const mutationResponseSchema = z.object({
  results: z.array(mutationResultSchema),
});

const authResponseSchema = z.object({
  accessToken: z.string(),
  refreshToken: z.string(),
  member: z.object({ key: z.enum(['SUMON', 'EBRAHIM']) }),
});

const changePageSchema = z.object({
  changes: z.array(
    z.object({
      cursor: z.string(),
      operation: z.enum(['CREATED', 'UPDATED', 'DELETED']),
      originMutationId: z.uuid(),
      expense: expenseSchema,
    }),
  ),
  nextCursor: z.string(),
  hasMore: z.boolean(),
});

const bootstrapPageSchema = z.object({
  items: z.array(expenseSchema),
  watermarkCursor: z.string(),
  nextPageToken: z.string().nullable(),
  hasMore: z.boolean(),
});

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
}

const defaultExpense: ExpenseFields = {
  amountMinor: 40_000,
  category: 'GROCERIES',
  payer: 'SUMON',
  occurredAt: '2026-08-13T10:30:00+06:00',
  note: 'Market',
};

let primarySumon: AuthenticatedMember;
let isolatedSumon: AuthenticatedMember;

function createMutation(
  operation: 'CREATE' | 'UPDATE' | 'DELETE',
  entityId: string,
  baseVersion: number,
  expense?: ExpenseFields,
  mutationId = randomUUID(),
): Record<string, unknown> {
  return {
    mutationId,
    entityId,
    operation,
    baseVersion,
    ...(expense === undefined ? {} : { expense }),
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

async function clearMutableData(): Promise<void> {
  await prisma.processedMutation.deleteMany();
  await prisma.expenseChange.deleteMany();
  await prisma.expense.deleteMany();
  await prisma.refreshToken.deleteMany();
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
    const isolated = await prisma.household.create({
      data: {
        slug: `isolated-${randomUUID()}`,
        name: 'Isolated test household',
      },
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
      prisma.member.create({
        data: {
          householdId: isolated.id,
          key: 'SUMON',
          displayName: 'Sumon',
          pinHash,
        },
      }),
      prisma.member.create({
        data: {
          householdId: isolated.id,
          key: 'EBRAHIM',
          displayName: 'Ebrahim',
          pinHash: ebrahimHash,
        },
      }),
    ]);

    const primaryMember = primaryMembers[0];
    const isolatedMember = primaryMembers[2];
    if (primaryMember === undefined || isolatedMember === undefined) {
      throw new Error('Test members were not created.');
    }

    primarySumon = {
      memberId: primaryMember.id,
      householdId: primary.id,
      memberKey: 'SUMON',
    };
    isolatedSumon = {
      memberId: isolatedMember.id,
      householdId: isolated.id,
      memberKey: 'SUMON',
    };
  }, 30_000);

  beforeEach(async () => {
    await clearMutableData();
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
        createMutation('CREATE', sumonEntity, 0, defaultExpense),
      ]),
      postMutations(ebrahim.accessToken, [
        createMutation('CREATE', ebrahimEntity, 0, {
          ...defaultExpense,
          amountMinor: 25_001,
          payer: 'EBRAHIM',
        }),
      ]),
    ]);

    expect(sumonResult.results[0]?.status).toBe('APPLIED');
    expect(ebrahimResult.results[0]?.status).toBe('APPLIED');
    expect(await prisma.expense.count()).toBe(2);
    expect(await prisma.expenseChange.count()).toBe(2);

    const pulled = await request(app)
      .get('/v1/sync/changes?limit=10')
      .set('Authorization', `Bearer ${sumon.accessToken}`);
    const page = changePageSchema.parse(pulled.body as unknown);
    expect(new Set(page.changes.map((change) => change.expense.id))).toEqual(
      new Set([sumonEntity, ebrahimEntity]),
    );
  });

  it('propagates updates and soft-delete tombstones', async () => {
    const session = await login('SUMON', sumonPin);
    const entityId = randomUUID();
    await postMutations(session.accessToken, [
      createMutation('CREATE', entityId, 0, defaultExpense),
    ]);
    const initialPull = await request(app)
      .get('/v1/sync/changes?limit=10')
      .set('Authorization', `Bearer ${session.accessToken}`);
    const initialPage = changePageSchema.parse(initialPull.body as unknown);

    const updated = await postMutations(session.accessToken, [
      createMutation('UPDATE', entityId, 1, {
        ...defaultExpense,
        amountMinor: 55_501,
        note: 'Updated',
      }),
    ]);
    expect(updated.results[0]?.expense?.version).toBe(2);

    const deleted = await postMutations(session.accessToken, [
      createMutation('DELETE', entityId, 2),
    ]);
    expect(deleted.results[0]?.expense?.version).toBe(3);
    expect(deleted.results[0]?.expense?.deletedAt).not.toBeNull();

    const propagated = await request(app)
      .get(
        `/v1/sync/changes?limit=10&cursor=${encodeURIComponent(initialPage.nextCursor)}`,
      )
      .set('Authorization', `Bearer ${session.accessToken}`);
    const page = changePageSchema.parse(propagated.body as unknown);
    expect(page.changes.map((change) => change.operation)).toEqual([
      'UPDATED',
      'DELETED',
    ]);
    expect(page.changes[1]?.expense.deletedAt).not.toBeNull();

    const stored = await prisma.expense.findUnique({ where: { id: entityId } });
    expect(stored).not.toBeNull();
    expect(stored?.deletedAt).not.toBeNull();
  });

  it('returns the authoritative server entity for a stale baseVersion', async () => {
    const session = await login('SUMON', sumonPin);
    const entityId = randomUUID();
    await postMutations(session.accessToken, [
      createMutation('CREATE', entityId, 0, defaultExpense),
    ]);
    await postMutations(session.accessToken, [
      createMutation('UPDATE', entityId, 1, {
        ...defaultExpense,
        amountMinor: 70_000,
      }),
    ]);

    const siblingEntityId = randomUUID();
    const stale = await postMutations(session.accessToken, [
      createMutation('UPDATE', entityId, 1, {
        ...defaultExpense,
        amountMinor: 90_000,
      }),
      createMutation('CREATE', siblingEntityId, 0, defaultExpense),
    ]);

    expect(stale.results[0]).toMatchObject({
      status: 'CONFLICT',
      code: 'VERSION_CONFLICT',
      expense: { id: entityId, version: 2, amountMinor: 70_000 },
    });
    expect(stale.results[1]).toMatchObject({
      status: 'APPLIED',
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
        createMutation('CREATE', entityId, 0, {
          ...defaultExpense,
          amountMinor: 10_000 + index,
        }),
      ),
    );
    const deletedId = entityIds[1];
    if (deletedId === undefined) {
      throw new Error('Missing test entity ID.');
    }
    await postMutations(session.accessToken, [
      createMutation('DELETE', deletedId, 1),
    ]);

    const firstPullResponse = await request(app)
      .get('/v1/sync/changes?limit=2')
      .set('Authorization', `Bearer ${session.accessToken}`);
    const firstPull = changePageSchema.parse(firstPullResponse.body as unknown);
    expect(firstPull.changes).toHaveLength(2);
    expect(firstPull.hasMore).toBe(true);

    const secondPullResponse = await request(app)
      .get(
        `/v1/sync/changes?limit=2&cursor=${encodeURIComponent(firstPull.nextCursor)}`,
      )
      .set('Authorization', `Bearer ${session.accessToken}`);
    const secondPull = changePageSchema.parse(
      secondPullResponse.body as unknown,
    );
    expect(secondPull.changes).toHaveLength(2);
    expect(secondPull.hasMore).toBe(false);
    expect(secondPull.changes.at(-1)?.operation).toBe('DELETED');

    const bootstrapItems: z.infer<typeof expenseSchema>[] = [];
    let pageToken: string | null = null;
    let watermark: string | undefined;
    do {
      const query =
        pageToken === null
          ? '/v1/sync/bootstrap?limit=1'
          : `/v1/sync/bootstrap?limit=1&pageToken=${encodeURIComponent(pageToken)}`;
      const response = await request(app)
        .get(query)
        .set('Authorization', `Bearer ${session.accessToken}`);
      const page = bootstrapPageSchema.parse(response.body as unknown);
      watermark ??= page.watermarkCursor;
      expect(page.watermarkCursor).toBe(watermark);
      bootstrapItems.push(...page.items);
      pageToken = page.nextPageToken;
    } while (pageToken !== null);

    expect(bootstrapItems).toHaveLength(3);
    expect(
      bootstrapItems.find((item) => item.id === deletedId)?.deletedAt,
    ).not.toBeNull();
  });

  it('scopes service reads and writes to the authenticated household', async () => {
    const entityId = randomUUID();
    const created = await syncService.applyMutations(primarySumon, [
      createMutation('CREATE', entityId, 0, defaultExpense) as never,
    ]);
    expect(created[0]?.status).toBe('APPLIED');

    const crossHousehold = await syncService.applyMutations(isolatedSumon, [
      createMutation('UPDATE', entityId, 1, {
        ...defaultExpense,
        amountMinor: 99_999,
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
    expect(isolatedBootstrap.items).toEqual([]);
    expect(
      await prisma.expense.count({
        where: { id: entityId, householdId: isolatedSumon.householdId },
      }),
    ).toBe(0);
  });

  it('returns a per-mutation validation rejection without applying sibling-invalid data', async () => {
    const session = await login('SUMON', sumonPin);
    const validEntity = randomUUID();
    const response = await postMutations(session.accessToken, [
      createMutation('CREATE', randomUUID(), 0, {
        ...defaultExpense,
        amountMinor: 0,
      }),
      createMutation('CREATE', validEntity, 0, defaultExpense),
    ]);

    expect(response.results[0]).toMatchObject({
      status: 'REJECTED',
      code: 'INVALID_MUTATION',
    });
    expect(response.results[1]?.status).toBe('APPLIED');
    expect(await prisma.expense.count()).toBe(1);
  });

  it('stores offset timestamps as UTC instants', async () => {
    const session = await login('SUMON', sumonPin);
    const entityId = randomUUID();
    await postMutations(session.accessToken, [
      createMutation('CREATE', entityId, 0, {
        ...defaultExpense,
        occurredAt: '2026-08-01T00:00:00+06:00',
      }),
    ]);

    const stored = await prisma.expense.findUnique({ where: { id: entityId } });
    expect(stored?.occurredAt.toISOString()).toBe('2026-07-31T18:00:00.000Z');
  });
});
