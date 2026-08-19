import { createHash } from 'node:crypto';

import { z } from 'zod';

import type { MemberKey, SyncEntityType } from '../domain/constants.js';
import { EXPENSE_CATEGORIES, MEMBER_KEYS } from '../domain/constants.js';
import { AppError, validationIssues } from '../domain/errors.js';
import type {
  AuthenticatedMember,
  EntityPayload,
  ExpenseSnapshot,
  LoanSnapshot,
  MutationBase,
  MutationResult,
  ParsedMutation,
  PeriodSnapshot,
} from '../domain/models.js';
import { parsedMutationSchema } from '../domain/validation.js';
import { Prisma } from '../generated/prisma/client.js';
import type { SpendingPeriod } from '../generated/prisma/client.js';
import type { DatabaseClient } from '../infrastructure/prisma.js';
import type {
  BootstrapPosition,
  TokenService,
} from '../infrastructure/token-service.js';
import type { HouseholdActivityNotifier } from './push-notifier.js';

const expenseWithPayer = {
  payer: {
    select: {
      key: true,
    },
  },
} satisfies Prisma.ExpenseInclude;

type ExpenseWithPayer = Prisma.ExpenseGetPayload<{
  include: typeof expenseWithPayer;
}>;

const loanWithDebtor = {
  debtor: {
    select: {
      key: true,
    },
  },
} satisfies Prisma.LoanEntryInclude;

type LoanWithDebtor = Prisma.LoanEntryGetPayload<{
  include: typeof loanWithDebtor;
}>;

type PeriodRow = SpendingPeriod;

/** One stored entity row paired with the entity type that describes it. */
type EntityRecord =
  | { entityType: 'EXPENSE'; row: ExpenseWithPayer }
  | { entityType: 'PERIOD'; row: PeriodRow }
  | { entityType: 'LOAN'; row: LoanWithDebtor };

const timestampSchema = z.string().datetime({ offset: true });
const nullableTimestampSchema = timestampSchema.nullable();

// Stored amounts are only checked for plausibility. The whole-taka rule belongs
// to `domain/validation.ts`, which guards everything entering the database; a
// stored document that predates the rule must still parse so an idempotent
// replay returns the value the client already saw.
const storedAmountMinorSchema = z.number().int().safe().positive();

const expenseSnapshotSchema = z
  .object({
    id: z.uuid(),
    amountMinor: storedAmountMinorSchema,
    category: z.enum(EXPENSE_CATEGORIES),
    payer: z.enum(MEMBER_KEYS),
    occurredAt: timestampSchema,
    note: z.string().nullable(),
    periodId: z.uuid(),
    version: z.number().int().positive(),
    updatedAt: timestampSchema,
    deletedAt: nullableTimestampSchema,
  })
  .strict();

const periodSnapshotSchema = z
  .object({
    id: z.uuid(),
    sequenceNumber: z.number().int().positive(),
    startedAt: timestampSchema,
    closedAt: nullableTimestampSchema,
    note: z.string().nullable(),
    version: z.number().int().positive(),
    updatedAt: timestampSchema,
  })
  .strict();

const loanSnapshotSchema = z
  .object({
    id: z.uuid(),
    debtor: z.enum(MEMBER_KEYS),
    amountMinor: storedAmountMinorSchema,
    occurredAt: timestampSchema,
    note: z.string().nullable(),
    version: z.number().int().positive(),
    updatedAt: timestampSchema,
    deletedAt: nullableTimestampSchema,
  })
  .strict();

/**
 * Reads an omitted entityType as EXPENSE, mirroring the same defaulting in
 * `parsedMutationSchema`. Defensive: the periods migration already stamped
 * every stored result document that carries a payload.
 */
function defaultEntityTypeToExpense(value: unknown): unknown {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return value;
  }

  const candidate = value as Record<string, unknown>;
  return candidate.entityType === undefined
    ? { ...candidate, entityType: 'EXPENSE' }
    : candidate;
}

// One payload key per entity type, spread into each result status below.
// Zod cannot discriminate through an intersection, so the two levels are nested
// discriminated unions rather than `status` intersected with a payload schema.
const expensePayloadShape = {
  entityType: z.literal('EXPENSE'),
  expense: expenseSnapshotSchema,
} as const;

const periodPayloadShape = {
  entityType: z.literal('PERIOD'),
  period: periodSnapshotSchema,
} as const;

const loanPayloadShape = {
  entityType: z.literal('LOAN'),
  loan: loanSnapshotSchema,
} as const;

const appliedShape = {
  mutationId: z.uuid(),
  status: z.literal('APPLIED'),
} as const;

const conflictShape = {
  mutationId: z.uuid(),
  status: z.literal('CONFLICT'),
  code: z.enum(['ENTITY_EXISTS', 'VERSION_CONFLICT']),
} as const;

const mutationResultSchema = z.preprocess(
  defaultEntityTypeToExpense,
  z.discriminatedUnion('status', [
    z.discriminatedUnion('entityType', [
      z.object({ ...appliedShape, ...expensePayloadShape }),
      z.object({ ...appliedShape, ...periodPayloadShape }),
      z.object({ ...appliedShape, ...loanPayloadShape }),
    ]),
    z.discriminatedUnion('entityType', [
      z.object({ ...conflictShape, ...expensePayloadShape }),
      z.object({ ...conflictShape, ...periodPayloadShape }),
      z.object({ ...conflictShape, ...loanPayloadShape }),
    ]),
    z.object({
      mutationId: z.uuid(),
      status: z.literal('REJECTED'),
      code: z.enum([
        'ENTITY_ID_UNAVAILABLE',
        'ENTITY_NOT_FOUND',
        'IDEMPOTENCY_KEY_REUSED',
        'INVALID_MUTATION',
        'PAYER_NOT_FOUND',
        'PERIOD_ALREADY_OPEN',
        'PERIOD_NOT_FOUND',
      ]),
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
  ]),
);

type ChangeView = {
  cursor: string;
  operation: 'CREATED' | 'UPDATED' | 'DELETED';
  /**
   * The member who authored the change. A pulling device compares this against
   * its own member to tell the other member's activity apart from its own
   * writes echoing back on the same sync run.
   */
  actorMember: MemberKey;
  originMutationId: string;
} & EntityPayload;

interface ChangePage {
  changes: ChangeView[];
  nextCursor: string;
  hasMore: boolean;
}

/** One canonical entity, tagged so a reader knows which payload key to read. */
type BootstrapItem = EntityPayload;

interface BootstrapPage {
  items: BootstrapItem[];
  watermarkCursor: string;
  nextPageToken: string | null;
  hasMore: boolean;
}

/**
 * Bootstrap walks the entity types in this order under one watermark, so every
 * spending period reaches a client before the expenses that reference it.
 */
const BOOTSTRAP_ORDER = ['PERIOD', 'EXPENSE', 'LOAN'] as const;

function nextBootstrapType(entityType: SyncEntityType): SyncEntityType | null {
  return BOOTSTRAP_ORDER[BOOTSTRAP_ORDER.indexOf(entityType) + 1] ?? null;
}

function safeAmountMinor(amountMinor: bigint): number {
  const value = Number(amountMinor);
  if (!Number.isSafeInteger(value)) {
    throw new AppError(
      500,
      'DATA_INTEGRITY_ERROR',
      'Stored expense data is invalid.',
    );
  }

  return value;
}

function expenseSnapshot(expense: ExpenseWithPayer): ExpenseSnapshot {
  return {
    id: expense.id,
    amountMinor: safeAmountMinor(expense.amountMinor),
    category: expense.category,
    payer: expense.payer.key,
    occurredAt: expense.occurredAt.toISOString(),
    note: expense.note,
    periodId: expense.periodId,
    version: expense.version,
    updatedAt: expense.updatedAt.toISOString(),
    deletedAt: expense.deletedAt?.toISOString() ?? null,
  };
}

function periodSnapshot(period: PeriodRow): PeriodSnapshot {
  return {
    id: period.id,
    sequenceNumber: period.sequenceNumber,
    startedAt: period.startedAt.toISOString(),
    closedAt: period.closedAt?.toISOString() ?? null,
    note: period.note,
    version: period.version,
    updatedAt: period.updatedAt.toISOString(),
  };
}

function loanSnapshot(loan: LoanWithDebtor): LoanSnapshot {
  return {
    id: loan.id,
    debtor: loan.debtor.key,
    amountMinor: safeAmountMinor(loan.amountMinor),
    occurredAt: loan.occurredAt.toISOString(),
    note: loan.note,
    version: loan.version,
    updatedAt: loan.updatedAt.toISOString(),
    deletedAt: loan.deletedAt?.toISOString() ?? null,
  };
}

function entityPayload(record: EntityRecord): EntityPayload {
  switch (record.entityType) {
    case 'EXPENSE':
      return { entityType: 'EXPENSE', expense: expenseSnapshot(record.row) };
    case 'PERIOD':
      return { entityType: 'PERIOD', period: periodSnapshot(record.row) };
    case 'LOAN':
      return { entityType: 'LOAN', loan: loanSnapshot(record.row) };
  }
}

/** Parses a stored change document against the schema its entity type names. */
function storedEntityPayload(
  entityType: SyncEntityType,
  snapshot: unknown,
): EntityPayload {
  switch (entityType) {
    case 'EXPENSE':
      return {
        entityType: 'EXPENSE',
        expense: expenseSnapshotSchema.parse(snapshot),
      };
    case 'PERIOD':
      return {
        entityType: 'PERIOD',
        period: periodSnapshotSchema.parse(snapshot),
      };
    case 'LOAN':
      return { entityType: 'LOAN', loan: loanSnapshotSchema.parse(snapshot) };
  }
}

function stableSerialize(value: unknown): string {
  if (value instanceof Date) {
    return JSON.stringify(value.toISOString());
  }
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableSerialize(item)).join(',')}]`;
  }

  const entries = Object.entries(value).filter(
    ([, item]) => item !== undefined,
  );
  entries.sort(([left], [right]) => left.localeCompare(right));
  return `{${entries
    .map(([key, item]) => `${JSON.stringify(key)}:${stableSerialize(item)}`)
    .join(',')}}`;
}

function requestHash(value: unknown): string {
  return createHash('sha256')
    .update(stableSerialize(value), 'utf8')
    .digest('hex');
}

function jsonValue(value: unknown): Prisma.InputJsonValue {
  return JSON.parse(JSON.stringify(value)) as Prisma.InputJsonValue;
}

const householdWriteLockNamespace = 'expense-change-sequence';

/**
 * Stable 64-bit advisory-lock key for one household's write transactions.
 */
function householdWriteLockKey(householdId: string): bigint {
  return createHash('sha256')
    .update(`${householdWriteLockNamespace}:${householdId}`, 'utf8')
    .digest()
    .readBigInt64BE(0);
}

/**
 * Serializes the write transactions of a single household so that
 * `ExpenseChange.sequence` values are allocated in the same order the
 * transactions commit.
 *
 * `sequence` comes from a PostgreSQL sequence, which hands out a number before
 * the transaction commits. Without this lock, a transaction holding the lower
 * number can commit after a higher one, and a client that polls
 * `/v1/sync/changes` in that window would move its cursor past the lower number
 * and never be sent that change again.
 */
export async function lockHouseholdWrites(
  transaction: Prisma.TransactionClient,
  householdId: string,
): Promise<void> {
  await transaction.$executeRaw`SELECT pg_advisory_xact_lock(${householdWriteLockKey(
    householdId,
  )}::bigint)`;
}

function prismaErrorCode(error: unknown): string | undefined {
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

export class SyncService {
  public constructor(
    private readonly prisma: DatabaseClient,
    private readonly tokens: TokenService,
    private readonly activity: HouseholdActivityNotifier,
  ) {}

  public async applyMutations(
    identity: AuthenticatedMember,
    mutations: MutationBase[],
  ): Promise<MutationResult[]> {
    const results: MutationResult[] = [];
    // The mutation ids answered from a stored receipt instead of by writing. A
    // replay returns the APPLIED result the client already saw, so the status
    // alone cannot tell a change that just landed from one being re-uploaded
    // after a lost response.
    const replays = new Set<string>();

    for (const mutation of mutations) {
      const parsed = parsedMutationSchema.safeParse(mutation);
      const hash = requestHash(parsed.success ? parsed.data : mutation);
      const invalidResult: MutationResult | undefined = parsed.success
        ? undefined
        : {
            mutationId: mutation.mutationId,
            status: 'REJECTED',
            code: 'INVALID_MUTATION',
            details: validationIssues(parsed.error),
          };

      results.push(
        await this.processWithRetry(
          identity,
          mutation,
          parsed.success ? parsed.data : undefined,
          invalidResult,
          hash,
          replays,
        ),
      );
    }

    // Only a change that actually landed is worth waking a phone for. A batch
    // replayed after a flaky upload, or one rejected outright, adds nothing to
    // the change feed, so there is nothing for the other device to come and
    // fetch.
    const landed = results.some(
      (result) =>
        result.status === 'APPLIED' && !replays.has(result.mutationId),
    );
    if (landed) {
      // Fired here rather than inside the transaction, and deliberately not
      // awaited: every write above has committed, so the response owes the
      // client nothing more, and the round trip to Google must not be added to
      // the time the phone spends waiting to sync.
      void this.activity.notifyOtherMembers(identity).catch(() => {
        // Unreachable unless the notifier itself has a bug — it already logs and
        // swallows every send failure. This is the backstop that keeps such a bug
        // from becoming an unhandled rejection and taking the process down.
      });
    }

    return results;
  }

  public async getChanges(
    identity: AuthenticatedMember,
    cursor: string | undefined,
    limit: number,
  ): Promise<ChangePage> {
    const after =
      cursor === undefined
        ? 0n
        : this.tokens.decodeChangeCursor(cursor, identity.householdId);
    const rows = await this.prisma.expenseChange.findMany({
      where: {
        householdId: identity.householdId,
        sequence: { gt: after },
      },
      orderBy: { sequence: 'asc' },
      take: limit + 1,
    });
    const hasMore = rows.length > limit;
    const pageRows = rows.slice(0, limit);
    const lastSequence = pageRows.at(-1)?.sequence ?? after;

    return {
      changes: pageRows.map((row) => ({
        cursor: this.tokens.encodeChangeCursor(
          identity.householdId,
          row.sequence,
        ),
        operation: row.operation,
        actorMember: row.actorMemberKey,
        originMutationId: row.originMutationId,
        ...storedEntityPayload(row.entityType, row.snapshot),
      })),
      nextCursor: this.tokens.encodeChangeCursor(
        identity.householdId,
        lastSequence,
      ),
      hasMore,
    };
  }

  public async bootstrap(
    identity: AuthenticatedMember,
    pageToken: string | undefined,
    limit: number,
  ): Promise<BootstrapPage> {
    let position: BootstrapPosition;

    if (pageToken === undefined) {
      const aggregate = await this.prisma.expenseChange.aggregate({
        where: { householdId: identity.householdId },
        _max: { sequence: true },
      });
      position = {
        watermark: aggregate._max.sequence ?? 0n,
        entityType: 'PERIOD',
        afterId: null,
      };
    } else {
      position = this.tokens.decodeBootstrapToken(
        pageToken,
        identity.householdId,
      );
    }

    const items: BootstrapItem[] = [];
    let entityType: SyncEntityType | null = position.entityType;
    let afterId = position.afterId;
    let next: BootstrapPosition | null = null;

    while (entityType !== null) {
      const remaining = limit - items.length;
      const rows = await this.readBootstrapLeg(
        identity.householdId,
        entityType,
        position.watermark,
        afterId,
        remaining + 1,
      );
      const taken = rows.slice(0, remaining);
      items.push(...taken.map(({ item }) => item));

      if (rows.length > remaining) {
        next = {
          watermark: position.watermark,
          entityType,
          // Nothing is taken once the page is already full, so the next page
          // resumes this leg exactly where this one stopped.
          afterId: taken.at(-1)?.id ?? afterId,
        };
        break;
      }

      entityType = nextBootstrapType(entityType);
      afterId = null;
    }

    return {
      items,
      watermarkCursor: this.tokens.encodeChangeCursor(
        identity.householdId,
        position.watermark,
      ),
      nextPageToken:
        next === null
          ? null
          : this.tokens.encodeBootstrapToken(identity.householdId, next),
      hasMore: next !== null,
    };
  }

  private async readBootstrapLeg(
    householdId: string,
    entityType: SyncEntityType,
    watermark: bigint,
    afterId: string | null,
    take: number,
  ): Promise<{ id: string; item: BootstrapItem }[]> {
    const where = {
      householdId,
      lastChangeSequence: { lte: watermark },
      ...(afterId === null ? {} : { id: { gt: afterId } }),
    };

    switch (entityType) {
      case 'PERIOD': {
        const rows = await this.prisma.spendingPeriod.findMany({
          where,
          orderBy: { id: 'asc' },
          take,
        });
        return rows.map((row) => ({
          id: row.id,
          item: { entityType, period: periodSnapshot(row) },
        }));
      }
      case 'EXPENSE': {
        const rows = await this.prisma.expense.findMany({
          where,
          include: expenseWithPayer,
          orderBy: { id: 'asc' },
          take,
        });
        return rows.map((row) => ({
          id: row.id,
          item: { entityType, expense: expenseSnapshot(row) },
        }));
      }
      case 'LOAN': {
        const rows = await this.prisma.loanEntry.findMany({
          where,
          include: loanWithDebtor,
          orderBy: { id: 'asc' },
          take,
        });
        return rows.map((row) => ({
          id: row.id,
          item: { entityType, loan: loanSnapshot(row) },
        }));
      }
    }
  }

  private async processWithRetry(
    identity: AuthenticatedMember,
    base: MutationBase,
    mutation: ParsedMutation | undefined,
    invalidResult: MutationResult | undefined,
    hash: string,
    replays: Set<string>,
  ): Promise<MutationResult> {
    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        return await this.prisma.$transaction(
          async (transaction) =>
            this.processOne(
              transaction,
              identity,
              base,
              mutation,
              invalidResult,
              hash,
              replays,
            ),
          { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
        );
      } catch (error) {
        const code = prismaErrorCode(error);
        if (code === 'P2034' && attempt < 3) {
          continue;
        }
        if (code === 'P2002') {
          return this.resolveUniqueCollision(
            identity,
            base,
            hash,
            mutation?.entityType ?? base.entityType ?? 'EXPENSE',
            replays,
          );
        }
        throw error;
      }
    }

    throw new AppError(
      503,
      'TRANSACTION_RETRY_EXHAUSTED',
      'Please retry the sync request.',
    );
  }

  private async processOne(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    base: MutationBase,
    mutation: ParsedMutation | undefined,
    invalidResult: MutationResult | undefined,
    hash: string,
    replays: Set<string>,
  ): Promise<MutationResult> {
    await lockHouseholdWrites(transaction, identity.householdId);

    const receipt = await transaction.processedMutation.findFirst({
      where: {
        mutationId: base.mutationId,
        householdId: identity.householdId,
      },
    });
    if (receipt !== null) {
      // Answered from the receipt, so the change feed did not grow and the other
      // phone has nothing new to fetch.
      replays.add(base.mutationId);
      return receipt.requestHash === hash
        ? mutationResultSchema.parse(receipt.result)
        : {
            mutationId: base.mutationId,
            status: 'REJECTED',
            code: 'IDEMPOTENCY_KEY_REUSED',
          };
    }

    if (invalidResult !== undefined || mutation === undefined) {
      const result = invalidResult ?? {
        mutationId: base.mutationId,
        status: 'REJECTED' as const,
        code: 'INVALID_MUTATION' as const,
      };
      await this.storeReceipt(
        transaction,
        identity,
        base,
        hash,
        result,
        base.entityType ?? 'EXPENSE',
      );
      return result;
    }

    if (mutation.entityType === 'EXPENSE') {
      if (mutation.operation === 'CREATE') {
        return this.createExpense(transaction, identity, mutation, hash);
      }
      if (mutation.operation === 'UPDATE') {
        return this.updateExpense(transaction, identity, mutation, hash);
      }
      return this.deleteExpense(transaction, identity, mutation, hash);
    }

    // A PERIOD DELETE never reaches here: `parsedMutationSchema` has no delete
    // variant for periods, so it is already rejected as INVALID_MUTATION.
    if (mutation.entityType === 'PERIOD') {
      return mutation.operation === 'CREATE'
        ? this.createPeriod(transaction, identity, mutation, hash)
        : this.updatePeriod(transaction, identity, mutation, hash);
    }

    if (mutation.operation === 'CREATE') {
      return this.createLoan(transaction, identity, mutation, hash);
    }
    if (mutation.operation === 'UPDATE') {
      return this.updateLoan(transaction, identity, mutation, hash);
    }
    return this.deleteLoan(transaction, identity, mutation, hash);
  }

  /**
   * Resolves the spending period an expense belongs to. An omitted period means
   * the household's open one; a named period only has to exist, because an
   * expense recorded offline before a close still belongs to the closed period
   * it was recorded in.
   */
  private async resolvePeriodId(
    transaction: Prisma.TransactionClient,
    householdId: string,
    requested: string | undefined,
  ): Promise<string | null> {
    const period = await transaction.spendingPeriod.findFirst({
      where:
        requested === undefined
          ? { householdId, closedAt: null }
          : { householdId, id: requested },
      select: { id: true },
    });

    return period?.id ?? null;
  }

  private async createExpense(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: Extract<
      ParsedMutation,
      { entityType: 'EXPENSE'; operation: 'CREATE' }
    >,
    hash: string,
  ): Promise<MutationResult> {
    const existing = await this.findExpense(
      transaction,
      identity.householdId,
      mutation.entityId,
    );
    if (existing !== null) {
      return this.storeConflict(
        transaction,
        identity,
        mutation,
        hash,
        'ENTITY_EXISTS',
        { entityType: 'EXPENSE', row: existing },
      );
    }

    const payer = await this.findMemberId(
      transaction,
      identity.householdId,
      mutation.expense.payer,
    );
    if (payer === null) {
      return this.storeSimpleRejection(
        transaction,
        identity,
        mutation,
        hash,
        'PAYER_NOT_FOUND',
      );
    }

    const periodId = await this.resolvePeriodId(
      transaction,
      identity.householdId,
      mutation.expense.periodId,
    );
    if (periodId === null) {
      return this.storeSimpleRejection(
        transaction,
        identity,
        mutation,
        hash,
        'PERIOD_NOT_FOUND',
      );
    }

    const now = new Date();
    const created = await transaction.expense.create({
      data: {
        id: mutation.entityId,
        householdId: identity.householdId,
        amountMinor: BigInt(mutation.expense.amountMinor),
        category: mutation.expense.category,
        payerId: payer,
        periodId,
        occurredAt: mutation.expense.occurredAt,
        note: mutation.expense.note,
        version: 1,
        createdAt: now,
        updatedAt: now,
      },
      include: expenseWithPayer,
    });

    return this.recordApplied(
      transaction,
      identity,
      mutation,
      hash,
      { entityType: 'EXPENSE', row: created },
      'CREATED',
    );
  }

  private async updateExpense(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: Extract<
      ParsedMutation,
      { entityType: 'EXPENSE'; operation: 'UPDATE' }
    >,
    hash: string,
  ): Promise<MutationResult> {
    const payer = await this.findMemberId(
      transaction,
      identity.householdId,
      mutation.expense.payer,
    );
    if (payer === null) {
      return this.storeSimpleRejection(
        transaction,
        identity,
        mutation,
        hash,
        'PAYER_NOT_FOUND',
      );
    }

    const periodId = await this.resolvePeriodId(
      transaction,
      identity.householdId,
      mutation.expense.periodId,
    );
    if (periodId === null) {
      return this.storeSimpleRejection(
        transaction,
        identity,
        mutation,
        hash,
        'PERIOD_NOT_FOUND',
      );
    }

    const updated = await transaction.expense.updateMany({
      where: {
        id: mutation.entityId,
        householdId: identity.householdId,
        version: mutation.baseVersion,
        deletedAt: null,
      },
      data: {
        amountMinor: BigInt(mutation.expense.amountMinor),
        category: mutation.expense.category,
        payerId: payer,
        periodId,
        occurredAt: mutation.expense.occurredAt,
        note: mutation.expense.note,
        version: { increment: 1 },
        updatedAt: new Date(),
      },
    });

    if (updated.count !== 1) {
      return this.versionFailure(transaction, identity, mutation, hash);
    }

    const expense = await this.findExpense(
      transaction,
      identity.householdId,
      mutation.entityId,
    );
    if (expense === null) {
      throw new AppError(
        500,
        'DATA_INTEGRITY_ERROR',
        'Updated expense was not found.',
      );
    }

    return this.recordApplied(
      transaction,
      identity,
      mutation,
      hash,
      { entityType: 'EXPENSE', row: expense },
      'UPDATED',
    );
  }

  private async deleteExpense(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: Extract<
      ParsedMutation,
      { entityType: 'EXPENSE'; operation: 'DELETE' }
    >,
    hash: string,
  ): Promise<MutationResult> {
    const now = new Date();
    const deleted = await transaction.expense.updateMany({
      where: {
        id: mutation.entityId,
        householdId: identity.householdId,
        version: mutation.baseVersion,
        deletedAt: null,
      },
      data: {
        version: { increment: 1 },
        updatedAt: now,
        deletedAt: now,
      },
    });

    if (deleted.count !== 1) {
      return this.versionFailure(transaction, identity, mutation, hash);
    }

    const expense = await this.findExpense(
      transaction,
      identity.householdId,
      mutation.entityId,
    );
    if (expense === null) {
      throw new AppError(
        500,
        'DATA_INTEGRITY_ERROR',
        'Deleted expense was not found.',
      );
    }

    return this.recordApplied(
      transaction,
      identity,
      mutation,
      hash,
      { entityType: 'EXPENSE', row: expense },
      'DELETED',
    );
  }

  private async createPeriod(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: Extract<
      ParsedMutation,
      { entityType: 'PERIOD'; operation: 'CREATE' }
    >,
    hash: string,
  ): Promise<MutationResult> {
    const existing = await this.findPeriod(
      transaction,
      identity.householdId,
      mutation.entityId,
    );
    if (existing !== null) {
      return this.storeConflict(
        transaction,
        identity,
        mutation,
        hash,
        'ENTITY_EXISTS',
        { entityType: 'PERIOD', row: existing },
      );
    }

    // A household settles one history at a time, so only one period may be
    // open. The partial unique index enforces the same rule under a race.
    if (mutation.period.closedAt === null) {
      const open = await transaction.spendingPeriod.findFirst({
        where: { householdId: identity.householdId, closedAt: null },
        select: { id: true },
      });
      if (open !== null) {
        return this.storeSimpleRejection(
          transaction,
          identity,
          mutation,
          hash,
          'PERIOD_ALREADY_OPEN',
        );
      }
    }

    const now = new Date();
    const created = await transaction.spendingPeriod.create({
      data: {
        id: mutation.entityId,
        householdId: identity.householdId,
        sequenceNumber: mutation.period.sequenceNumber,
        startedAt: mutation.period.startedAt,
        closedAt: mutation.period.closedAt,
        note: mutation.period.note,
        version: 1,
        createdAt: now,
        updatedAt: now,
      },
    });

    return this.recordApplied(
      transaction,
      identity,
      mutation,
      hash,
      { entityType: 'PERIOD', row: created },
      'CREATED',
    );
  }

  private async updatePeriod(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: Extract<
      ParsedMutation,
      { entityType: 'PERIOD'; operation: 'UPDATE' }
    >,
    hash: string,
  ): Promise<MutationResult> {
    const stored = await this.findPeriod(
      transaction,
      identity.householdId,
      mutation.entityId,
    );
    if (
      stored !== null &&
      stored.closedAt !== null &&
      mutation.period.closedAt === null
    ) {
      const result: MutationResult = {
        mutationId: mutation.mutationId,
        status: 'REJECTED',
        code: 'INVALID_MUTATION',
        details: [
          {
            path: 'period.closedAt',
            code: 'custom',
            message: 'A settled spending period cannot be reopened.',
          },
        ],
      };
      await this.storeReceipt(
        transaction,
        identity,
        mutation,
        hash,
        result,
        'PERIOD',
      );
      return result;
    }

    const updated = await transaction.spendingPeriod.updateMany({
      where: {
        id: mutation.entityId,
        householdId: identity.householdId,
        version: mutation.baseVersion,
      },
      data: {
        sequenceNumber: mutation.period.sequenceNumber,
        startedAt: mutation.period.startedAt,
        closedAt: mutation.period.closedAt,
        note: mutation.period.note,
        version: { increment: 1 },
        updatedAt: new Date(),
      },
    });

    if (updated.count !== 1) {
      return this.versionFailure(transaction, identity, mutation, hash);
    }

    const period = await this.findPeriod(
      transaction,
      identity.householdId,
      mutation.entityId,
    );
    if (period === null) {
      throw new AppError(
        500,
        'DATA_INTEGRITY_ERROR',
        'Updated spending period was not found.',
      );
    }

    return this.recordApplied(
      transaction,
      identity,
      mutation,
      hash,
      { entityType: 'PERIOD', row: period },
      'UPDATED',
    );
  }

  private async createLoan(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: Extract<
      ParsedMutation,
      { entityType: 'LOAN'; operation: 'CREATE' }
    >,
    hash: string,
  ): Promise<MutationResult> {
    const existing = await this.findLoan(
      transaction,
      identity.householdId,
      mutation.entityId,
    );
    if (existing !== null) {
      return this.storeConflict(
        transaction,
        identity,
        mutation,
        hash,
        'ENTITY_EXISTS',
        { entityType: 'LOAN', row: existing },
      );
    }

    const debtor = await this.findMemberId(
      transaction,
      identity.householdId,
      mutation.loan.debtor,
    );
    if (debtor === null) {
      return this.storeSimpleRejection(
        transaction,
        identity,
        mutation,
        hash,
        'PAYER_NOT_FOUND',
      );
    }

    const now = new Date();
    const created = await transaction.loanEntry.create({
      data: {
        id: mutation.entityId,
        householdId: identity.householdId,
        debtorId: debtor,
        amountMinor: BigInt(mutation.loan.amountMinor),
        occurredAt: mutation.loan.occurredAt,
        note: mutation.loan.note,
        version: 1,
        createdAt: now,
        updatedAt: now,
      },
      include: loanWithDebtor,
    });

    return this.recordApplied(
      transaction,
      identity,
      mutation,
      hash,
      { entityType: 'LOAN', row: created },
      'CREATED',
    );
  }

  private async updateLoan(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: Extract<
      ParsedMutation,
      { entityType: 'LOAN'; operation: 'UPDATE' }
    >,
    hash: string,
  ): Promise<MutationResult> {
    const debtor = await this.findMemberId(
      transaction,
      identity.householdId,
      mutation.loan.debtor,
    );
    if (debtor === null) {
      return this.storeSimpleRejection(
        transaction,
        identity,
        mutation,
        hash,
        'PAYER_NOT_FOUND',
      );
    }

    const updated = await transaction.loanEntry.updateMany({
      where: {
        id: mutation.entityId,
        householdId: identity.householdId,
        version: mutation.baseVersion,
        deletedAt: null,
      },
      data: {
        debtorId: debtor,
        amountMinor: BigInt(mutation.loan.amountMinor),
        occurredAt: mutation.loan.occurredAt,
        note: mutation.loan.note,
        version: { increment: 1 },
        updatedAt: new Date(),
      },
    });

    if (updated.count !== 1) {
      return this.versionFailure(transaction, identity, mutation, hash);
    }

    const loan = await this.findLoan(
      transaction,
      identity.householdId,
      mutation.entityId,
    );
    if (loan === null) {
      throw new AppError(
        500,
        'DATA_INTEGRITY_ERROR',
        'Updated loan entry was not found.',
      );
    }

    return this.recordApplied(
      transaction,
      identity,
      mutation,
      hash,
      { entityType: 'LOAN', row: loan },
      'UPDATED',
    );
  }

  private async deleteLoan(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: Extract<
      ParsedMutation,
      { entityType: 'LOAN'; operation: 'DELETE' }
    >,
    hash: string,
  ): Promise<MutationResult> {
    const now = new Date();
    const deleted = await transaction.loanEntry.updateMany({
      where: {
        id: mutation.entityId,
        householdId: identity.householdId,
        version: mutation.baseVersion,
        deletedAt: null,
      },
      data: {
        version: { increment: 1 },
        updatedAt: now,
        deletedAt: now,
      },
    });

    if (deleted.count !== 1) {
      return this.versionFailure(transaction, identity, mutation, hash);
    }

    const loan = await this.findLoan(
      transaction,
      identity.householdId,
      mutation.entityId,
    );
    if (loan === null) {
      throw new AppError(
        500,
        'DATA_INTEGRITY_ERROR',
        'Deleted loan entry was not found.',
      );
    }

    return this.recordApplied(
      transaction,
      identity,
      mutation,
      hash,
      { entityType: 'LOAN', row: loan },
      'DELETED',
    );
  }

  private async versionFailure(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: ParsedMutation,
    hash: string,
  ): Promise<MutationResult> {
    const authoritative = await this.findEntity(
      transaction,
      identity.householdId,
      mutation.entityType,
      mutation.entityId,
    );
    if (authoritative === null) {
      return this.storeSimpleRejection(
        transaction,
        identity,
        mutation,
        hash,
        'ENTITY_NOT_FOUND',
      );
    }

    return this.storeConflict(
      transaction,
      identity,
      mutation,
      hash,
      'VERSION_CONFLICT',
      authoritative,
    );
  }

  /**
   * Appends one row to the change feed and returns its sequence.
   *
   * The feed carries every entity type; `entityType` names the schema the
   * stored snapshot document satisfies.
   */
  private async writeChange(
    transaction: Prisma.TransactionClient,
    householdId: string,
    change: {
      entityId: string;
      entityType: SyncEntityType;
      entityVersion: number;
      operation: 'CREATED' | 'UPDATED' | 'DELETED';
      actorMember: MemberKey;
      changedAt: Date;
      originMutationId: string;
      payload: EntityPayload;
    },
  ): Promise<bigint> {
    const snapshot =
      change.payload.entityType === 'EXPENSE'
        ? change.payload.expense
        : change.payload.entityType === 'PERIOD'
          ? change.payload.period
          : change.payload.loan;
    const row = await transaction.expenseChange.create({
      data: {
        householdId,
        entityId: change.entityId,
        entityType: change.entityType,
        entityVersion: change.entityVersion,
        operation: change.operation,
        actorMemberKey: change.actorMember,
        originMutationId: change.originMutationId,
        snapshot: jsonValue(snapshot),
        changedAt: change.changedAt,
      },
    });

    return row.sequence;
  }

  /**
   * Points the entity's own row at the change that produced it, so bootstrap
   * can page under a stable watermark.
   */
  private async linkChange(
    transaction: Prisma.TransactionClient,
    householdId: string,
    record: EntityRecord,
    sequence: bigint,
  ): Promise<void> {
    const where = {
      id: record.row.id,
      householdId,
      version: record.row.version,
    };
    const data = { lastChangeSequence: sequence };
    const linked =
      record.entityType === 'EXPENSE'
        ? await transaction.expense.updateMany({ where, data })
        : record.entityType === 'PERIOD'
          ? await transaction.spendingPeriod.updateMany({ where, data })
          : await transaction.loanEntry.updateMany({ where, data });

    if (linked.count !== 1) {
      throw new AppError(
        500,
        'DATA_INTEGRITY_ERROR',
        'Entity change could not be linked.',
      );
    }
  }

  private async recordApplied(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: ParsedMutation,
    hash: string,
    record: EntityRecord,
    operation: 'CREATED' | 'UPDATED' | 'DELETED',
  ): Promise<MutationResult> {
    const payload = entityPayload(record);
    const sequence = await this.writeChange(transaction, identity.householdId, {
      entityId: record.row.id,
      entityType: record.entityType,
      entityVersion: record.row.version,
      operation,
      actorMember: identity.memberKey,
      changedAt: record.row.updatedAt,
      originMutationId: mutation.mutationId,
      payload,
    });
    await this.linkChange(transaction, identity.householdId, record, sequence);

    const result: MutationResult = {
      mutationId: mutation.mutationId,
      status: 'APPLIED',
      ...payload,
    };
    await this.storeReceipt(
      transaction,
      identity,
      mutation,
      hash,
      result,
      record.entityType,
    );
    return result;
  }

  private async storeConflict(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: ParsedMutation,
    hash: string,
    code: 'ENTITY_EXISTS' | 'VERSION_CONFLICT',
    record: EntityRecord,
  ): Promise<MutationResult> {
    const result: MutationResult = {
      mutationId: mutation.mutationId,
      status: 'CONFLICT',
      code,
      ...entityPayload(record),
    };
    await this.storeReceipt(
      transaction,
      identity,
      mutation,
      hash,
      result,
      record.entityType,
    );
    return result;
  }

  private async storeSimpleRejection(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: ParsedMutation,
    hash: string,
    code:
      | 'ENTITY_NOT_FOUND'
      | 'PAYER_NOT_FOUND'
      | 'PERIOD_ALREADY_OPEN'
      | 'PERIOD_NOT_FOUND',
  ): Promise<MutationResult> {
    const result: MutationResult = {
      mutationId: mutation.mutationId,
      status: 'REJECTED',
      code,
    };
    await this.storeReceipt(
      transaction,
      identity,
      mutation,
      hash,
      result,
      mutation.entityType,
    );
    return result;
  }

  private async storeReceipt(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: MutationBase,
    hash: string,
    result: MutationResult,
    entityType: SyncEntityType,
  ): Promise<void> {
    await transaction.processedMutation.create({
      data: {
        mutationId: mutation.mutationId,
        householdId: identity.householdId,
        memberId: identity.memberId,
        entityId: mutation.entityId,
        entityType,
        operation: mutation.operation,
        requestHash: hash,
        result: jsonValue(result),
      },
    });
  }

  private async findMemberId(
    transaction: Prisma.TransactionClient,
    householdId: string,
    key: 'SUMON' | 'EBRAHIM',
  ): Promise<string | null> {
    const member = await transaction.member.findFirst({
      where: { householdId, key, disabledAt: null },
      select: { id: true },
    });

    return member?.id ?? null;
  }

  private async findExpense(
    transaction: Prisma.TransactionClient,
    householdId: string,
    entityId: string,
  ): Promise<ExpenseWithPayer | null> {
    return transaction.expense.findFirst({
      where: { id: entityId, householdId },
      include: expenseWithPayer,
    });
  }

  private async findPeriod(
    transaction: Prisma.TransactionClient,
    householdId: string,
    entityId: string,
  ): Promise<PeriodRow | null> {
    return transaction.spendingPeriod.findFirst({
      where: { id: entityId, householdId },
    });
  }

  private async findLoan(
    transaction: Prisma.TransactionClient,
    householdId: string,
    entityId: string,
  ): Promise<LoanWithDebtor | null> {
    return transaction.loanEntry.findFirst({
      where: { id: entityId, householdId },
      include: loanWithDebtor,
    });
  }

  private async findEntity(
    transaction: Prisma.TransactionClient,
    householdId: string,
    entityType: SyncEntityType,
    entityId: string,
  ): Promise<EntityRecord | null> {
    switch (entityType) {
      case 'EXPENSE': {
        const row = await this.findExpense(transaction, householdId, entityId);
        return row === null ? null : { entityType, row };
      }
      case 'PERIOD': {
        const row = await this.findPeriod(transaction, householdId, entityId);
        return row === null ? null : { entityType, row };
      }
      case 'LOAN': {
        const row = await this.findLoan(transaction, householdId, entityId);
        return row === null ? null : { entityType, row };
      }
    }
  }

  private async resolveUniqueCollision(
    identity: AuthenticatedMember,
    mutation: MutationBase,
    hash: string,
    entityType: SyncEntityType,
    replays: Set<string>,
  ): Promise<MutationResult> {
    const receipt = await this.prisma.processedMutation.findFirst({
      where: {
        mutationId: mutation.mutationId,
        householdId: identity.householdId,
      },
    });
    if (receipt !== null) {
      // Two copies of one upload raced and the other won. This one wrote
      // nothing, so it is a replay like any other.
      replays.add(mutation.mutationId);
      return receipt.requestHash === hash
        ? mutationResultSchema.parse(receipt.result)
        : {
            mutationId: mutation.mutationId,
            status: 'REJECTED',
            code: 'IDEMPOTENCY_KEY_REUSED',
          };
    }

    const existing = await this.findEntity(
      this.prisma,
      identity.householdId,
      entityType,
      mutation.entityId,
    );
    if (existing !== null && mutation.operation === 'CREATE') {
      return {
        mutationId: mutation.mutationId,
        status: 'CONFLICT',
        code: 'ENTITY_EXISTS',
        ...entityPayload(existing),
      };
    }

    // A period's only other unique keys are its sequence number and the partial
    // index that admits one open period per household, so a collision on a
    // different id means another period already occupies the slot.
    return {
      mutationId: mutation.mutationId,
      status: 'REJECTED',
      code:
        entityType === 'PERIOD'
          ? 'PERIOD_ALREADY_OPEN'
          : 'ENTITY_ID_UNAVAILABLE',
    };
  }
}
