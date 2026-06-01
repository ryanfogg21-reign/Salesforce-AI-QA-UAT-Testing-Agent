// ─────────────────────────────────────────────────────────────────────────────
// claudeClient.ts — Anthropic Claude computer-use API wrapper
// ─────────────────────────────────────────────────────────────────────────────

import Anthropic from '@anthropic-ai/sdk';
import { ComputerAction } from './types.js';
import { VIEWPORT_WIDTH, VIEWPORT_HEIGHT } from './browserManager.js';
import { logger } from './logger.js';

const client = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

const COMPUTER_USE_MODEL = process.env.CLAUDE_MODEL ?? 'claude-opus-4-5';

// Computer-use tool definition — typed as `any` because the SDK's Tool type
// doesn't yet include the beta computer_20241022 variant in all versions.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const COMPUTER_TOOL: any = {
  type:              'computer_20241022',
  name:              'computer',
  display_width_px:  VIEWPORT_WIDTH,
  display_height_px: VIEWPORT_HEIGHT,
  display_number:    1,
};

// ─── Types ────────────────────────────────────────────────────────────────────

export interface ClaudeStepDecision {
  actions:   ComputerAction[];
  verdict?:  { passed: boolean; reason: string };
  isComplete: boolean;
  rawContent: Anthropic.ContentBlock[];
}

// ─── System prompt ────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `You are an expert QA automation agent executing UI test steps in Salesforce Lightning.

ENVIRONMENT:
- You are controlling a ${VIEWPORT_WIDTH}x${VIEWPORT_HEIGHT} browser showing a Salesforce org
- Salesforce Lightning uses dynamic CSS — always prefer clicking visible text labels over selectors
- After any click, wait for the Lightning spinner (circular animation) to disappear before continuing
- Picklist dropdowns require clicking the chevron/arrow icon, then clicking the option from the list

EXECUTING A STEP:
1. Look at the screenshot carefully — identify the element described in the step
2. Use the computer tool to interact with the UI
3. After each action, you will receive a new screenshot — assess whether the action had the intended effect
4. When the expected outcome is achieved (or clearly cannot be achieved), respond with a JSON verdict:
   {"passed": true/false, "reason": "brief explanation of what was observed"}
5. Do NOT include any other text with the verdict JSON — output it alone

IMPORTANT RULES:
- Only interact with what is visible on screen
- If a step says "Fill", type the text then press Tab or click away to commit it
- If the expected outcome mentions a specific value or text, verify you can see it before marking passed
- If you cannot locate an element after 3 attempts, mark the step as failed with the reason
- NEVER navigate away from the current app unless the step explicitly says to navigate`;

// ─── Main function ────────────────────────────────────────────────────────────

export async function askClaude(
  sessionId: string,
  conversationHistory: Anthropic.MessageParam[],
  stepDescription: string,
  expectedOutcome: string | undefined
): Promise<ClaudeStepDecision> {

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const response = await (client.messages.create as any)({
    model:      COMPUTER_USE_MODEL,
    max_tokens: 1024,
    system:     SYSTEM_PROMPT,
    betas:      ['computer-use-2024-10-22'],
    tools:      [COMPUTER_TOOL],
    messages:   conversationHistory,
  }) as Anthropic.Message;

  logger.debug(sessionId, 'Claude response', {
    stopReason:   response.stop_reason,
    contentTypes: response.content.map((c: Anthropic.ContentBlock) => c.type),
  });

  // ── Case 1: Claude used tools (browser actions) ───────────────────────────
  if (response.stop_reason === 'tool_use') {
    const toolUseBlocks = response.content.filter(
      (c: Anthropic.ContentBlock) => c.type === 'tool_use'
    ) as Anthropic.ToolUseBlock[];

    const actions: ComputerAction[] = toolUseBlocks.map(
      (b: Anthropic.ToolUseBlock) => b.input as ComputerAction
    );
    return { actions, isComplete: false, rawContent: response.content };
  }

  // ── Case 2: end_turn — look for JSON verdict ──────────────────────────────
  if (response.stop_reason === 'end_turn') {
    const textBlock = response.content.find(
      (c: Anthropic.ContentBlock) => c.type === 'text'
    ) as Anthropic.TextBlock | undefined;

    const text = textBlock?.text.trim() ?? '';
    const jsonMatch = text.match(/\{[\s\S]*"passed"[\s\S]*\}/);

    if (jsonMatch) {
      try {
        const verdict = JSON.parse(jsonMatch[0]) as { passed: boolean; reason: string };
        return { actions: [], verdict, isComplete: true, rawContent: response.content };
      } catch {
        logger.warn(sessionId, 'Could not parse Claude verdict JSON', { text });
      }
    }

    return {
      actions:    [],
      verdict:    { passed: false, reason: `No verdict returned. Response: ${text.slice(0, 200)}` },
      isComplete: true,
      rawContent: response.content,
    };
  }

  // ── Case 3: unexpected stop reason ────────────────────────────────────────
  return {
    actions:    [],
    verdict:    { passed: false, reason: `Unexpected stop reason: ${response.stop_reason}` },
    isComplete: true,
    rawContent: response.content,
  };
}

// ─── Message builders ─────────────────────────────────────────────────────────

export function buildStepMessage(
  screenshotBase64: string,
  stepDescription: string,
  expectedOutcome: string | undefined
): Anthropic.MessageParam {
  return {
    role: 'user',
    content: [
      {
        type:   'image',
        source: { type: 'base64', media_type: 'image/png', data: screenshotBase64 },
      },
      {
        type: 'text',
        text: `STEP TO EXECUTE:\n${stepDescription}\n\n` +
              (expectedOutcome ? `EXPECTED OUTCOME:\n${expectedOutcome}\n\n` : '') +
              'Please execute this step now. When complete, output your JSON verdict.',
      },
    ],
  };
}

export function buildToolResultMessage(
  toolUseIds: string[],
  screenshotBase64: string
): Anthropic.MessageParam {
  return {
    role: 'user',
    content: toolUseIds.map((id) => ({
      type:        'tool_result' as const,
      tool_use_id: id,
      content: [
        {
          type:   'image' as const,
          source: {
            type:       'base64' as const,
            media_type: 'image/png' as const,
            data:       screenshotBase64,
          },
        },
      ],
    })),
  };
}
