import type { ZodError } from 'zod';

import type { ValidationIssue } from './models.js';

export class AppError extends Error {
  public constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
    public readonly details?: ValidationIssue[],
  ) {
    super(message);
    this.name = 'AppError';
  }
}

export function validationIssues(error: ZodError): ValidationIssue[] {
  return error.issues.map((issue) => ({
    path: issue.path.join('.'),
    code: issue.code,
    message: issue.message,
  }));
}

export function validationError(error: ZodError): AppError {
  return new AppError(
    422,
    'VALIDATION_ERROR',
    'The request did not pass validation.',
    validationIssues(error),
  );
}
