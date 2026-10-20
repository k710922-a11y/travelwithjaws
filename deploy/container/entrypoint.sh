#!/usr/bin/env bash
# 허브 컨테이너 시작 순서: (DB 연결 시) 마이그레이션 → 운영자 등록 → 서버
#   DATABASE_URL  postgresql://postgres:비밀번호@supabase-db-…:5432/postgres (Coolify 내부 네트워크)
#   CONSOLE_STAFF "staff_uuid|이름|역할1,역할2;…"  — CONSOLE_USERS 의 staff_uuid 와 같은 값
# 마이그레이션이 실패하면 서버를 띄우지 않는다 (Coolify 가 이전 컨테이너를 유지)
set -euo pipefail

if [ -n "${DATABASE_URL:-}" ]; then
  echo "[boot] DB 연결 대기"
  for i in $(seq 1 45); do
    pg_isready -d "$DATABASE_URL" -q && break
    [ "$i" -eq 45 ] && { echo "[boot] DB 에 연결할 수 없습니다"; exit 1; }
    sleep 2
  done
  echo "[boot] 마이그레이션"
  bash /app/db/migrate.sh

  if [ -n "${CONSOLE_STAFF:-}" ]; then
    IFS=';' read -ra items <<< "$CONSOLE_STAFF"
    for it in "${items[@]}"; do
      IFS='|' read -r sid sname sroles <<< "$it"
      [ -n "${sid:-}" ] || continue
      echo "insert into trip.staff(id, name, roles) values (:'sid'::uuid, :'n', :'r'::text[])
            on conflict (id) do update set name = excluded.name, roles = excluded.roles;" \
        | psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 -v sid="$sid" -v n="$sname" -v r="{$sroles}"
      echo "[boot] 운영자 확인: $sname"
    done
  fi
fi

echo "[boot] 서버 시작"
exec node server.js
