# Travel.with.Jaws 허브 — Coolify: Base Directory "/" · Dockerfile "/Dockerfile" · 포트 3000
# 컨테이너가 시작할 때 DATABASE_URL 이 있으면 DB 마이그레이션과 운영자 등록을 먼저 하고 서버를 띄운다.
FROM node:22-alpine AS deps
WORKDIR /app
COPY hub/package*.json ./
RUN npm ci --no-audit --no-fund

FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY hub/ .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine
RUN apk add --no-cache bash postgresql16-client
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
COPY db/migrations ./db/migrations
COPY db/migrate.sh ./db/migrate.sh
COPY deploy/container/entrypoint.sh ./entrypoint.sh
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/api/health || exit 1
CMD ["bash", "/app/entrypoint.sh"]
