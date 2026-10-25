# syntax=docker/dockerfile:1

# ---- build stage: install production dependencies only -----------------------
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm install --omit=dev

# ---- runtime stage -----------------------------------------------------------
FROM node:22-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# node:*-alpine already ships an unprivileged "node" user (uid 1000).
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node server.js ./
COPY --chown=node:node public ./public

USER node
EXPOSE 8080

# Kubernetes probes are authoritative; this keeps `docker run` honest too.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]
