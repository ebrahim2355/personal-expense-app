import cors from 'cors';
import express, { type Express, type RequestHandler } from 'express';
import helmet from 'helmet';

import type { AuthService } from './application/auth-service.js';
import type { SyncService } from './application/sync-service.js';
import type { AppConfig } from './config/env.js';
import { AppError } from './domain/errors.js';
import { errorHandler, notFoundHandler } from './http/error-handler.js';
import { requestContext } from './http/request-context.js';
import { createGlobalRateLimiter, createRouter } from './http/routes.js';
import type { AppLogger } from './infrastructure/logger.js';
import type { DatabaseClient } from './infrastructure/prisma.js';

export interface AppDependencies {
  config: AppConfig;
  prisma: DatabaseClient;
  authService: AuthService;
  syncService: SyncService;
  logger: AppLogger;
}

function requireHttps(config: AppConfig): RequestHandler {
  return (request, _response, next) => {
    if (config.nodeEnv === 'production' && !request.secure) {
      next(new AppError(400, 'HTTPS_REQUIRED', 'HTTPS is required.'));
      return;
    }

    next();
  };
}

export function createApp(dependencies: AppDependencies): Express {
  const { config, logger } = dependencies;
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxyHops);
  app.use(requestContext(logger));
  app.use(helmet());
  app.use(requireHttps(config));
  app.use(
    cors({
      credentials: false,
      origin(origin, callback) {
        // Native Android requests normally have no Origin header.
        if (origin === undefined || config.corsAllowedOrigins.has(origin)) {
          callback(null, true);
          return;
        }

        callback(
          new AppError(
            403,
            'ORIGIN_NOT_ALLOWED',
            'The request origin is not allowed.',
          ),
        );
      },
    }),
  );
  app.use(express.json({ limit: config.jsonBodyLimit, strict: true }));
  app.use(createGlobalRateLimiter(config));
  app.use(createRouter(dependencies));
  app.use(notFoundHandler());
  app.use(errorHandler(logger));

  return app;
}
