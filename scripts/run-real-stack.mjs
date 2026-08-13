import { randomBytes, randomInt } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const mobileRoot = path.join(root, "apps", "mobile");
const apiPort = 3100;
const apiBaseUrl = `http://127.0.0.1:${apiPort}`;
const databaseUrl =
  "postgresql://expenses_test:expenses_test@127.0.0.1:55432/" +
  "expenses_e2e_test?schema=public";
const node = process.execPath;
const npm = process.platform === "win32" ? node : "npm";
const npmPrefixArgs =
  process.platform === "win32"
    ? [
        process.env.npm_execpath ??
          path.join(
            path.dirname(node),
            "node_modules",
            "npm",
            "bin",
            "npm-cli.js",
          ),
      ]
    : [];
const flutter =
  process.platform === "win32" ? (process.env.ComSpec ?? "cmd.exe") : "flutter";
const flutterPrefixArgs =
  process.platform === "win32" ? ["/d", "/s", "/c", "flutter.bat"] : [];
const keepPostgres = process.argv.includes("--keep-postgres");

const stackEnv = {
  ...process.env,
  NODE_ENV: "test",
  PORT: String(apiPort),
  DATABASE_URL: databaseUrl,
  TEST_DATABASE_URL: databaseUrl,
  JWT_ACCESS_SECRET: randomBytes(32).toString("base64url"),
  CURSOR_SIGNING_SECRET: randomBytes(32).toString("base64url"),
  JWT_ISSUER: "household-expenses-e2e",
  JWT_AUDIENCE: "household-expenses-mobile-e2e",
  ACCESS_TOKEN_TTL_SECONDS: "60",
  REFRESH_TOKEN_TTL_DAYS: "1",
  PIN_PEPPER: randomBytes(16).toString("base64url"),
  CORS_ALLOWED_ORIGINS: "",
  TRUST_PROXY_HOPS: "0",
  JSON_BODY_LIMIT: "64kb",
  RATE_LIMIT_MAX: "10000",
  AUTH_RATE_LIMIT_MAX: "10000",
  RATE_LIMIT_WINDOW_MS: "60000",
  DATABASE_POOL_MAX: "10",
  DATABASE_CONNECTION_TIMEOUT_MS: "5000",
  LOG_LEVEL: "info",
  HOUSEHOLD_SLUG: "sumon-ebrahim-e2e",
  HOUSEHOLD_NAME: "Sumon and Ebrahim E2E",
  SUMON_INITIAL_PIN: String(randomInt(1_000_000, 9_999_999)),
  EBRAHIM_INITIAL_PIN: String(randomInt(1_000_000, 9_999_999)),
};

function run(command, args, options = {}) {
  const launchArgs =
    command === npm
      ? [...npmPrefixArgs, ...args]
      : command === flutter
        ? [...flutterPrefixArgs, ...args]
        : args;
  const printableArgs = launchArgs.map((argument) =>
    argument.startsWith("--dart-define=REAL_STACK_SUMON_PIN=") ||
    argument.startsWith("--dart-define=REAL_STACK_EBRAHIM_PIN=")
      ? `${argument.split("=", 1)[0]}=<redacted>`
      : argument,
  );
  process.stdout.write(`> ${command} ${printableArgs.join(" ")}\n`);
  const result = spawnSync(command, launchArgs, {
    cwd: root,
    env: stackEnv,
    stdio: "inherit",
    windowsHide: true,
    ...options,
  });
  if (result.error !== undefined) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`${command} exited with status ${result.status}.`);
  }
}

async function waitForReady(server) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    if (server.exitCode !== null) {
      throw new Error(`API exited before readiness with ${server.exitCode}.`);
    }
    try {
      const response = await fetch(`${apiBaseUrl}/health/ready`);
      if (response.status === 200) {
        return;
      }
    } catch {
      // Readiness is authoritative; keep polling until the bounded deadline.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("API readiness deadline expired.");
}

async function stopServer(server) {
  if (server.exitCode !== null) {
    return;
  }
  const exitPromise = once(server, "exit");
  server.kill("SIGTERM");
  let timeoutId;
  await Promise.race([
    exitPromise,
    new Promise((resolve) => {
      timeoutId = setTimeout(resolve, 10_000);
    }),
  ]);
  if (timeoutId !== undefined) {
    clearTimeout(timeoutId);
  }
  if (server.exitCode === null) {
    server.kill("SIGKILL");
    await exitPromise;
  }
}

let apiServer;
let postgresStarted = false;
let completed = false;
try {
  run("docker", [
    "compose",
    "-f",
    "compose.test.yaml",
    "up",
    "-d",
    "--wait",
    "postgres-test",
  ]);
  postgresStarted = true;
  run(npm, ["run", "prisma:generate", "--workspace", "@expenses/api"]);
  run(npm, ["run", "prisma:migrate:deploy", "--workspace", "@expenses/api"]);
  run(npm, ["run", "test:reset", "--workspace", "@expenses/api"]);
  run(npm, ["run", "members:provision", "--workspace", "@expenses/api"]);
  run(npm, ["run", "build", "--workspace", "@expenses/api"]);

  apiServer = spawn(node, ["apps/api/dist/index.js"], {
    cwd: root,
    env: stackEnv,
    stdio: ["ignore", "inherit", "inherit"],
    windowsHide: true,
  });
  await waitForReady(apiServer);

  run(
    flutter,
    [
      "test",
      "test/real_stack_sync_test.dart",
      `--dart-define=REAL_STACK_API_BASE_URL=${apiBaseUrl}`,
      `--dart-define=REAL_STACK_SUMON_PIN=${stackEnv.SUMON_INITIAL_PIN}`,
      `--dart-define=REAL_STACK_EBRAHIM_PIN=${stackEnv.EBRAHIM_INITIAL_PIN}`,
    ],
    { cwd: mobileRoot },
  );
  completed = true;
} finally {
  if (apiServer !== undefined) {
    await stopServer(apiServer);
  }
  if (postgresStarted) {
    try {
      run(npm, ["run", "test:reset", "--workspace", "@expenses/api"]);
    } catch (error) {
      process.stderr.write(`Post-test cleanup failed: ${String(error)}\n`);
    }
    if (!keepPostgres) {
      run("docker", ["compose", "-f", "compose.test.yaml", "down"]);
    }
  }
}

if (!completed) {
  process.exitCode = 1;
}
