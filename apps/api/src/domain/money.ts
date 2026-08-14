import { MAX_AMOUNT_MINOR } from './constants.js';

export interface EqualSplit {
  payerShareMinor: number;
  otherShareMinor: number;
}

export function splitAmountMinor(amountMinor: number): EqualSplit {
  if (
    !Number.isSafeInteger(amountMinor) ||
    amountMinor < 1 ||
    amountMinor > MAX_AMOUNT_MINOR
  ) {
    throw new RangeError('amountMinor is outside the supported integer range.');
  }

  // Convert at the boundary so no monetary calculation passes through binary
  // floating-point division. Both results remain within the JSON-safe range.
  const amount = BigInt(amountMinor);
  const otherShareMinor = amount / 2n;

  return {
    payerShareMinor: Number(otherShareMinor + (amount % 2n)),
    otherShareMinor: Number(otherShareMinor),
  };
}
