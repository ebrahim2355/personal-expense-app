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
        // An FCM registration token is enough to send a device a notification,
        // so it is redacted alongside the credentials even though it grants no
        // authority over the account. The send path never logs one deliberately;
        // this is the guard against a future log line that forgets.
        'token',
        '*.token',
        'privateKey',
        '*.privateKey',
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
