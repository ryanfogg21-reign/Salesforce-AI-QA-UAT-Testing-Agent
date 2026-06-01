// ─────────────────────────────────────────────────────────────────────────────
// callbackClient.ts — POSTs test results back to Salesforce REST API
// ─────────────────────────────────────────────────────────────────────────────

import { TestRunCallback } from './types.js';
import { logger } from './logger.js';

const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 2000;

export async function postCallback(
  callbackUrl: string,
  sfAccessToken: string,
  payload: TestRunCallback
): Promise<void> {
  // Strip screenshots from the payload before sending to Salesforce
  // (too large for an Apex REST callout — store screenshots separately if needed)
  const sanitizedPayload = {
    ...payload,
    stepResults: payload.stepResults.map(({ screenshotBase64: _ignored, ...rest }) => rest),
  };

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      logger.info(payload.sessionId, `Posting callback to Salesforce (attempt ${attempt})`, {
        url:    callbackUrl,
        status: payload.status,
      });

      const response = await fetch(callbackUrl, {
        method:  'POST',
        headers: {
          'Content-Type':  'application/json',
          'Authorization': `Bearer ${sfAccessToken}`,
        },
        body: JSON.stringify(sanitizedPayload),
      });

      if (response.ok) {
        logger.info(payload.sessionId, `Callback delivered successfully (HTTP ${response.status})`);
        return;
      }

      const body = await response.text().catch(() => '');
      logger.warn(payload.sessionId, `Callback returned HTTP ${response.status}`, { body });

      if (response.status >= 400 && response.status < 500) {
        // 4xx errors won't improve with retrying
        logger.error(payload.sessionId, 'Non-retryable callback error — giving up');
        return;
      }

    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      logger.warn(payload.sessionId, `Callback attempt ${attempt} failed: ${message}`);
    }

    if (attempt < MAX_RETRIES) {
      await new Promise((r) => setTimeout(r, RETRY_DELAY_MS * attempt));
    }
  }

  logger.error(payload.sessionId, `Failed to deliver callback after ${MAX_RETRIES} attempts`);
}
