#!/usr/bin/env bash
# 미니PC에서 실행: 운영자 등록 + 편집 콘솔 로그인 줄 생성
#   bash deploy/minipc/add-staff.sh "정수" product,editor jungsoo [supabase-db 컨테이너 이름]
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
name="${1:?이름}"; roles="${2:?역할}"; login="${3:?로그인 아이디}"; DBC="${4:-}"
DOCKER=docker; $DOCKER ps >/dev/null 2>&1 || DOCKER="sudo docker"
if [ -z "$DBC" ]; then
  mapfile -t found < <($DOCKER ps --format '{{.Names}}' | grep -E 'supabase-db' || true)
  [ "${#found[@]}" -eq 1 ] || { echo "Supabase DB 컨테이너 이름을 네 번째 인자로 주세요:"; printf '  %s\n' "${found[@]}"; exit 1; }
  DBC="${found[0]}"
fi
NET=$($DOCKER inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' "$DBC" | head -1)
PW=$($DOCKER inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$DBC" | sed -n 's/^POSTGRES_PASSWORD=//p' | head -1)
$DOCKER run --rm -i --network "$NET" -e DATABASE_URL="postgresql://postgres:${PW}@${DBC}:5432/postgres" \
  -v "$REPO/db:/db:ro" postgres:16 bash /db/add_staff.sh "$name" "$roles" "$login"
