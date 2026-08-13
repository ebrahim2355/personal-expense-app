import 'dotenv/config';

import * as argon2 from 'argon2';
import { PrismaPg } from '@prisma/adapter-pg';
import { z } from 'zod';

import { PrismaClient } from '../src/generated/prisma/client.js';

const environmentSchema = z.object({
  DATABASE_URL: z.string().min(1),
  HOUSEHOLD_SLUG: z
    .string()
    .regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    .max(64)
    .default('sumon-ebrahim'),
  HOUSEHOLD_NAME: z
    .string()
    .trim()
    .min(1)
    .max(100)
    .default('Sumon and Ebrahim'),
  SUMON_INITIAL_PIN: z.string().regex(/^\d{6,12}$/),
  EBRAHIM_INITIAL_PIN: z.string().regex(/^\d{6,12}$/),
  PIN_PEPPER: z.string().default(''),
});

const passwordOptions: argon2.HashOptions = {
  type: argon2.argon2id,
  memoryCost: 19_456,
  timeCost: 2,
  parallelism: 1,
};

async function main(): Promise<void> {
  const environment = environmentSchema.parse(process.env);
  const adapter = new PrismaPg({ connectionString: environment.DATABASE_URL });
  const prisma = new PrismaClient({ adapter });

  try {
    const [sumonHash, ebrahimHash] = await Promise.all([
      argon2.hash(
        `${environment.SUMON_INITIAL_PIN}${environment.PIN_PEPPER}`,
        passwordOptions,
      ),
      argon2.hash(
        `${environment.EBRAHIM_INITIAL_PIN}${environment.PIN_PEPPER}`,
        passwordOptions,
      ),
    ]);

    await prisma.$transaction(async (transaction) => {
      const household = await transaction.household.upsert({
        where: { slug: environment.HOUSEHOLD_SLUG },
        create: {
          slug: environment.HOUSEHOLD_SLUG,
          name: environment.HOUSEHOLD_NAME,
        },
        update: { name: environment.HOUSEHOLD_NAME },
      });

      await transaction.member.upsert({
        where: {
          householdId_key: { householdId: household.id, key: 'SUMON' },
        },
        create: {
          householdId: household.id,
          key: 'SUMON',
          displayName: 'Sumon',
          pinHash: sumonHash,
        },
        update: {
          displayName: 'Sumon',
          pinHash: sumonHash,
          disabledAt: null,
          updatedAt: new Date(),
        },
      });

      await transaction.member.upsert({
        where: {
          householdId_key: { householdId: household.id, key: 'EBRAHIM' },
        },
        create: {
          householdId: household.id,
          key: 'EBRAHIM',
          displayName: 'Ebrahim',
          pinHash: ebrahimHash,
        },
        update: {
          displayName: 'Ebrahim',
          pinHash: ebrahimHash,
          disabledAt: null,
          updatedAt: new Date(),
        },
      });
    });

    process.stdout.write('Household members provisioned successfully.\n');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((_error: unknown) => {
  process.stderr.write(
    'Member provisioning failed. Check configuration and database readiness.\n',
  );
  process.exitCode = 1;
});
