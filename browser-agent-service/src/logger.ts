// ─────────────────────────────────────────────────────────────────────────────
// logger.ts — structured console logger
// ─────────────────────────────────────────────────────────────────────────────

type LogLevel = 'info' | 'warn' | 'error' | 'debug';

function log(level: LogLevel, sessionId: string | null, message: string, data?: unknown): void {
  const entry = {
    ts:        new Date().toISOString(),
    level,
    session:   sessionId ?? 'system',
    message,
    ...(data !== undefined ? { data } : {}),
  };

  const line = JSON.stringify(entry);

  if (level === 'error') {
    console.error(line);
  } else if (level === 'warn') {
    console.warn(line);
  } else {
    console.log(line);
  }
}

export const logger = {
  info:  (sessionId: string | null, msg: string, data?: unknown) => log('info',  sessionId, msg, data),
  warn:  (sessionId: string | null, msg: string, data?: unknown) => log('warn',  sessionId, msg, data),
  error: (sessionId: string | null, msg: string, data?: unknown) => log('error', sessionId, msg, data),
  debug: (sessionId: string | null, msg: string, data?: unknown) => {
    if (process.env.LOG_LEVEL === 'debug') log('debug', sessionId, msg, data);
  },
};
