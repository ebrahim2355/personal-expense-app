import {
  MAX_AMOUNT_MINOR,
  MIN_AMOUNT_MINOR,
  POISHA_PER_TAKA,
} from './constants.js';

export interface EqualSplit {
  payerShareMinor: number;
  otherShareMinor: number;
}

/**
 * Splits a shared expense in half at whole-taka precision.
 *
 * Amounts are whole taka, and no screen ever shows a fraction of a taka, so an
 * odd total cannot be halved evenly. The extra taka is allocated to the payer,
 * which keeps the two shares summing exactly to the total and keeps the
 * asymmetry visible only in the settlement figure.
 */
export function splitAmountMinor(amountMinor: number): EqualSplit {
  if (
    !Number.isSafeInteger(amountMinor) ||
    amountMinor < MIN_AMOUNT_MINOR ||
    amountMinor > MAX_AMOUNT_MINOR ||
    amountMinor % POISHA_PER_TAKA !== 0
  ) {
    throw new RangeError('amountMinor must be a whole taka amount in poisha.');
  }

  // Convert at the boundary so no monetary calculation passes through binary
  // floating-point division. Both results remain within the JSON-safe range.
  const taka = BigInt(amountMinor) / BigInt(POISHA_PER_TAKA);
  const otherShareTaka = taka / 2n;
  const payerShareTaka = otherShareTaka + (taka % 2n);

  return {
    payerShareMinor: Number(payerShareTaka * BigInt(POISHA_PER_TAKA)),
    otherShareMinor: Number(otherShareTaka * BigInt(POISHA_PER_TAKA)),
  };
}
