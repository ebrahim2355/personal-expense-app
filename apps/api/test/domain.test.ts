import { randomUUID } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { MAX_AMOUNT_MINOR } from '../src/domain/constants.js';
import { splitAmountMinor } from '../src/domain/money.js';
import {
  bootstrapQuerySchema,
  changesQuerySchema,
  expenseInputSchema,
  loanInputSchema,
  parsedMutationSchema,
  periodInputSchema,
} from '../src/domain/validation.js';

/** The largest whole-taka amount the poisha ceiling admits. */
const MAX_WHOLE_TAKA_MINOR = 99_999_999_900;

function createMutation(expense: unknown): unknown {
  return {
    mutationId: randomUUID(),
    entityId: randomUUID(),
    operation: 'CREATE',
    baseVersion: 0,
    expense,
  };
}

const validExpense = {
  amountMinor: 12_300,
  category: 'GROCERIES',
  payer: 'SUMON',
  occurredAt: '2026-08-13T10:30:00+06:00',
  note: 'Lunch',
};

const validPeriod = {
  sequenceNumber: 1,
  startedAt: '2026-08-01T00:00:00+06:00',
  closedAt: null,
  note: null,
};

const validLoan = {
  debtor: 'EBRAHIM',
  amountMinor: 50_000,
  occurredAt: '2026-08-13T10:30:00+06:00',
  note: 'Rickshaw fare',
};

describe('integer money rules', () => {
  it('assigns an odd-taka remainder to the payer share', () => {
    expect(splitAmountMinor(80_000)).toEqual({
      payerShareMinor: 40_000,
      otherShareMinor: 40_000,
    });
    expect(splitAmountMinor(10_100)).toEqual({
      payerShareMinor: 5100,
      otherShareMinor: 5000,
    });
    expect(splitAmountMinor(MAX_WHOLE_TAKA_MINOR)).toEqual({
      payerShareMinor: 50_000_000_000,
      otherShareMinor: 49_999_999_900,
    });
  });

  it.each([
    0,
    -1,
    1,
    99,
    150,
    1.5,
    Number.NaN,
    MAX_AMOUNT_MINOR,
    MAX_AMOUNT_MINOR + 1,
  ])('rejects an unsupported amount: %s', (amountMinor) => {
    expect(() => splitAmountMinor(amountMinor)).toThrow(RangeError);
  });
});

describe('pagination validation', () => {
  it.each([changesQuerySchema, bootstrapQuerySchema])(
    'enforces the documented maximum page size',
    (schema) => {
      expect(schema.safeParse({ limit: '250' }).success).toBe(true);
      expect(schema.safeParse({ limit: '251' }).success).toBe(false);
    },
  );
});

describe('expense validation', () => {
  it.each([
    0,
    -1,
    1,
    99,
    150,
    1.1,
    MAX_AMOUNT_MINOR,
    MAX_AMOUNT_MINOR + 1,
    Number.MAX_SAFE_INTEGER + 1,
  ])('rejects invalid amountMinor %s', (amountMinor) => {
    expect(
      parsedMutationSchema.safeParse(
        createMutation({ ...validExpense, amountMinor }),
      ).success,
    ).toBe(false);
  });

  it('accepts the largest whole-taka amount', () => {
    expect(
      expenseInputSchema.parse({
        ...validExpense,
        amountMinor: MAX_WHOLE_TAKA_MINOR,
      }).amountMinor,
    ).toBe(MAX_WHOLE_TAKA_MINOR);
  });

  it.each([
    ['payer', 'UNKNOWN'],
    ['category', 'DINING'],
    ['occurredAt', '2026-08-13'],
    ['occurredAt', 'not-a-date'],
    ['note', 'x'.repeat(501)],
    ['periodId', 'not-a-uuid'],
  ])('rejects invalid %s', (field, value) => {
    expect(
      parsedMutationSchema.safeParse(
        createMutation({ ...validExpense, [field]: value }),
      ).success,
    ).toBe(false);
  });

  it('leaves an omitted periodId for the server to resolve', () => {
    expect(expenseInputSchema.parse(validExpense).periodId).toBeUndefined();
  });

  it('trims notes and normalizes an empty note to null', () => {
    const parsed = expenseInputSchema.parse({ ...validExpense, note: '   ' });

    expect(parsed.note).toBeNull();
  });

  it('converts Asia/Dhaka calendar boundaries to their UTC instants', () => {
    const start = expenseInputSchema.parse({
      ...validExpense,
      occurredAt: '2026-08-01T00:00:00+06:00',
    });
    const end = expenseInputSchema.parse({
      ...validExpense,
      occurredAt: '2026-09-01T00:00:00+06:00',
    });

    expect(start.occurredAt.toISOString()).toBe('2026-07-31T18:00:00.000Z');
    expect(end.occurredAt.toISOString()).toBe('2026-08-31T18:00:00.000Z');
  });
});

describe('spending period validation', () => {
  it('reads an omitted closedAt as an open period', () => {
    const parsed = periodInputSchema.parse({
      sequenceNumber: 1,
      startedAt: validPeriod.startedAt,
    });

    expect(parsed.closedAt).toBeNull();
    expect(parsed.note).toBeNull();
  });

  it('accepts a period closed at the instant it started', () => {
    const parsed = periodInputSchema.parse({
      ...validPeriod,
      closedAt: validPeriod.startedAt,
    });

    expect(parsed.closedAt?.toISOString()).toBe('2026-07-31T18:00:00.000Z');
  });

  it('rejects a closedAt that precedes startedAt', () => {
    const parsed = periodInputSchema.safeParse({
      ...validPeriod,
      closedAt: '2026-07-01T00:00:00+06:00',
    });

    expect(parsed.success).toBe(false);
    expect(parsed.error?.issues[0]?.path).toEqual(['closedAt']);
  });

  it.each([
    ['sequenceNumber', 0],
    ['sequenceNumber', 1.5],
    ['sequenceNumber', 2_147_483_648],
    ['startedAt', '2026-08-01'],
    ['note', 'x'.repeat(501)],
  ])('rejects invalid %s', (field, value) => {
    expect(
      periodInputSchema.safeParse({ ...validPeriod, [field]: value }).success,
    ).toBe(false);
  });
});

describe('loan validation', () => {
  it('records who owes the money and normalizes a blank note', () => {
    const parsed = loanInputSchema.parse({ ...validLoan, note: '  ' });

    expect(parsed.debtor).toBe('EBRAHIM');
    expect(parsed.note).toBeNull();
  });

  it.each([0, -1, 1, 99, 150, 1.1, MAX_AMOUNT_MINOR])(
    'rejects invalid amountMinor %s',
    (amountMinor) => {
      expect(
        loanInputSchema.safeParse({ ...validLoan, amountMinor }).success,
      ).toBe(false);
    },
  );

  it.each([
    ['debtor', 'UNKNOWN'],
    ['occurredAt', '2026-08-13'],
    ['note', 'x'.repeat(501)],
  ])('rejects invalid %s', (field, value) => {
    expect(
      loanInputSchema.safeParse({ ...validLoan, [field]: value }).success,
    ).toBe(false);
  });
});

describe('mutation entity discrimination', () => {
  it('reads a candidate without an entityType as an expense', () => {
    const parsed = parsedMutationSchema.parse(createMutation(validExpense));

    expect(parsed.entityType).toBe('EXPENSE');
  });

  it.each([
    ['PERIOD', { period: validPeriod }],
    ['LOAN', { loan: validLoan }],
  ])('parses an explicit %s candidate', (entityType, payload) => {
    const parsed = parsedMutationSchema.parse({
      mutationId: randomUUID(),
      entityId: randomUUID(),
      entityType,
      operation: 'CREATE',
      baseVersion: 0,
      ...payload,
    });

    expect(parsed.entityType).toBe(entityType);
  });

  it('rejects a candidate whose payload belongs to another entity', () => {
    expect(
      parsedMutationSchema.safeParse({
        mutationId: randomUUID(),
        entityId: randomUUID(),
        entityType: 'PERIOD',
        operation: 'CREATE',
        baseVersion: 0,
        expense: validExpense,
      }).success,
    ).toBe(false);
  });

  it('rejects deleting a spending period, because expenses reference it', () => {
    expect(
      parsedMutationSchema.safeParse({
        mutationId: randomUUID(),
        entityId: randomUUID(),
        entityType: 'PERIOD',
        operation: 'DELETE',
        baseVersion: 1,
      }).success,
    ).toBe(false);
  });

  it('accepts deleting a loan, which is a purely manual record', () => {
    const parsed = parsedMutationSchema.parse({
      mutationId: randomUUID(),
      entityId: randomUUID(),
      entityType: 'LOAN',
      operation: 'DELETE',
      baseVersion: 1,
    });

    expect(parsed).toMatchObject({ entityType: 'LOAN', operation: 'DELETE' });
  });
});
