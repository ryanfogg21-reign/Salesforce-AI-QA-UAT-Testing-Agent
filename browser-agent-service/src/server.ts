// ─────────────────────────────────────────────────────────────────────────────
// server.ts — Express HTTP server with all route definitions
// ─────────────────────────────────────────────────────────────────────────────

import express, { Request, Response } from 'express';
import { requireApiKey } from './auth.js';
import { executeTestScript } from './executor.js';
import { sessionStore } from './sessionStore.js';
import { ExecuteTestRequest } from './types.js';
import { logger } from './logger.js';

const app = express();
app.use(express.json({ limit: '1mb' }));

// ─── Health check (no auth) ───────────────────────────────────────────────────

app.get('/health', (_req: Request, res: Response) => {
  res.json({
    status:    'ok',
    service:   'browser-agent-service',
    timestamp: new Date().toISOString(),
    sessions:  sessionStore.size(),
  });
});

// ─── All other routes require API key ─────────────────────────────────────────

app.use(requireApiKey);

// ─── POST /execute-test ───────────────────────────────────────────────────────
// Validates the request, acknowledges immediately, then runs async.

app.post('/execute-test', async (req: Request, res: Response) => {
  const body = req.body as Partial<ExecuteTestRequest>;

  // Basic validation
  const missing: string[] = [];
  if (!body.sessionId)    missing.push('sessionId');
  if (!body.testRunId)    missing.push('testRunId');
  if (!body.callbackUrl)  missing.push('callbackUrl');
  if (!body.steps?.length) missing.push('steps');

  if (missing.length > 0) {
    res.status(400).json({ error: `Missing required fields: ${missing.join(', ')}` });
    return;
  }

  const testReq = body as ExecuteTestRequest;

  // Check concurrency limit
  const MAX_CONCURRENT = parseInt(process.env.MAX_CONCURRENT_SESSIONS ?? '5', 10);
  if (sessionStore.size() >= MAX_CONCURRENT) {
    logger.warn(null, `Concurrency limit reached (${MAX_CONCURRENT}) — rejecting request`);
    res.status(429).json({
      error:     'Service at capacity. Please retry in a few minutes.',
      retryAfterSeconds: 60,
    });
    return;
  }

  // Acknowledge immediately — Salesforce's callout timeout is 2 minutes
  res.status(200).json({
    sessionId: testReq.sessionId,
    status:    'running',
    message:   `Test "${testReq.testScriptName}" accepted. Results will be POSTed to callbackUrl.`,
  });

  // Run asynchronously — result POSTed to callbackUrl when complete
  setImmediate(() => {
    executeTestScript(testReq).catch((err) => {
      logger.error(testReq.sessionId, 'Unhandled top-level error in executeTestScript', {
        error: err instanceof Error ? err.message : String(err),
      });
    });
  });
});

// ─── GET /status/:sessionId ───────────────────────────────────────────────────
// Polling fallback in case Salesforce didn't receive the callback.

app.get('/status/:sessionId', (req: Request, res: Response) => {
  const { sessionId } = req.params;
  const session = sessionStore.get(sessionId);

  if (!session) {
    res.status(404).json({ error: `No session found for ID: ${sessionId}` });
    return;
  }

  // Return status without full screenshot data
  const { stepResults, ...summary } = session;
  res.json({
    ...summary,
    stepCount: {
      total:  stepResults.length,
      passed: stepResults.filter((r) => r.passed).length,
      failed: stepResults.filter((r) => !r.passed).length,
    },
  });
});

// ─── GET /sessions ────────────────────────────────────────────────────────────
// Admin endpoint — lists active session IDs.

app.get('/sessions', (_req: Request, res: Response) => {
  res.json({ activeSessions: sessionStore.size() });
});

// ─── 404 fallback ─────────────────────────────────────────────────────────────

app.use((_req: Request, res: Response) => {
  res.status(404).json({ error: 'Not found' });
});

// ─── Start ────────────────────────────────────────────────────────────────────

const PORT = parseInt(process.env.PORT ?? '3000', 10);

export function startServer(): void {
  app.listen(PORT, () => {
    logger.info(null, `Browser agent service started`, {
      port:       PORT,
      model:      process.env.CLAUDE_MODEL ?? 'claude-sonnet-4-6',
      maxSessions: process.env.MAX_CONCURRENT_SESSIONS ?? '5',
    });
  });
}

export default app;
