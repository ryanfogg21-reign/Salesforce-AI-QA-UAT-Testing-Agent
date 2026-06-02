// ─────────────────────────────────────────────────────────────────────────────
// index.ts — entry point
// ─────────────────────────────────────────────────────────────────────────────

import { startServer } from './server.js';

// Force stdout/stderr to flush immediately — Node.js buffers these when
// stdout is a pipe (which it is inside Docker/Railway containers).
// Without this, log lines sit in an in-process buffer and never appear
// in Railway's log view until the buffer fills up (~64 KB) or the
// process exits.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(process.stdout as any)._handle?.setBlocking(true);
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(process.stderr as any)._handle?.setBlocking(true);

// Validate required environment variables at startup
const REQUIRED_ENV_VARS = ['ANTHROPIC_API_KEY', 'SERVICE_API_KEY'];

const missing = REQUIRED_ENV_VARS.filter((v) => !process.env[v]);
if (missing.length > 0) {
  console.error(`[FATAL] Missing required environment variables: ${missing.join(', ')}`);
  console.error('Copy .env.example to .env and fill in the values.');
  process.exit(1);
}

startServer();
