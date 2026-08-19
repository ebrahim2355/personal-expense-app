import { z } from 'zod';

const rawEnvironmentSchema = z.object({
  NODE_ENV: z
    .enum(['development', 'test', 'production'])
    .default('development'),
  PORT: z.coerce.number().int().min(1).max(65_535).default(3000),
  DATABASE_URL: z.string().min(1),
  JWT_ACCESS_SECRET: z.string().min(32),
  CURSOR_SIGNING_SECRET: z.string().min(32),
  JWT_ISSUER: z.string().min(1).default('household-expenses-api'),
  JWT_AUDIENCE: z.string().min(1).default('household-expenses-mobile'),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce
    .number()
    .int()
    .min(60)
    .max(3600)
    .default(600),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).max(90).default(30),
  PIN_PEPPER: z.string().default(''),
  CORS_ALLOWED_ORIGINS: z.string().default(''),
  TRUST_PROXY_HOPS: z.coerce.number().int().min(0).max(5).default(0),
  JSON_BODY_LIMIT: z
    .string()
    .regex(/^\d+(kb|mb)$/i)
    .default('64kb'),
  RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(300),
  AUTH_RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(10),
  RATE_LIMIT_WINDOW_MS: z.coerce.number().int().min(1000).default(60_000),
  DATABASE_POOL_MAX: z.coerce.number().int().min(1).max(50).default(10),
  DATABASE_CONNECTION_TIMEOUT_MS: z.coerce
    .number()
    .int()
    .min(100)
    .max(60_000)
    .default(5000),
  LOG_LEVEL: z
    .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent'])
    .default('info'),
  // Optional on purpose: with no credential the API starts, serves every route,
  // and simply never sends a push, which is exactly the behaviour that shipped
  // before push existed. Base64 rather than raw JSON because the private key
  // contains newlines, and a dashboard text field mangles those.
  FIREBASE_SERVICE_ACCOUNT_BASE64: z.string().optional(),
});

/// The three fields `firebase-admin` needs to authenticate as our project. Held
/// as a parsed object rather than the raw JSON so a malformed credential fails
/// at startup, where it is one clear log line, instead of at the first send,
/// where it would be a silent notification that never arrived.
export interface FirebaseServiceAccount {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

const serviceAccountSchema = z.object({
  project_id: z.string().min(1),
  client_email: z.string().min(1),
  private_key: z.string().min(1),
});

function parseServiceAccount(encoded: string): FirebaseServiceAccount {
  // `Buffer.from(…, 'base64')` never throws — it drops characters outside the
  // alphabet — so malformed base64 surfaces here as unparseable JSON rather
  // than as a decode error. One message covers both, because from the operator's
  // side they are the same mistake: the value pasted was not the encoded file.
  let document: unknown;
  try {
    document = JSON.parse(
      Buffer.from(encoded, 'base64').toString('utf8'),
    ) as unknown;
  } catch {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT_BASE64 must be base64-encoded service account JSON.',
    );
  }

  const parsed = serviceAccountSchema.safeParse(document);
  if (!parsed.success) {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT_BASE64 must contain project_id, client_email, and private_key.',
    );
  }

  return {
    projectId: parsed.data.project_id,
    clientEmail: parsed.data.client_email,
    privateKey: parsed.data.private_key,
  };
}

export interface AppConfig {
  nodeEnv: 'development' | 'test' | 'production';
  port: number;
  databaseUrl: string;
  jwtAccessSecret: string;
  cursorSigningSecret: string;
  jwtIssuer: string;
  jwtAudience: string;
  accessTokenTtlSeconds: number;
  refreshTokenTtlDays: number;
  pinPepper: string;
  corsAllowedOrigins: ReadonlySet<string>;
  trustProxyHops: number;
  jsonBodyLimit: string;
  rateLimitMax: number;
  authRateLimitMax: number;
  rateLimitWindowMs: number;
  databasePoolMax: number;
  databaseConnectionTimeoutMs: number;
  logLevel: string;
  /// Null when no credential is configured, which disables push and leaves the
  /// client on background polling alone.
  firebaseServiceAccount: FirebaseServiceAccount | null;
}

export function loadConfig(
  environment: NodeJS.ProcessEnv = process.env,
): AppConfig {
  const parsed = rawEnvironmentSchema.parse(environment);

  let databaseUrl: URL;
  try {
    databaseUrl = new URL(parsed.DATABASE_URL);
  } catch {
    throw new Error('DATABASE_URL must be a valid PostgreSQL URL.');
  }
  if (!['postgres:', 'postgresql:'].includes(databaseUrl.protocol)) {
    throw new Error(
      'DATABASE_URL must use the postgres or postgresql protocol.',
    );
  }

  if (parsed.JWT_ACCESS_SECRET === parsed.CURSOR_SIGNING_SECRET) {
    throw new Error(
      'JWT_ACCESS_SECRET and CURSOR_SIGNING_SECRET must be independent values.',
    );
  }

  const origins = parsed.CORS_ALLOWED_ORIGINS.split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);

  if (parsed.NODE_ENV === 'production' && parsed.TRUST_PROXY_HOPS === 0) {
    throw new Error('TRUST_PROXY_HOPS must be configured in production.');
  }

  for (const origin of origins) {
    const url = new URL(origin);
    if (
      url.origin !== origin ||
      (parsed.NODE_ENV === 'production' && url.protocol !== 'https:')
    ) {
      throw new Error(`Invalid CORS origin: ${origin}`);
    }
  }

  return {
    nodeEnv: parsed.NODE_ENV,
    port: parsed.PORT,
    databaseUrl: parsed.DATABASE_URL,
    jwtAccessSecret: parsed.JWT_ACCESS_SECRET,
    cursorSigningSecret: parsed.CURSOR_SIGNING_SECRET,
    jwtIssuer: parsed.JWT_ISSUER,
    jwtAudience: parsed.JWT_AUDIENCE,
    accessTokenTtlSeconds: parsed.ACCESS_TOKEN_TTL_SECONDS,
    refreshTokenTtlDays: parsed.REFRESH_TOKEN_TTL_DAYS,
    pinPepper: parsed.PIN_PEPPER,
    corsAllowedOrigins: new Set(origins),
    trustProxyHops: parsed.TRUST_PROXY_HOPS,
    jsonBodyLimit: parsed.JSON_BODY_LIMIT,
    rateLimitMax: parsed.RATE_LIMIT_MAX,
    authRateLimitMax: parsed.AUTH_RATE_LIMIT_MAX,
    rateLimitWindowMs: parsed.RATE_LIMIT_WINDOW_MS,
    databasePoolMax: parsed.DATABASE_POOL_MAX,
    databaseConnectionTimeoutMs: parsed.DATABASE_CONNECTION_TIMEOUT_MS,
    logLevel: parsed.LOG_LEVEL,
    firebaseServiceAccount:
      parsed.FIREBASE_SERVICE_ACCOUNT_BASE64 === undefined ||
      parsed.FIREBASE_SERVICE_ACCOUNT_BASE64.trim().length === 0
        ? null
        : parseServiceAccount(parsed.FIREBASE_SERVICE_ACCOUNT_BASE64.trim()),
  };
}
