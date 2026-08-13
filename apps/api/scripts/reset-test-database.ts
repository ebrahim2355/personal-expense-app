import { PrismaPg } from '@prisma/adapter-pg';

import { PrismaClient } from '../src/generated/prisma/client.js';

function assertDedicatedTestDatabase(rawUrl: string): URL {
  const url = new URL(rawUrl);
  const databaseName = decodeURIComponent(url.pathname.replace(/^\//, ''));
  if (!/(?:^|[-_])test$/i.test(databaseName)) {
    throw new Error(
      'Refusing cleanup: database name must end in "-test" or "_test".',
    );
  }
  return url;
}

async function main(): Promise<void> {
  if (process.env.NODE_ENV !== 'test') {
    throw new Error('Refusing cleanup unless NODE_ENV=test.');
  }
  const testDatabaseUrl = process.env.TEST_DATABASE_URL;
  if (testDatabaseUrl === undefined || testDatabaseUrl.length === 0) {
    throw new Error('TEST_DATABASE_URL is required.');
  }
  if (process.env.DATABASE_URL !== testDatabaseUrl) {
    throw new Error(
      'DATABASE_URL must exactly match TEST_DATABASE_URL during cleanup.',
    );
  }

  const url = assertDedicatedTestDatabase(testDatabaseUrl);
  const adapter = new PrismaPg({ connectionString: testDatabaseUrl });
  const prisma = new PrismaClient({ adapter });
  try {
    await prisma.$executeRaw`TRUNCATE TABLE "ProcessedMutation", "ExpenseChange", "Expense", "RefreshToken", "Member", "Household" RESTART IDENTITY CASCADE`;
    process.stdout.write(
      `Dedicated test database ${decodeURIComponent(url.pathname.slice(1))} reset.\n`,
    );
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((_error: unknown) => {
  process.stderr.write(
    'Test database reset refused or failed. Check the dedicated test configuration.\n',
  );
  process.exitCode = 1;
});
