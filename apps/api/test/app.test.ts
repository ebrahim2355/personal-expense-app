import request from 'supertest';
import { describe, expect, it } from 'vitest';

import type { AuthService } from '../src/application/auth-service.js';
import type { SyncService } from '../src/application/sync-service.js';
import { createApp } from '../src/app.js';
import type { AppConfig } from '../src/config/env.js';
import { createLogger } from '../src/infrastructure/logger.js';
import type { DatabaseClient } from '../src/infrastructure/prisma.js';

const config: AppConfig = {
  nodeEnv: 'test',
  port: 3000,
  databaseUrl: 'postgresql://unused:unused@localhost:5432/unused',
  jwtAccessSecret: 'a'.repeat(32),
  cursorSigningSecret: 'b'.repeat(32),
  jwtIssuer: 'test-issuer',
  jwtAudience: 'test-audience',
  accessTokenTtlSeconds: 600,
  refreshTokenTtlDays: 30,
  pinPepper: '',
  corsAllowedOrigins: new Set<string>(),
  trustProxyHops: 0,
  jsonBodyLimit: '64kb',
  rateLimitMax: 1000,
  authRateLimitMax: 1000,
  rateLimitWindowMs: 60_000,
  databasePoolMax: 1,
  databaseConnectionTimeoutMs: 100,
  logLevel: 'silent',
};

describe('GET /health/live', () => {
  it('returns process liveness without requiring the database', async () => {
    const app = createApp({
      config,
      prisma: {} as DatabaseClient,
      authService: {} as AuthService,
      syncService: {} as SyncService,
      logger: createLogger(config),
    });
    const response = await request(app).get('/health/live');

    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toMatch(/^application\/json/);
    expect(response.headers['x-powered-by']).toBeUndefined();
    expect(response.headers['x-request-id']).toBeTypeOf('string');
    expect(response.body).toEqual({ status: 'ok', checks: { process: 'up' } });
  });
});
