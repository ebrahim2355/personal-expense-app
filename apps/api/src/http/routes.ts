import { Router, type RequestHandler } from 'express';
import { rateLimit } from 'express-rate-limit';

import type { AuthService } from '../application/auth-service.js';
import type { SyncService } from '../application/sync-service.js';
import type { AppConfig } from '../config/env.js';
import { AppError } from '../domain/errors.js';
import {
  bootstrapQuerySchema,
  changesQuerySchema,
  loginSchema,
  logoutSchema,
  mutationEnvelopeSchema,
  refreshSchema,
} from '../domain/validation.js';
import type { AppLogger } from '../infrastructure/logger.js';
import type { DatabaseClient } from '../infrastructure/prisma.js';
import {
  asyncHandler,
  authenticatedMember,
  requireAuthentication,
  unknownBody,
} from './request-context.js';

interface RouteDependencies {
  config: AppConfig;
  prisma: DatabaseClient;
  authService: AuthService;
  syncService: SyncService;
  logger: AppLogger;
}

function limiter(
  config: AppConfig,
  maximum: number,
  code: string,
): RequestHandler {
  return rateLimit({
    windowMs: config.rateLimitWindowMs,
    limit: maximum,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    handler: (_request, _response, next) => {
      next(
        new AppError(429, code, 'Too many requests. Please try again later.'),
      );
    },
  });
}

async function databaseIsReady(prisma: DatabaseClient): Promise<boolean> {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return true;
  } catch {
    return false;
  }
}

export function createRouter(dependencies: RouteDependencies): Router {
  const router = Router();
  const authRequired = requireAuthentication(dependencies.authService);
  const authLimiter = limiter(
    dependencies.config,
    dependencies.config.authRateLimitMax,
    'AUTH_RATE_LIMITED',
  );

  router.get('/health/live', (_request, response) => {
    response.status(200).json({ status: 'ok', checks: { process: 'up' } });
  });

  router.get(
    '/health/ready',
    asyncHandler(async (_request, response) => {
      const ready = await databaseIsReady(dependencies.prisma);
      response.status(ready ? 200 : 503).json({
        status: ready ? 'ready' : 'not_ready',
        checks: { database: ready ? 'up' : 'down' },
      });
    }),
  );

  router.get(
    '/health',
    asyncHandler(async (_request, response) => {
      const ready = await databaseIsReady(dependencies.prisma);
      response.status(ready ? 200 : 503).json({
        status: ready ? 'ready' : 'not_ready',
        checks: {
          process: 'up',
          database: ready ? 'up' : 'down',
        },
      });
    }),
  );

  router.post(
    '/v1/auth/login',
    authLimiter,
    asyncHandler(async (request, response) => {
      const input = loginSchema.parse(unknownBody(request));
      const result = await dependencies.authService.login(
        input.member,
        input.pin,
      );
      response.status(200).json(result);
    }),
  );

  router.post(
    '/v1/auth/refresh',
    authLimiter,
    asyncHandler(async (request, response) => {
      const input = refreshSchema.parse(unknownBody(request));
      const result = await dependencies.authService.refresh(input.refreshToken);
      response.status(200).json(result);
    }),
  );

  router.post(
    '/v1/auth/logout',
    authRequired,
    asyncHandler(async (request, response) => {
      const input = logoutSchema.parse(unknownBody(request));
      await dependencies.authService.logout(
        authenticatedMember(response),
        input.refreshToken,
      );
      response.status(204).send();
    }),
  );

  router.get(
    '/v1/auth/me',
    authRequired,
    asyncHandler(async (_request, response) => {
      const member = await dependencies.authService.currentMember(
        authenticatedMember(response),
      );
      response.status(200).json({ member });
    }),
  );

  router.post(
    '/v1/sync/mutations',
    authRequired,
    asyncHandler(async (request, response) => {
      const input = mutationEnvelopeSchema.parse(unknownBody(request));
      const identity = authenticatedMember(response);
      const results = await dependencies.syncService.applyMutations(
        identity,
        input.mutations,
      );
      dependencies.logger.info(
        {
          requestId: response.locals.requestId as string,
          memberKey: identity.memberKey,
          mutationIds: input.mutations.map((mutation) => mutation.mutationId),
          resultStatuses: results.map((result) => result.status),
        },
        'sync mutation batch processed',
      );
      response.status(200).json({ results });
    }),
  );

  router.get(
    '/v1/sync/changes',
    authRequired,
    asyncHandler(async (request, response) => {
      const query = changesQuerySchema.parse(request.query);
      const identity = authenticatedMember(response);
      const page = await dependencies.syncService.getChanges(
        identity,
        query.cursor,
        query.limit,
      );
      dependencies.logger.debug(
        {
          requestId: response.locals.requestId as string,
          memberKey: identity.memberKey,
          cursorSupplied: query.cursor !== undefined,
          changeCount: page.changes.length,
          hasMore: page.hasMore,
        },
        'sync change page served',
      );
      response.status(200).json(page);
    }),
  );

  router.get(
    '/v1/sync/bootstrap',
    authRequired,
    asyncHandler(async (request, response) => {
      const query = bootstrapQuerySchema.parse(request.query);
      const identity = authenticatedMember(response);
      const page = await dependencies.syncService.bootstrap(
        identity,
        query.pageToken,
        query.limit,
      );
      dependencies.logger.debug(
        {
          requestId: response.locals.requestId as string,
          memberKey: identity.memberKey,
          pageTokenSupplied: query.pageToken !== undefined,
          itemCount: page.items.length,
          hasMore: page.hasMore,
        },
        'sync bootstrap page served',
      );
      response.status(200).json(page);
    }),
  );

  return router;
}

export function createGlobalRateLimiter(config: AppConfig): RequestHandler {
  return limiter(config, config.rateLimitMax, 'RATE_LIMITED');
}
