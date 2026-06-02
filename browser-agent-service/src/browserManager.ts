// ─────────────────────────────────────────────────────────────────────────────
// browserManager.ts — Playwright browser lifecycle and action executor
// ─────────────────────────────────────────────────────────────────────────────

import { chromium, Browser, BrowserContext, Page } from 'playwright';
import { ComputerAction } from './types.js';
import { logger } from './logger.js';

// Viewport matches Claude computer-use expected dimensions
export const VIEWPORT_WIDTH  = 1280;
export const VIEWPORT_HEIGHT = 800;

// ─── Browser / Page lifecycle ─────────────────────────────────────────────────

export async function launchBrowser(): Promise<{ browser: Browser; context: BrowserContext; page: Page }> {
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',   // use /tmp instead of /dev/shm (required in Docker)
      '--disable-gpu',
      '--no-zygote',               // skip the zygote process — reduces memory in containers
      '--single-process',          // run renderer in the browser process — lower RAM overhead
      '--disable-extensions',
      '--disable-background-networking',
      '--disable-default-apps',
      '--no-first-run',
      '--mute-audio',
    ],
  });

  const context = await browser.newContext({
    viewport: { width: VIEWPORT_WIDTH, height: VIEWPORT_HEIGHT },
    userAgent:
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    // Accept language matching Salesforce default locale
    locale: 'en-US',
  });

  const page = await context.newPage();

  // Dismiss any Salesforce dialog/modal popups that might block interaction
  page.on('dialog', async (dialog) => {
    logger.debug(null, `Auto-dismissing dialog: ${dialog.message()}`);
    await dialog.dismiss().catch(() => {});
  });

  return { browser, context, page };
}

export async function closeBrowser(browser: Browser): Promise<void> {
  try {
    await browser.close();
  } catch {
    // ignore close errors
  }
}

// ─── Screenshot ───────────────────────────────────────────────────────────────

export async function captureScreenshot(page: Page): Promise<string> {
  const buffer = await page.screenshot({
    type:     'png',
    fullPage: false, // viewport only — matches what Claude sees
  });
  return buffer.toString('base64');
}

// ─── Action executor ─────────────────────────────────────────────────────────

/**
 * Executes a single computer-use action in the Playwright page.
 * Always waits briefly after each action for Salesforce Lightning to re-render.
 */
export async function executeAction(
  page: Page,
  action: ComputerAction,
  sessionId: string
): Promise<void> {
  logger.debug(sessionId, `Executing action: ${action.action}`, action);

  switch (action.action) {
    case 'screenshot':
      // Caller handles screenshot capture — nothing to do here
      break;

    case 'left_click':
      await page.mouse.click(action.coordinate[0], action.coordinate[1]);
      break;

    case 'right_click':
      await page.mouse.click(action.coordinate[0], action.coordinate[1], { button: 'right' });
      break;

    case 'double_click':
      await page.mouse.dblclick(action.coordinate[0], action.coordinate[1]);
      break;

    case 'type':
      await page.keyboard.type(action.text, { delay: 25 });
      break;

    case 'key':
      await page.keyboard.press(normalizeKey(action.text));
      break;

    case 'scroll':
      await page.mouse.wheel(
        action.direction === 'up' || action.direction === 'down' ? 0 : action.amount * 100,
        action.direction === 'down' ? action.amount * 100 : action.direction === 'up' ? -action.amount * 100 : 0
      );
      break;

    case 'mouse_move':
      await page.mouse.move(action.coordinate[0], action.coordinate[1]);
      break;

    case 'left_click_drag':
      await page.mouse.move(action.startCoordinate[0], action.startCoordinate[1]);
      await page.mouse.down();
      await page.mouse.move(action.coordinate[0], action.coordinate[1], { steps: 10 });
      await page.mouse.up();
      break;

    default:
      logger.warn(sessionId, `Unknown action type: ${(action as ComputerAction).action}`);
  }

  // Salesforce Lightning needs time to process interactions —
  // wait for any pending network requests and React re-renders
  await waitForLightning(page);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Waits for Salesforce Lightning to finish re-rendering after an action.
 * Uses a combination of network idle and a short fixed delay.
 */
async function waitForLightning(page: Page): Promise<void> {
  try {
    await page.waitForLoadState('networkidle', { timeout: 3000 });
  } catch {
    // networkidle timeout is fine — Lightning SPAs stay "active"
    // Fall back to a fixed delay
  }
  // Small fixed delay for DOM updates that don't trigger network calls
  await new Promise((r) => setTimeout(r, 300));
}

/**
 * Normalizes Claude's key names to Playwright's expected format.
 * Claude uses key names like "Return", "ctrl+a", "BackSpace" etc.
 */
function normalizeKey(key: string): string {
  const keyMap: Record<string, string> = {
    Return:    'Enter',
    BackSpace: 'Backspace',
    Escape:    'Escape',
    Tab:       'Tab',
    Delete:    'Delete',
    space:     'Space',
  };

  // Handle combos like "ctrl+a" → "Control+a"
  return key
    .split('+')
    .map((k) => keyMap[k] ?? k)
    .join('+');
}
