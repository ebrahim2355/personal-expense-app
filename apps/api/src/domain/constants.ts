export const MEMBER_KEYS = ['SUMON', 'EBRAHIM'] as const;
export type MemberKey = (typeof MEMBER_KEYS)[number];

export const EXPENSE_CATEGORIES = [
  'GROCERIES',
  'UTILITIES',
  'TRANSPORT',
  'HOUSEHOLD',
  'MEDICINE',
  'OTHER',
] as const;
export type ExpenseCategory = (typeof EXPENSE_CATEGORIES)[number];

export const MUTATION_OPERATIONS = ['CREATE', 'UPDATE', 'DELETE'] as const;
export type MutationOperation = (typeof MUTATION_OPERATIONS)[number];

export const SYNC_ENTITY_TYPES = ['EXPENSE', 'PERIOD', 'LOAN'] as const;
export type SyncEntityType = (typeof SYNC_ENTITY_TYPES)[number];

/** Money is stored as poisha; only whole taka are accepted. */
export const POISHA_PER_TAKA = 100;
export const MIN_AMOUNT_MINOR = POISHA_PER_TAKA;
export const MAX_AMOUNT_MINOR = 99_999_999_999;
export const MAX_SEQUENCE_NUMBER = 2_147_483_647;
export const MAX_NOTE_CODE_POINTS = 500;
export const MAX_MUTATIONS_PER_REQUEST = 50;
export const DEFAULT_PAGE_SIZE = 100;
export const MAX_PAGE_SIZE = 250;
