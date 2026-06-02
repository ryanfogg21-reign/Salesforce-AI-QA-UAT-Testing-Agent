// ─────────────────────────────────────────────────────────────────────────────
// executor.ts — core test execution loop
// ─────────────────────────────────────────────────────────────────────────────

import Anthropic from '@anthropic-ai/sdk';
import { Page } from 'playwright';
import {
  ExecuteTestRequest,
  TestStep,
  StepResult,
  SessionStatus,
} from './types.js';
import {
  launchBrowser,
  closeBrowser,
  captureScreenshot,
  executeAction,
} from './browserManager.js';
import {
  askClaude,
  buildStepMessage,
  buildToolResultMessage,
} from './claudeClient.js';
import { sessionStore } from './sessionStore.js';
import { postCallback } from './callbackClient.js';
import { logger } from './logger.js';

// ─── Entry point ──────────────────────────────────────────────────────────────

/**
 * Runs the full test script. Called asynchronously after the HTTP response is sent.
 * On completion, POSTs results back to the Salesforce callback URL.
 */
export async function executeTestScript(req: ExecuteTestRequest): Promise<void> {
  const { sessionId, testRunId, steps, callbackUrl, sfAccessToken } = req;
  const startTime = Date.now();

  // Initialize session state
  sessionStore.set(sessionId, {
    sessionId,
    testRunId,
    status:      'running',
    currentStep: 0,
    totalSteps:  steps.length,
    stepResults: [],
    startedAt:   new Date(),
  });

  logger.info(sessionId, `Starting test: "${req.testScriptName}"`, {
    steps:   steps.length,
    timeout: req.timeoutMinutes,
    target:  req.targetUrl,
  });

  const { browser, page } = await launchBrowser();

  try {
    // ── Log in to Salesforce via frontdoor.jsp ─────────────────────────────────
    // The sfAccessToken (UserInfo.getSessionId()) lets us authenticate the
    // Playwright browser without needing a username/password.
    // frontdoor.jsp establishes the session and redirects to retURL.
    const orgBaseUrl = callbackUrl.replace('/services/apexrest/qatester/callback', '');

    let retURL = '/';
    if (req.targetUrl) {
      try {
        // If it's a full URL, extract just the path portion for retURL
        const parsed = new URL(req.targetUrl);
        retURL = parsed.pathname + parsed.search + parsed.hash;
      } catch {
        // Already a relative path
        retURL = req.targetUrl.startsWith('/') ? req.targetUrl : '/' + req.targetUrl;
      }
    }

    const loginUrl = `${orgBaseUrl}/secur/frontdoor.jsp`
      + `?sid=${encodeURIComponent(sfAccessToken)}`
      + `&retURL=${encodeURIComponent(retURL)}`;

    logger.info(sessionId, `Authenticating browser via frontdoor.jsp`, { retURL });
    await page.goto(loginUrl, { waitUntil: 'networkidle', timeout: 30_000 });
    logger.info(sessionId, `Browser authenticated, current URL: ${page.url()}`);

    const stepResults: StepResult[] = [];
    let stepsPassed = 0;
    let stepsFailed = 0;

    for (const step of steps) {
      // Check overall timeout
      const elapsedMinutes = (Date.now() - startTime) / 60_000;
      if (elapsedMinutes >= req.timeoutMinutes) {
        logger.warn(sessionId, `Overall timeout reached after ${Math.round(elapsedMinutes)} min`);
        stepResults.push({
          stepId:       step.id,
          stepNumber:   step.stepNumber,
          description:  step.description,
          passed:       false,
          reason:       `Test timed out after ${req.timeoutMinutes} minutes`,
          actionsCount: 0,
          durationMs:   0,
        });
        stepsFailed++;
        break;
      }

      // Update session with current step
      const session = sessionStore.get(sessionId)!;
      session.currentStep = step.stepNumber;
      sessionStore.set(sessionId, session);

      logger.info(sessionId, `Executing step ${step.stepNumber}: ${step.description.slice(0, 80)}`);

      const result = await executeStep(page, step, sessionId);
      stepResults.push(result);

      if (result.passed) {
        stepsPassed++;
      } else {
        stepsFailed++;
        logger.warn(sessionId, `Step ${step.stepNumber} FAILED: ${result.reason}`);

        // Stop on first failure unless script says continue
        if (!req.continueOnFailure && !step.continueOnFail) {
          logger.info(sessionId, 'Stopping execution on failure (continueOnFailure=false)');
          break;
        }
      }
    }

    const durationSeconds = Math.round((Date.now() - startTime) / 1000);
    const overallPassed   = stepsFailed === 0;
    const status          = overallPassed ? 'Passed' : 'Failed';

    // Build plain-English summary for the Agentforce agent to relay
    const summary = buildSummary(req.testScriptName, stepResults, overallPassed);

    logger.info(sessionId, `Test complete: ${status}`, {
      passed: stepsPassed,
      failed: stepsFailed,
      total:  steps.length,
      seconds: durationSeconds,
    });

    // Update session store
    const finalSession = sessionStore.get(sessionId)!;
    finalSession.status      = 'completed';
    finalSession.stepResults = stepResults;
    sessionStore.set(sessionId, finalSession);

    // POST result back to Salesforce
    await postCallback(callbackUrl, sfAccessToken, {
      sessionId,
      testRunId,
      status,
      summary,
      durationSeconds,
      stepsPassed,
      stepsFailed,
      stepsTotal:  steps.length,
      stepResults,
    });

  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    logger.error(sessionId, `Unhandled error during test execution: ${message}`);

    const session = sessionStore.get(sessionId);
    if (session) {
      session.status = 'error';
      session.error  = message;
      sessionStore.set(sessionId, session);
    }

    await postCallback(callbackUrl, sfAccessToken, {
      sessionId,
      testRunId,
      status:          'Error',
      summary:         'Test execution failed due to an internal service error.',
      errorMessage:    message,
      durationSeconds: Math.round((Date.now() - startTime) / 1000),
      stepsPassed:     0,
      stepsFailed:     0,
      stepsTotal:      steps.length,
      stepResults:     [],
    });

  } finally {
    await closeBrowser(browser);
  }
}

// ─── Single step execution ────────────────────────────────────────────────────

async function executeStep(
  page: Page,
  step: TestStep,
  sessionId: string
): Promise<StepResult> {
  const stepStart = Date.now();
  const conversation: Anthropic.MessageParam[] = [];
  let actionsCount = 0;

  // Apply per-step timeout
  const stepTimeoutMs = step.timeoutSeconds * 1_000;
  const stepDeadline  = Date.now() + stepTimeoutMs;

  try {
    // Take initial screenshot and build first message
    const initialShot = await captureScreenshot(page);
    conversation.push(buildStepMessage(initialShot, step.description, step.expectedOutcome));

    while (actionsCount < step.maxActions) {

      // Check step-level timeout
      if (Date.now() > stepDeadline) {
        return {
          stepId:       step.id,
          stepNumber:   step.stepNumber,
          description:  step.description,
          passed:       false,
          reason:       `Step timed out after ${step.timeoutSeconds}s (${actionsCount} actions taken)`,
          actionsCount,
          durationMs:   Date.now() - stepStart,
        };
      }

      // Ask Claude what to do
      const decision = await askClaude(
        sessionId,
        conversation,
        step.description,
        step.expectedOutcome
      );

      // Add Claude's response to conversation history
      if (decision.actions.length > 0) {
        // Claude used tools — record this in conversation
        // (we reconstruct the assistant message from the actions)
        conversation.push({
          role: 'assistant',
          content: decision.actions.map((a, i) => ({
            type:  'tool_use' as const,
            id:    `tool_${actionsCount}_${i}`,
            name:  'computer',
            input: a,
          })),
        });
      }

      // If Claude is done, return the verdict
      if (decision.isComplete && decision.verdict) {
        const finalShot = await captureScreenshot(page);
        return {
          stepId:           step.id,
          stepNumber:       step.stepNumber,
          description:      step.description,
          passed:           decision.verdict.passed,
          reason:           decision.verdict.reason,
          actionsCount,
          durationMs:       Date.now() - stepStart,
          screenshotBase64: finalShot,
        };
      }

      // Execute each action Claude requested and feed back a screenshot
      const toolUseIds: string[] = [];
      for (let i = 0; i < decision.actions.length; i++) {
        const action = decision.actions[i];
        toolUseIds.push(`tool_${actionsCount}_${i}`);

        if (action.action !== 'screenshot') {
          await executeAction(page, action, sessionId);
          actionsCount++;
        }
      }

      // Capture screenshot after all actions and add as tool result
      const newShot = await captureScreenshot(page);
      conversation.push(buildToolResultMessage(toolUseIds, newShot));
    }

    // Exceeded max actions without a verdict
    const finalShot = await captureScreenshot(page);
    return {
      stepId:           step.id,
      stepNumber:       step.stepNumber,
      description:      step.description,
      passed:           false,
      reason:           `Reached maximum action limit (${step.maxActions}) without completing the step`,
      actionsCount,
      durationMs:       Date.now() - stepStart,
      screenshotBase64: finalShot,
    };

  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      stepId:       step.id,
      stepNumber:   step.stepNumber,
      description:  step.description,
      passed:       false,
      reason:       `Step threw an exception: ${message}`,
      actionsCount,
      durationMs:   Date.now() - stepStart,
    };
  }
}

// ─── Summary builder ──────────────────────────────────────────────────────────

function buildSummary(
  scriptName: string,
  results: StepResult[],
  overallPassed: boolean
): string {
  const passed  = results.filter((r) => r.passed).length;
  const failed  = results.filter((r) => !r.passed).length;
  const total   = results.length;

  const lines = [
    `${overallPassed ? '✅ PASSED' : '❌ FAILED'}: "${scriptName}"`,
    `${passed}/${total} steps passed.`,
  ];

  if (failed > 0) {
    lines.push('Failed steps:');
    results
      .filter((r) => !r.passed)
      .forEach((r) => lines.push(`  • Step ${r.stepNumber}: ${r.reason}`));
  }

  return lines.join('\n');
}
