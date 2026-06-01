// ─────────────────────────────────────────────────────────────────────────────
// auth.ts — API key authentication middleware
// ─────────────────────────────────────────────────────────────────────────────

import { Request, Response, NextFunction } from 'express';
import { logger } from './logger.js';

export function requireApiKey(req: Request, res: Response, next: NextFunction): void {
  const serviceApiKey = process.env.SERVICE_API_KEY;

  if (!serviceApiKey) {
    logger.error(null, 'SERVICE_API_KEY not configured — rejecting all requests');
    res.status(500).json({ error: 'Service not properly configured' });
    return;
  }

  const authHeader = req.headers['authorization'];
  const providedKey = authHeader?.startsWith('Bearer ')
    ? authHeader.slice(7)
    : null;

  if (!providedKey || providedKey !== serviceApiKey) {
    logger.warn(null, 'Rejected request — invalid or missing API key', {
      ip: req.ip,
      path: req.path,
    });
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  next();
}
