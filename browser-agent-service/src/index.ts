// ─────────────────────────────────────────────────────────────────────────────
// index.ts — entry point
// ─────────────────────────────────────────────────────────────────────────────

import { startServer } from './server.js';

// Validate required environment variables at startup
const REQUIRED_ENV_VARS = ['ANTHROPIC_API_KEY', 'SERVICE_API_KEY'];

const missing = REQUIRED_ENV_VARS.filter((v) => !process.env[v]);
if (missing.length > 0) {
  console.error(`[FATAL] Missing required environment variables: ${missing.join(', ')}`);
  console.error('Copy .env.example to .env and fill in the values.');
  process.exit(1);
}

startServer();
