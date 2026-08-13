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

  const otherShareMinor = Math.floor(amountMinor / 2);

  return {
    payerShareMinor: otherShareMinor + (amountMinor % 2),
    otherShareMinor,
  };
}
