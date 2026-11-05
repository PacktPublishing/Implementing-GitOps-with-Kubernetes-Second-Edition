# syntax=docker/dockerfile:1

# Node.js 24 is the LTS line the official "lts" image tag points to in
# November 2026 (maintenance until April 2028). Pin the digest in your own
# fork; Renovate (Chapter 5) keeps it current.

# ---- build stage: install production dependencies only -----------------------
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev || npm install --omit=dev

# ---- runtime stage -----------------------------------------------------------
FROM node:24-alpine AS runtime
ARG APP_REVISION=dev
ENV NODE_ENV=production \
    APP_REVISION=${APP_REVISION}
WORKDIR /app

# node:*-alpine ships an unprivileged "node" user (uid 1000).
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node server.js ./
COPY --chown=node:node public ./public

USER 1000
EXPOSE 8080

CMD ["node", "server.js"]
