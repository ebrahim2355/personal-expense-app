import { PrismaPg } from '@prisma/adapter-pg';

import type { AppConfig } from '../config/env.js';
import { PrismaClient } from '../generated/prisma/client.js';

export function createPrismaClient(config: AppConfig): PrismaClient {
  const adapter = new PrismaPg({
    connectionString: config.databaseUrl,
    max: config.databasePoolMax,
    connectionTimeoutMillis: config.databaseConnectionTimeoutMs,
  });

  return new PrismaClient({ adapter });
}

export type DatabaseClient = PrismaClient;
