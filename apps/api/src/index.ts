import 'dotenv/config';

import { createApp } from './app.js';

const DEFAULT_PORT = 3000;

function resolvePort(rawPort: string | undefined): number {
  if (rawPort === undefined) {
    return DEFAULT_PORT;
  }

  if (!/^\d+$/.test(rawPort)) {
    throw new Error('PORT must be an integer between 1 and 65535.');
  }

  const port = Number(rawPort);

  if (!Number.isSafeInteger(port) || port < 1 || port > 65_535) {
    throw new Error('PORT must be an integer between 1 and 65535.');
  }

  return port;
}

const port = resolvePort(process.env.PORT);
const app = createApp();

app.listen(port, () => {
  console.log(`Household Expenses API listening on port ${String(port)}.`);
});
