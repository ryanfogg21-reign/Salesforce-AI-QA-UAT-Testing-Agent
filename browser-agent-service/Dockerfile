# ─────────────────────────────────────────────────────────────────────────────
# Dockerfile — browser-agent-service
# Uses the official Playwright image which includes all browser dependencies.
# ─────────────────────────────────────────────────────────────────────────────

FROM mcr.microsoft.com/playwright:v1.48.0-jammy

WORKDIR /app

# Install dependencies (production only in final image)
COPY package*.json ./
RUN npm ci --omit=dev

# Copy compiled TypeScript output
COPY dist/ ./dist/

# Non-root user for security
USER pwuser

EXPOSE 3000

# Health check so orchestrators know when the service is ready
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>r.ok?process.exit(0):process.exit(1)).catch(()=>process.exit(1))"

CMD ["node", "dist/index.js"]
