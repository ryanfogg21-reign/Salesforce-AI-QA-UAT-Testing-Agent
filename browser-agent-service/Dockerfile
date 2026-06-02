# ─────────────────────────────────────────────────────────────────────────────
# Dockerfile — browser-agent-service
# Uses the official Playwright image which includes all browser dependencies.
# ─────────────────────────────────────────────────────────────────────────────

FROM mcr.microsoft.com/playwright:v1.60.0-jammy

WORKDIR /app

# Install ALL dependencies (including devDeps needed for tsc build)
COPY package*.json ./
RUN npm ci

# Copy source and compile TypeScript
COPY tsconfig.json ./
COPY src/ ./src/
RUN npm run build

# Remove dev dependencies after build
RUN npm prune --omit=dev

# Non-root user for security
USER pwuser

EXPOSE 3000

# Health check so orchestrators know when the service is ready
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>r.ok?process.exit(0):process.exit(1)).catch(()=>process.exit(1))"

CMD ["node", "dist/index.js"]
