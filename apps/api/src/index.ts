import 'dotenv/config';

import { createServer } from 'node:http';

import { AuthService } from './application/auth-service.js';
import {
  disabledActivityNotifier,
  PushActivityNotifier,
} from './application/push-notifier.js';
import { SyncService } from './application/sync-service.js';
import { createApp } from './app.js';
import { loadConfig } from './config/env.js';
import { createLogger } from './infrastructure/logger.js';
import { createPrismaClient } from './infrastructure/prisma.js';
import { createPushSender } from './infrastructure/push-sender.js';
import { TokenService } from './infrastructure/token-service.js';

const config = loadConfig();
const logger = createLogger(config);
const prisma = createPrismaClient(config);
const tokenService = new TokenService(config);
const authService = new AuthService(prisma, tokenService, config);

// Announced once at startup rather than per mutation. Without a credential the
// API is fully functional and simply never wakes a phone, so the only way to
// tell that state from a broken send is to say so here.
const pushSender = createPushSender(config.firebaseServiceAccount);
if (pushSender === null) {
  logger.warn(
    'push disabled: FIREBASE_SERVICE_ACCOUNT_BASE64 is not configured, clients rely on background polling',
  );
} else {
  logger.info(
    { projectId: config.firebaseServiceAccount?.projectId },
    'push enabled',
  );
}

const activityNotifier =
  pushSender === null
    ? disabledActivityNotifier
    : new PushActivityNotifier(prisma, pushSender, logger);
const syncService = new SyncService(prisma, tokenService, activityNotifier);
const app = createApp({ config, prisma, authService, syncService, logger });
const server = createServer(app);
let shuttingDown = false;

async function shutdown(signal: string): Promise<void> {
  if (shuttingDown) {
    return;
  }
  shuttingDown = true;
  logger.info({ signal }, 'shutdown started');

  const forceTimer = setTimeout(() => {
    logger.fatal('graceful shutdown timed out');
    process.exit(1);
  }, 10_000);
  forceTimer.unref();

  try {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => {
        if (error === undefined) {
          resolve();
        } else {
          reject(error);
        }
      });
    });
    await prisma.$disconnect();
    clearTimeout(forceTimer);
    logger.info('shutdown complete');
  } catch (error) {
    clearTimeout(forceTimer);
    logger.error({ err: error }, 'graceful shutdown failed');
    process.exitCode = 1;
  }
}

process.on('SIGINT', () => {
  void shutdown('SIGINT');
});
process.on('SIGTERM', () => {
  void shutdown('SIGTERM');
});

server.on('error', (error) => {
  logger.fatal({ err: error }, 'HTTP server failed');
  process.exitCode = 1;
});

server.listen(config.port, () => {
  logger.info(
    { port: config.port, environment: config.nodeEnv },
    'API listening',
  );
});
