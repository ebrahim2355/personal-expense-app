import { randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';

import type { NextFunction, Request, RequestHandler, Response } from 'express';

import type { AuthService } from '../application/auth-service.js';
import { AppError } from '../domain/errors.js';
import type { AuthenticatedMember } from '../domain/models.js';
import type { AppLogger } from '../infrastructure/logger.js';

export interface RequestLocals {
  requestId: string;
  auth?: AuthenticatedMember;
}

const acceptedRequestId = /^[A-Za-z0-9._-]{1,100}$/;

export function requestContext(logger: AppLogger): RequestHandler {
  return (request, response, next) => {
    const supplied = request.header('x-request-id');
    const requestId =
      supplied !== undefined && acceptedRequestId.test(supplied)
        ? supplied
        : randomUUID();
    const startedAt = performance.now();

    response.locals.requestId = requestId;
    response.setHeader('x-request-id', requestId);
    response.on('finish', () => {
      logger.info(
        {
          requestId,
          method: request.method,
          path: request.path,
          statusCode: response.statusCode,
          durationMs: Math.round((performance.now() - startedAt) * 100) / 100,
        },
        'request completed',
      );
    });

    next();
  };
}

export function requireAuthentication(
  authService: AuthService,
): RequestHandler {
  return async (request, response, next) => {
    try {
      const authorization = request.header('authorization');
      if (!authorization?.startsWith('Bearer ')) {
        throw new AppError(401, 'UNAUTHORIZED', 'Authentication is required.');
      }

      const rawToken = authorization.slice('Bearer '.length).trim();
      if (rawToken.length === 0 || rawToken.includes(' ')) {
        throw new AppError(401, 'UNAUTHORIZED', 'Authentication is required.');
      }

      response.locals.auth =
        await authService.authenticateAccessToken(rawToken);
      next();
    } catch (error) {
      next(error);
    }
  };
}

export function authenticatedMember(response: Response): AuthenticatedMember {
  const identity: unknown = response.locals.auth;
  if (
    typeof identity !== 'object' ||
    identity === null ||
    !('memberId' in identity) ||
    !('householdId' in identity) ||
    !('memberKey' in identity)
  ) {
    throw new AppError(401, 'UNAUTHORIZED', 'Authentication is required.');
  }

  return identity as AuthenticatedMember;
}

export function unknownBody(request: Request): unknown {
  return request.body as unknown;
}

export function asyncHandler(
  handler: (request: Request, response: Response) => Promise<void>,
): RequestHandler {
  return (request: Request, response: Response, next: NextFunction) => {
    void handler(request, response).catch(next);
  };
}
