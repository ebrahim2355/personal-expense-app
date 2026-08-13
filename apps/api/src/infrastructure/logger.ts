import pino, { type Logger } from 'pino';

import type { AppConfig } from '../config/env.js';

export type AppLogger = Logger;

export function createLogger(config: AppConfig): AppLogger {
  return pino({
    level: config.logLevel,
    base: null,
    redact: {
      paths: [
        'authorization',
        'headers.authorization',
        'req.headers.authorization',
        'pin',
        '*.pin',
        'accessToken',
        '*.accessToken',
        'refreshToken',
        '*.refreshToken',
        'tokenHash',
        '*.tokenHash',
        'pinHash',
        '*.pinHash',
        'databaseUrl',
      ],
      censor: '[REDACTED]',
    },
  });
}
