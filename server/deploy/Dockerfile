FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund
COPY src ./src
COPY migrations ./migrations
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787 VEHICLE_PROXY_ONLY=1
USER node
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8787/v1/health || exit 1
CMD ["node", "--import", "tsx", "src/main.ts"]
