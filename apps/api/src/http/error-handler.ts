import type { ErrorRequestHandler, RequestHandler } from 'express';
import { ZodError } from 'zod';

import { AppError, validationError } from '../domain/errors.js';
import type { AppLogger } from '../infrastructure/logger.js';

function hasErrorType(error: unknown, type: string): boolean {
  return (
    error instanceof Error &&
    'type' in error &&
    typeof error.type === 'string' &&
    error.type === type
  );
}

export function notFoundHandler(): RequestHandler {
  return (_request, _response, next) => {
    next(
      new AppError(404, 'NOT_FOUND', 'The requested endpoint does not exist.'),
    );
  };
}

export function errorHandler(logger: AppLogger): ErrorRequestHandler {
  return (error: unknown, _request, response, _next) => {
    const requestId =
      typeof response.locals.requestId === 'string'
        ? response.locals.requestId
        : 'unknown';

    let appError: AppError;
    if (error instanceof AppError) {
      appError = error;
    } else if (error instanceof ZodError) {
      appError = validationError(error);
    } else if (hasErrorType(error, 'entity.parse.failed')) {
      appError = new AppError(
        400,
        'INVALID_JSON',
        'The request body is not valid JSON.',
      );
    } else if (hasErrorType(error, 'entity.too.large')) {
      appError = new AppError(
        413,
        'BODY_TOO_LARGE',
        'The request body is too large.',
      );
    } else {
      // Arbitrary driver/library errors can include query values or connection
      // details. Keep enough structured context to correlate the incident while
      // never returning or logging the exception message/stack.
      logger.error(
        {
          requestId,
          errorType: error instanceof Error ? error.name : typeof error,
        },
        'unhandled request error',
      );
      appError = new AppError(
        500,
        'INTERNAL_ERROR',
        'An unexpected error occurred.',
      );
    }

    response.status(appError.statusCode).json({
      error: {
        code: appError.code,
        message: appError.message,
        requestId,
        ...(appError.details === undefined
          ? {}
          : { details: appError.details }),
      },
    });
  };
}
