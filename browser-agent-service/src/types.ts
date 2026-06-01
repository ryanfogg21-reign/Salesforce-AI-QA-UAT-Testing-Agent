// ─────────────────────────────────────────────────────────────────────────────
// types.ts — shared TypeScript interfaces for the browser agent service
// ─────────────────────────────────────────────────────────────────────────────

// ─── Inbound from Salesforce ──────────────────────────────────────────────────

export interface TestStep {
  id: string;
  stepNumber: number;
  stepType: 'Navigate' | 'Click' | 'Fill' | 'Assert' | 'Verify' | 'Wait' | 'Screenshot' | 'Multi-Action';
  description: string;
  expectedOutcome?: string;
  continueOnFail: boolean;
  timeoutSeconds: number;
  maxActions: number;
}

export interface ExecuteTestRequest {
  sessionId: string;
  testRunId: string;
  testScriptName: string;
  callbackUrl: string;
  sfAccessToken: string;
  targetUrl: string;
  timeoutMinutes: number;
  continueOnFailure: boolean;
  steps: TestStep[];
}

// ─── Internal ─────────────────────────────────────────────────────────────────

export interface StepResult {
  stepId: string;
  stepNumber: number;
  description: string;
  passed: boolean;
  reason: string;
  actionsCount: number;
  durationMs: number;
  screenshotBase64?: string; // final screenshot for this step
}

export interface SessionStatus {
  sessionId: string;
  testRunId: string;
  status: 'running' | 'completed' | 'error';
  currentStep?: number;
  totalSteps: number;
  stepResults: StepResult[];
  startedAt: Date;
  error?: string;
}

// ─── Claude computer-use action shapes ────────────────────────────────────────

export interface ScreenshotAction {
  action: 'screenshot';
}

export interface LeftClickAction {
  action: 'left_click';
  coordinate: [number, number];
}

export interface RightClickAction {
  action: 'right_click';
  coordinate: [number, number];
}

export interface DoubleClickAction {
  action: 'double_click';
  coordinate: [number, number];
}

export interface TypeAction {
  action: 'type';
  text: string;
}

export interface KeyAction {
  action: 'key';
  text: string;
}

export interface ScrollAction {
  action: 'scroll';
  coordinate: [number, number];
  direction: 'up' | 'down' | 'left' | 'right';
  amount: number;
}

export interface MouseMoveAction {
  action: 'mouse_move';
  coordinate: [number, number];
}

export interface LeftClickDragAction {
  action: 'left_click_drag';
  startCoordinate: [number, number];
  coordinate: [number, number];
}

export type ComputerAction =
  | ScreenshotAction
  | LeftClickAction
  | RightClickAction
  | DoubleClickAction
  | TypeAction
  | KeyAction
  | ScrollAction
  | MouseMoveAction
  | LeftClickDragAction;

// ─── Outbound to Salesforce callback ─────────────────────────────────────────

export interface TestRunCallback {
  sessionId: string;
  testRunId: string;
  status: 'Passed' | 'Failed' | 'Error';
  summary: string;
  errorMessage?: string;
  durationSeconds: number;
  stepsPassed: number;
  stepsFailed: number;
  stepsTotal: number;
  stepResults: StepResult[];
}
