import type {
  ExpenseCategory,
  MemberKey,
  MutationOperation,
  SyncEntityType,
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
  periodId?: string | undefined;
}

export interface ExpenseSnapshot {
  id: string;
  amountMinor: number;
  category: ExpenseCategory;
  payer: MemberKey;
  occurredAt: string;
  note: string | null;
  periodId: string;
  version: number;
  updatedAt: string;
  deletedAt: string | null;
}

export interface PeriodInput {
  sequenceNumber: number;
  startedAt: Date;
  closedAt: Date | null;
  note: string | null;
}

export interface PeriodSnapshot {
  id: string;
  sequenceNumber: number;
  startedAt: string;
  closedAt: string | null;
  note: string | null;
  version: number;
  updatedAt: string;
}

export interface LoanInput {
  debtor: MemberKey;
  amountMinor: number;
  occurredAt: Date;
  note: string | null;
}

export interface LoanSnapshot {
  id: string;
  debtor: MemberKey;
  amountMinor: number;
  occurredAt: string;
  note: string | null;
  version: number;
  updatedAt: string;
  deletedAt: string | null;
}

export interface MutationBase {
  mutationId: string;
  entityId: string;
  entityType?: SyncEntityType | undefined;
  operation: MutationOperation;
  baseVersion: number;
  expense?: unknown;
  period?: unknown;
  loan?: unknown;
}

interface MutationIdentity {
  mutationId: string;
  entityId: string;
}

export type ParsedMutation = MutationIdentity &
  (
    | {
        entityType: 'EXPENSE';
        operation: 'CREATE';
        baseVersion: 0;
        expense: ExpenseInput;
      }
    | {
        entityType: 'EXPENSE';
        operation: 'UPDATE';
        baseVersion: number;
        expense: ExpenseInput;
      }
    | { entityType: 'EXPENSE'; operation: 'DELETE'; baseVersion: number }
    | {
        entityType: 'PERIOD';
        operation: 'CREATE';
        baseVersion: 0;
        period: PeriodInput;
      }
    | {
        entityType: 'PERIOD';
        operation: 'UPDATE';
        baseVersion: number;
        period: PeriodInput;
      }
    | {
        entityType: 'LOAN';
        operation: 'CREATE';
        baseVersion: 0;
        loan: LoanInput;
      }
    | {
        entityType: 'LOAN';
        operation: 'UPDATE';
        baseVersion: number;
        loan: LoanInput;
      }
    | { entityType: 'LOAN'; operation: 'DELETE'; baseVersion: number }
  );

/** One synchronized entity, tagged so a reader knows which key to read. */
export type EntityPayload =
  | { entityType: 'EXPENSE'; expense: ExpenseSnapshot }
  | { entityType: 'PERIOD'; period: PeriodSnapshot }
  | { entityType: 'LOAN'; loan: LoanSnapshot };

export type MutationResult =
  | ({ mutationId: string; status: 'APPLIED' } & EntityPayload)
  | ({
      mutationId: string;
      status: 'CONFLICT';
      code: 'ENTITY_EXISTS' | 'VERSION_CONFLICT';
    } & EntityPayload)
  | {
      mutationId: string;
      status: 'REJECTED';
      code:
        | 'ENTITY_ID_UNAVAILABLE'
        | 'ENTITY_NOT_FOUND'
        | 'IDEMPOTENCY_KEY_REUSED'
        | 'INVALID_MUTATION'
        | 'PAYER_NOT_FOUND'
        | 'PERIOD_ALREADY_OPEN'
        | 'PERIOD_NOT_FOUND';
      details?: ValidationIssue[] | undefined;
    };

export interface ValidationIssue {
  path: string;
  code: string;
  message: string;
}
