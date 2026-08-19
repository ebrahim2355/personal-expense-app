import { z } from 'zod';

import {
  DEFAULT_PAGE_SIZE,
  DEVICE_PLATFORMS,
  EXPENSE_CATEGORIES,
  MAX_AMOUNT_MINOR,
  MAX_DEVICE_TOKEN_LENGTH,
  MAX_MUTATIONS_PER_REQUEST,
  MAX_NOTE_CODE_POINTS,
  MAX_PAGE_SIZE,
  MAX_SEQUENCE_NUMBER,
  MEMBER_KEYS,
  MIN_AMOUNT_MINOR,
  MIN_DEVICE_TOKEN_LENGTH,
  MUTATION_OPERATIONS,
  POISHA_PER_TAKA,
  SYNC_ENTITY_TYPES,
} from './constants.js';

const uuidSchema = z.uuid();

const occurredAtSchema = z
  .string()
  .datetime({ offset: true })
  .transform((value) => new Date(value));

const nullableTimestampSchema = z
  .string()
  .datetime({ offset: true })
  .nullable()
  .optional()
  .transform((value): Date | null =>
    value === undefined || value === null ? null : new Date(value),
  );

const amountMinorSchema = z
  .number()
  .int()
  .safe()
  .min(MIN_AMOUNT_MINOR)
  .max(MAX_AMOUNT_MINOR)
  .refine((value) => value % POISHA_PER_TAKA === 0, {
    message: 'Amount must be a whole number of taka.',
  });

const noteSchema = z
  .string()
  .nullable()
  .optional()
  .transform((value, context): string | null => {
    if (value === undefined || value === null) {
      return null;
    }

    const trimmed = value.trim();
    if ([...trimmed].length > MAX_NOTE_CODE_POINTS) {
      context.addIssue({
        code: 'custom',
        message: `Note must contain at most ${String(MAX_NOTE_CODE_POINTS)} Unicode code points.`,
      });
      return z.NEVER;
    }

    return trimmed.length === 0 ? null : trimmed;
  });

export const expenseInputSchema = z
  .object({
    amountMinor: amountMinorSchema,
    category: z.enum(EXPENSE_CATEGORIES),
    payer: z.enum(MEMBER_KEYS),
    occurredAt: occurredAtSchema,
    note: noteSchema,
    periodId: uuidSchema.optional(),
  })
  .strict();

export const periodInputSchema = z
  .object({
    sequenceNumber: z.number().int().min(1).max(MAX_SEQUENCE_NUMBER),
    startedAt: occurredAtSchema,
    closedAt: nullableTimestampSchema,
    note: noteSchema,
  })
  .strict()
  .refine(
    ({ startedAt, closedAt }) => closedAt === null || closedAt >= startedAt,
    { message: 'closedAt must not precede startedAt.', path: ['closedAt'] },
  );

export const loanInputSchema = z
  .object({
    debtor: z.enum(MEMBER_KEYS),
    amountMinor: amountMinorSchema,
    occurredAt: occurredAtSchema,
    note: noteSchema,
  })
  .strict();

export const loginSchema = z
  .object({
    member: z.enum(MEMBER_KEYS),
    pin: z.string().regex(/^\d{6,12}$/, 'PIN must contain 6 to 12 digits.'),
  })
  .strict();

export const refreshSchema = z
  .object({
    refreshToken: z.string().min(80).max(200),
  })
  .strict();

export const logoutSchema = refreshSchema;

const deviceTokenSchema = z
  .string()
  .min(MIN_DEVICE_TOKEN_LENGTH)
  .max(MAX_DEVICE_TOKEN_LENGTH);

export const deviceRegistrationSchema = z
  .object({
    token: deviceTokenSchema,
    platform: z.enum(DEVICE_PLATFORMS),
  })
  .strict();

export const deviceUnregistrationSchema = z
  .object({
    token: deviceTokenSchema,
  })
  .strict();

export const mutationBaseSchema = z
  .object({
    mutationId: uuidSchema,
    entityId: uuidSchema,
    entityType: z.enum(SYNC_ENTITY_TYPES).optional(),
    operation: z.enum(MUTATION_OPERATIONS),
    baseVersion: z.number().int().min(0).max(2_147_483_646),
    expense: z.unknown().optional(),
    period: z.unknown().optional(),
    loan: z.unknown().optional(),
  })
  .strict();

export const mutationEnvelopeSchema = z
  .object({
    mutations: z
      .array(mutationBaseSchema)
      .min(1)
      .max(MAX_MUTATIONS_PER_REQUEST),
  })
  .strict();

const identityShape = {
  mutationId: uuidSchema,
  entityId: uuidSchema,
} as const;

const createVersionSchema = z.literal(0);
const existingVersionSchema = z.number().int().min(1).max(2_147_483_646);

const expenseMutationSchema = z.discriminatedUnion('operation', [
  z
    .object({
      ...identityShape,
      entityType: z.literal('EXPENSE'),
      operation: z.literal('CREATE'),
      baseVersion: createVersionSchema,
      expense: expenseInputSchema,
    })
    .strict(),
  z
    .object({
      ...identityShape,
      entityType: z.literal('EXPENSE'),
      operation: z.literal('UPDATE'),
      baseVersion: existingVersionSchema,
      expense: expenseInputSchema,
    })
    .strict(),
  z
    .object({
      ...identityShape,
      entityType: z.literal('EXPENSE'),
      operation: z.literal('DELETE'),
      baseVersion: existingVersionSchema,
      expense: z.undefined().optional(),
    })
    .strict(),
]);

// A period is never deleted, because active expenses reference it.
const periodMutationSchema = z.discriminatedUnion('operation', [
  z
    .object({
      ...identityShape,
      entityType: z.literal('PERIOD'),
      operation: z.literal('CREATE'),
      baseVersion: createVersionSchema,
      period: periodInputSchema,
    })
    .strict(),
  z
    .object({
      ...identityShape,
      entityType: z.literal('PERIOD'),
      operation: z.literal('UPDATE'),
      baseVersion: existingVersionSchema,
      period: periodInputSchema,
    })
    .strict(),
]);

const loanMutationSchema = z.discriminatedUnion('operation', [
  z
    .object({
      ...identityShape,
      entityType: z.literal('LOAN'),
      operation: z.literal('CREATE'),
      baseVersion: createVersionSchema,
      loan: loanInputSchema,
    })
    .strict(),
  z
    .object({
      ...identityShape,
      entityType: z.literal('LOAN'),
      operation: z.literal('UPDATE'),
      baseVersion: existingVersionSchema,
      loan: loanInputSchema,
    })
    .strict(),
  z
    .object({
      ...identityShape,
      entityType: z.literal('LOAN'),
      operation: z.literal('DELETE'),
      baseVersion: existingVersionSchema,
      loan: z.undefined().optional(),
    })
    .strict(),
]);

/**
 * Reads an omitted entityType as EXPENSE so a candidate written before periods
 * and loans existed still parses to exactly the same mutation.
 */
export const parsedMutationSchema = z.preprocess(
  (value) => {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      return value;
    }

    const candidate = value as Record<string, unknown>;
    return candidate.entityType === undefined
      ? { ...candidate, entityType: 'EXPENSE' }
      : candidate;
  },
  z.discriminatedUnion('entityType', [
    expenseMutationSchema,
    periodMutationSchema,
    loanMutationSchema,
  ]),
);

const limitSchema = z.preprocess(
  (value) =>
    typeof value === 'string' && /^\d+$/.test(value) ? Number(value) : value,
  z.number().int().min(1).max(MAX_PAGE_SIZE).default(DEFAULT_PAGE_SIZE),
);

export const changesQuerySchema = z
  .object({
    cursor: z.string().min(1).max(2048).optional(),
    limit: limitSchema,
  })
  .strict();

export const bootstrapQuerySchema = z
  .object({
    pageToken: z.string().min(1).max(4096).optional(),
    limit: limitSchema,
  })
  .strict();
