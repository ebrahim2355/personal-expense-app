import type {
  ExpenseCategory,
  MemberKey,
  MutationOperation,
} from './constants.js';

export interface AuthenticatedMember {
  memberId: string;
  householdId: string;
  memberKey: MemberKey;
}

export interface MemberView {
  id: string;
  householdId: string;
  key: MemberKey;
  displayName: string;
}

export interface ExpenseInput {
  amountMinor: number;
  category: ExpenseCategory;
  payer: MemberKey;
  occurredAt: Date;
  note: string | null;
}

export interface ExpenseSnapshot {
  id: string;
  amountMinor: number;
  category: ExpenseCategory;
  payer: MemberKey;
  occurredAt: string;
  note: string | null;
  version: number;
  updatedAt: string;
  deletedAt: string | null;
}

export interface MutationBase {
  mutationId: string;
  entityId: string;
  operation: MutationOperation;
  baseVersion: number;
  expense?: unknown;
}

export type ParsedMutation =
  | {
      mutationId: string;
      entityId: string;
      operation: 'CREATE';
      baseVersion: 0;
      expense: ExpenseInput;
    }
  | {
      mutationId: string;
      entityId: string;
      operation: 'UPDATE';
      baseVersion: number;
      expense: ExpenseInput;
    }
  | {
      mutationId: string;
      entityId: string;
      operation: 'DELETE';
      baseVersion: number;
    };

export type MutationResult =
  | {
      mutationId: string;
      status: 'APPLIED';
      expense: ExpenseSnapshot;
    }
  | {
      mutationId: string;
      status: 'CONFLICT';
      code: 'ENTITY_EXISTS' | 'VERSION_CONFLICT';
      expense: ExpenseSnapshot;
    }
  | {
      mutationId: string;
      status: 'REJECTED';
      code:
        | 'ENTITY_ID_UNAVAILABLE'
        | 'ENTITY_NOT_FOUND'
        | 'IDEMPOTENCY_KEY_REUSED'
        | 'INVALID_MUTATION'
        | 'PAYER_NOT_FOUND';
      details?: ValidationIssue[] | undefined;
    };

export interface ValidationIssue {
  path: string;
  code: string;
  message: string;
}
