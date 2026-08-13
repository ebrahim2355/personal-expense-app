import { randomUUID } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { MAX_AMOUNT_MINOR } from '../src/domain/constants.js';
import { splitAmountMinor } from '../src/domain/money.js';
import {
  expenseInputSchema,
  parsedMutationSchema,
} from '../src/domain/validation.js';

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
  amountMinor: 12_345,
  category: 'GROCERIES',
  payer: 'SUMON',
  occurredAt: '2026-08-13T10:30:00+06:00',
  note: 'Lunch',
};

describe('integer money rules', () => {
  it('assigns an odd-poisha remainder to the payer share', () => {
    expect(splitAmountMinor(80_000)).toEqual({
      payerShareMinor: 40_000,
      otherShareMinor: 40_000,
    });
    expect(splitAmountMinor(10_001)).toEqual({
      payerShareMinor: 5001,
      otherShareMinor: 5000,
    });
  });

  it.each([0, -1, 1.5, Number.NaN, MAX_AMOUNT_MINOR + 1])(
    'rejects an unsupported amount: %s',
    (amountMinor) => {
      expect(() => splitAmountMinor(amountMinor)).toThrow(RangeError);
    },
  );
});

describe('expense validation', () => {
  it.each([0, -1, 1.1, MAX_AMOUNT_MINOR + 1, Number.MAX_SAFE_INTEGER + 1])(
    'rejects invalid amountMinor %s',
    (amountMinor) => {
      expect(
        parsedMutationSchema.safeParse(
          createMutation({ ...validExpense, amountMinor }),
        ).success,
      ).toBe(false);
    },
  );

  it.each([
    ['payer', 'UNKNOWN'],
    ['category', 'DINING'],
    ['occurredAt', '2026-08-13'],
    ['occurredAt', 'not-a-date'],
    ['note', 'x'.repeat(501)],
  ])('rejects invalid %s', (field, value) => {
    expect(
      parsedMutationSchema.safeParse(
        createMutation({ ...validExpense, [field]: value }),
      ).success,
    ).toBe(false);
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
