import { z } from 'zod';

import {
  DEFAULT_PAGE_SIZE,
  EXPENSE_CATEGORIES,
  MAX_AMOUNT_MINOR,
  MAX_MUTATIONS_PER_REQUEST,
  MAX_NOTE_CODE_POINTS,
  MAX_PAGE_SIZE,
  MEMBER_KEYS,
  MUTATION_OPERATIONS,
} from './constants.js';

const uuidSchema = z.uuid();

const occurredAtSchema = z
  .string()
  .datetime({ offset: true })
  .transform((value) => new Date(value));

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
    amountMinor: z.number().int().safe().min(1).max(MAX_AMOUNT_MINOR),
    category: z.enum(EXPENSE_CATEGORIES),
    payer: z.enum(MEMBER_KEYS),
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

export const mutationBaseSchema = z
  .object({
    mutationId: uuidSchema,
    entityId: uuidSchema,
    operation: z.enum(MUTATION_OPERATIONS),
    baseVersion: z.number().int().min(0).max(2_147_483_646),
    expense: z.unknown().optional(),
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

export const parsedMutationSchema = z.discriminatedUnion('operation', [
  z
    .object({
      mutationId: uuidSchema,
      entityId: uuidSchema,
      operation: z.literal('CREATE'),
      baseVersion: z.literal(0),
      expense: expenseInputSchema,
    })
    .strict(),
  z
    .object({
      mutationId: uuidSchema,
      entityId: uuidSchema,
      operation: z.literal('UPDATE'),
      baseVersion: z.number().int().min(1).max(2_147_483_646),
      expense: expenseInputSchema,
    })
    .strict(),
  z
    .object({
      mutationId: uuidSchema,
      entityId: uuidSchema,
      operation: z.literal('DELETE'),
      baseVersion: z.number().int().min(1).max(2_147_483_646),
      expense: z.undefined().optional(),
    })
    .strict(),
]);

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
