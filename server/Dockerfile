# Сервер Beepy: API синхронизации и админка одним процессом.
# Сборка из корня репозитория: docker build -f server/Dockerfile .
# Корень нужен из-за админки — она собирается из crm/.

FROM node:22-alpine AS admin
WORKDIR /crm
COPY crm/package.json crm/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY crm/ ./
RUN npm run admin:build

FROM node:22-alpine AS deps
WORKDIR /app
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

FROM node:22-alpine
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787 ADMIN_DIST=/app/admin
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY server/package.json ./
COPY server/src ./src
COPY server/migrations ./migrations
COPY --from=admin /crm/dist-admin ./admin
USER node
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8787/v1/health || exit 1
CMD ["node", "--import", "tsx", "src/main.ts"]
