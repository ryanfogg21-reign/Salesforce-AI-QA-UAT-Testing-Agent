// ─────────────────────────────────────────────────────────────────────────────
// sessionStore.ts — in-memory session state store
// For production, swap this for Redis or a DB-backed store.
// ─────────────────────────────────────────────────────────────────────────────

import { SessionStatus } from './types.js';

// Simple in-memory map — persists for the lifetime of the process
const store = new Map<string, SessionStatus>();

// Auto-expire sessions after 2 hours to prevent memory leaks
const SESSION_TTL_MS = 2 * 60 * 60 * 1000;

export const sessionStore = {
  get(sessionId: string): SessionStatus | undefined {
    return store.get(sessionId);
  },

  set(sessionId: string, status: SessionStatus): void {
    store.set(sessionId, status);

    // Schedule auto-cleanup
    setTimeout(() => {
      store.delete(sessionId);
    }, SESSION_TTL_MS);
  },

  delete(sessionId: string): void {
    store.delete(sessionId);
  },

  size(): number {
    return store.size;
  },
};
