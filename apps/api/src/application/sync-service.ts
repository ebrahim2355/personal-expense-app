import { createHash } from 'node:crypto';

import { z } from 'zod';

import { AppError, validationIssues } from '../domain/errors.js';
import type {
  AuthenticatedMember,
  ExpenseSnapshot,
  MutationBase,
  MutationResult,
  ParsedMutation,
} from '../domain/models.js';
import { parsedMutationSchema } from '../domain/validation.js';
import { Prisma } from '../generated/prisma/client.js';
import type { DatabaseClient } from '../infrastructure/prisma.js';
import type { TokenService } from '../infrastructure/token-service.js';

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

const snapshotSchema = z
  .object({
    id: z.uuid(),
    amountMinor: z.number().int().safe().positive(),
    category: z.enum([
      'GROCERIES',
      'UTILITIES',
      'TRANSPORT',
      'HOUSEHOLD',
      'MEDICINE',
      'OTHER',
    ]),
    payer: z.enum(['SUMON', 'EBRAHIM']),
    occurredAt: z.string().datetime({ offset: true }),
    note: z.string().nullable(),
    version: z.number().int().positive(),
    updatedAt: z.string().datetime({ offset: true }),
    deletedAt: z.string().datetime({ offset: true }).nullable(),
  })
  .strict();

const mutationResultSchema = z.discriminatedUnion('status', [
  z.object({
    mutationId: z.uuid(),
    status: z.literal('APPLIED'),
    expense: snapshotSchema,
  }),
  z.object({
    mutationId: z.uuid(),
    status: z.literal('CONFLICT'),
    code: z.enum(['ENTITY_EXISTS', 'VERSION_CONFLICT']),
    expense: snapshotSchema,
  }),
  z.object({
    mutationId: z.uuid(),
    status: z.literal('REJECTED'),
    code: z.enum([
      'ENTITY_ID_UNAVAILABLE',
      'ENTITY_NOT_FOUND',
      'IDEMPOTENCY_KEY_REUSED',
      'INVALID_MUTATION',
      'PAYER_NOT_FOUND',
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
]);

interface ChangeView {
  cursor: string;
  entityType: 'EXPENSE';
  operation: 'CREATED' | 'UPDATED' | 'DELETED';
  originMutationId: string;
  expense: ExpenseSnapshot;
}

interface ChangePage {
  changes: ChangeView[];
  nextCursor: string;
  hasMore: boolean;
}

interface BootstrapPage {
  items: ExpenseSnapshot[];
  watermarkCursor: string;
  nextPageToken: string | null;
  hasMore: boolean;
}

function snapshot(expense: ExpenseWithPayer): ExpenseSnapshot {
  const amountMinor = Number(expense.amountMinor);
  if (!Number.isSafeInteger(amountMinor)) {
    throw new AppError(
      500,
      'DATA_INTEGRITY_ERROR',
      'Stored expense data is invalid.',
    );
  }

  return {
    id: expense.id,
    amountMinor,
    category: expense.category,
    payer: expense.payer.key,
    occurredAt: expense.occurredAt.toISOString(),
    note: expense.note,
    version: expense.version,
    updatedAt: expense.updatedAt.toISOString(),
    deletedAt: expense.deletedAt?.toISOString() ?? null,
  };
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
  ) {}

  public async applyMutations(
    identity: AuthenticatedMember,
    mutations: MutationBase[],
  ): Promise<MutationResult[]> {
    const results: MutationResult[] = [];

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
        ),
      );
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
        entityType: 'EXPENSE',
        operation: row.operation,
        originMutationId: row.originMutationId,
        expense: snapshotSchema.parse(row.snapshot),
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
    let watermark: bigint;
    let afterId: string | undefined;

    if (pageToken === undefined) {
      const aggregate = await this.prisma.expenseChange.aggregate({
        where: { householdId: identity.householdId },
        _max: { sequence: true },
      });
      watermark = aggregate._max.sequence ?? 0n;
    } else {
      const decoded = this.tokens.decodeBootstrapToken(
        pageToken,
        identity.householdId,
      );
      watermark = decoded.watermark;
      afterId = decoded.afterId;
    }

    const expenses = await this.prisma.expense.findMany({
      where: {
        householdId: identity.householdId,
        lastChangeSequence: { lte: watermark },
        ...(afterId === undefined ? {} : { id: { gt: afterId } }),
      },
      include: expenseWithPayer,
      orderBy: { id: 'asc' },
      take: limit + 1,
    });
    const hasMore = expenses.length > limit;
    const pageExpenses = expenses.slice(0, limit);
    const lastId = pageExpenses.at(-1)?.id;

    return {
      items: pageExpenses.map((expense) => snapshot(expense)),
      watermarkCursor: this.tokens.encodeChangeCursor(
        identity.householdId,
        watermark,
      ),
      nextPageToken:
        hasMore && lastId !== undefined
          ? this.tokens.encodeBootstrapToken(
              identity.householdId,
              watermark,
              lastId,
            )
          : null,
      hasMore,
    };
  }

  private async processWithRetry(
    identity: AuthenticatedMember,
    base: MutationBase,
    mutation: ParsedMutation | undefined,
    invalidResult: MutationResult | undefined,
    hash: string,
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
            ),
          { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
        );
      } catch (error) {
        const code = prismaErrorCode(error);
        if (code === 'P2034' && attempt < 3) {
          continue;
        }
        if (code === 'P2002') {
          return this.resolveUniqueCollision(identity, base, hash);
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
  ): Promise<MutationResult> {
    await lockHouseholdWrites(transaction, identity.householdId);

    const receipt = await transaction.processedMutation.findFirst({
      where: {
        mutationId: base.mutationId,
        householdId: identity.householdId,
      },
    });
    if (receipt !== null) {
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
      await this.storeReceipt(transaction, identity, base, hash, result);
      return result;
    }

    if (mutation.operation === 'CREATE') {
      return this.createExpense(transaction, identity, mutation, hash);
    }
    if (mutation.operation === 'UPDATE') {
      return this.updateExpense(transaction, identity, mutation, hash);
    }
    return this.deleteExpense(transaction, identity, mutation, hash);
  }

  private async createExpense(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: Extract<ParsedMutation, { operation: 'CREATE' }>,
    hash: string,
  ): Promise<MutationResult> {
    const existing = await this.findExpense(
      transaction,
      identity.householdId,
      mutation.entityId,
    );
    if (existing !== null) {
      const result: MutationResult = {
        mutationId: mutation.mutationId,
        status: 'CONFLICT',
        code: 'ENTITY_EXISTS',
        expense: snapshot(existing),
      };
      await this.storeReceipt(transaction, identity, mutation, hash, result);
      return result;
    }

    const payer = await transaction.member.findFirst({
      where: {
        householdId: identity.householdId,
        key: mutation.expense.payer,
        disabledAt: null,
      },
      select: { id: true },
    });
    if (payer === null) {
      return this.storeSimpleRejection(
        transaction,
        identity,
        mutation,
        hash,
        'PAYER_NOT_FOUND',
      );
    }

    const now = new Date();
    const created = await transaction.expense.create({
      data: {
        id: mutation.entityId,
        householdId: identity.householdId,
        amountMinor: BigInt(mutation.expense.amountMinor),
        category: mutation.expense.category,
        payerId: payer.id,
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
      created,
      'CREATED',
    );
  }

  private async updateExpense(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: Extract<ParsedMutation, { operation: 'UPDATE' }>,
    hash: string,
  ): Promise<MutationResult> {
    const payer = await transaction.member.findFirst({
      where: {
        householdId: identity.householdId,
        key: mutation.expense.payer,
        disabledAt: null,
      },
      select: { id: true },
    });
    if (payer === null) {
      return this.storeSimpleRejection(
        transaction,
        identity,
        mutation,
        hash,
        'PAYER_NOT_FOUND',
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
        payerId: payer.id,
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
      expense,
      'UPDATED',
    );
  }

  private async deleteExpense(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: Extract<ParsedMutation, { operation: 'DELETE' }>,
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
      expense,
      'DELETED',
    );
  }

  private async versionFailure(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: ParsedMutation,
    hash: string,
  ): Promise<MutationResult> {
    const authoritative = await this.findExpense(
      transaction,
      identity.householdId,
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

    const result: MutationResult = {
      mutationId: mutation.mutationId,
      status: 'CONFLICT',
      code: 'VERSION_CONFLICT',
      expense: snapshot(authoritative),
    };
    await this.storeReceipt(transaction, identity, mutation, hash, result);
    return result;
  }

  private async recordApplied(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: ParsedMutation,
    hash: string,
    expense: ExpenseWithPayer,
    operation: 'CREATED' | 'UPDATED' | 'DELETED',
  ): Promise<MutationResult> {
    const expenseSnapshot = snapshot(expense);
    const change = await transaction.expenseChange.create({
      data: {
        householdId: identity.householdId,
        entityId: expense.id,
        entityVersion: expense.version,
        operation,
        originMutationId: mutation.mutationId,
        snapshot: jsonValue(expenseSnapshot),
        changedAt: expense.updatedAt,
      },
    });
    const linked = await transaction.expense.updateMany({
      where: {
        id: expense.id,
        householdId: identity.householdId,
        version: expense.version,
      },
      data: { lastChangeSequence: change.sequence },
    });
    if (linked.count !== 1) {
      throw new AppError(
        500,
        'DATA_INTEGRITY_ERROR',
        'Expense change could not be linked.',
      );
    }

    const result: MutationResult = {
      mutationId: mutation.mutationId,
      status: 'APPLIED',
      expense: expenseSnapshot,
    };
    await this.storeReceipt(transaction, identity, mutation, hash, result);
    return result;
  }

  private async storeSimpleRejection(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: MutationBase,
    hash: string,
    code: 'ENTITY_NOT_FOUND' | 'PAYER_NOT_FOUND',
  ): Promise<MutationResult> {
    const result: MutationResult = {
      mutationId: mutation.mutationId,
      status: 'REJECTED',
      code,
    };
    await this.storeReceipt(transaction, identity, mutation, hash, result);
    return result;
  }

  private async storeReceipt(
    transaction: Prisma.TransactionClient,
    identity: AuthenticatedMember,
    mutation: MutationBase,
    hash: string,
    result: MutationResult,
  ): Promise<void> {
    await transaction.processedMutation.create({
      data: {
        mutationId: mutation.mutationId,
        householdId: identity.householdId,
        memberId: identity.memberId,
        entityId: mutation.entityId,
        operation: mutation.operation,
        requestHash: hash,
        result: jsonValue(result),
      },
    });
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

  private async resolveUniqueCollision(
    identity: AuthenticatedMember,
    mutation: MutationBase,
    hash: string,
  ): Promise<MutationResult> {
    const receipt = await this.prisma.processedMutation.findFirst({
      where: {
        mutationId: mutation.mutationId,
        householdId: identity.householdId,
      },
    });
    if (receipt !== null) {
      return receipt.requestHash === hash
        ? mutationResultSchema.parse(receipt.result)
        : {
            mutationId: mutation.mutationId,
            status: 'REJECTED',
            code: 'IDEMPOTENCY_KEY_REUSED',
          };
    }

    const expense = await this.prisma.expense.findFirst({
      where: {
        id: mutation.entityId,
        householdId: identity.householdId,
      },
      include: expenseWithPayer,
    });
    if (expense !== null && mutation.operation === 'CREATE') {
      return {
        mutationId: mutation.mutationId,
        status: 'CONFLICT',
        code: 'ENTITY_EXISTS',
        expense: snapshot(expense),
      };
    }

    return {
      mutationId: mutation.mutationId,
      status: 'REJECTED',
      code: 'ENTITY_ID_UNAVAILABLE',
    };
  }
}
