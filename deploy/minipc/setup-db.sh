#!/usr/bin/env bash
# 미니PC(keymedi-mini-pc)에서 실행: Coolify 로 띄운 Supabase DB 에 Travel.with.Jaws 마이그레이션 적용
#
#   cd ~/travelwithjaws && git pull && bash deploy/minipc/setup-db.sh
#   (DB 컨테이너 이름을 직접 줄 때)  bash deploy/minipc/setup-db.sh <supabase-db 컨테이너 이름>
#   (적용 예정만 보기)               DRY_RUN=1 bash deploy/minipc/setup-db.sh
#
# 하는 일
#   1) Supabase DB 컨테이너를 찾아 같은 도커 네트워크에서 postgres:16 클라이언트 컨테이너로 접속
#   2) db/migrate.sh 실행 — 아직 적용하지 않은 마이그레이션만 순서대로 적용, 적용된 파일 변조 시 중단
#   3) PostgREST(API)가 trip 스키마를 노출하는지 확인하고 안내
# DB 비밀번호는 컨테이너 설정에서 읽어 쓰기만 하고 화면·파일에 남기지 않는다.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
say() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }

command -v docker >/dev/null || { echo "docker 가 없습니다"; exit 1; }
DOCKER=docker; $DOCKER ps >/dev/null 2>&1 || DOCKER="sudo docker"

say "Supabase DB 컨테이너 찾기"
DBC="${1:-}"
if [ -z "$DBC" ]; then
  mapfile -t found < <($DOCKER ps --format '{{.Names}}' | grep -E 'supabase-db' || true)
  if [ "${#found[@]}" -eq 0 ]; then echo "supabase-db 컨테이너가 없습니다. Coolify 에서 Supabase 서비스를 먼저 만드세요."; exit 1; fi
  if [ "${#found[@]}" -gt 1 ]; then
    echo "Supabase DB 가 여러 개입니다 (haedong 등). Travel.with.Jaws 용 컨테이너 이름을 인자로 주세요:"; printf '  %s\n' "${found[@]}"; exit 1
  fi
  DBC="${found[0]}"
fi
echo "  $DBC"

NET=$($DOCKER inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' "$DBC" | head -1)
PW=$($DOCKER inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$DBC" | sed -n 's/^POSTGRES_PASSWORD=//p' | head -1)
[ -n "$PW" ] || { echo "POSTGRES_PASSWORD 를 컨테이너에서 찾지 못했습니다"; exit 1; }
URL="postgresql://postgres:${PW}@${DBC}:5432/postgres"

run_psql_container() {
  $DOCKER run --rm -i --network "$NET" -e DATABASE_URL="$URL" -v "$REPO/db:/db:ro" postgres:16 "$@"
}

say "마이그레이션 ${DRY_RUN:+(미리보기)}"
if [ -n "${DRY_RUN:-}" ]; then run_psql_container bash /db/migrate.sh --dry-run; else run_psql_container bash /db/migrate.sh; fi

say "API(PostgREST) 노출 스키마 확인"
REST=$($DOCKER ps --format '{{.Names}}' | grep -E "supabase-rest" | grep -E "$(echo "$DBC" | sed -E 's/^supabase-db-?//')" | head -1 || true)
[ -n "$REST" ] || REST=$($DOCKER ps --format '{{.Names}}' | grep -E "supabase-rest" | head -1 || true)
if [ -n "$REST" ]; then
  SCHEMAS=$($DOCKER inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$REST" | sed -n 's/^PGRST_DB_SCHEMAS=//p')
  if echo ",$SCHEMAS," | grep -q ",trip,"; then echo "  trip 노출됨 ($SCHEMAS)"
  else
    echo "  ⚠ trip 이 노출되지 않았습니다 (현재: ${SCHEMAS:-없음})"
    echo "    Coolify → Supabase 서비스 → Environment Variables → PGRST_DB_SCHEMAS 에 ,trip 추가 → Redeploy"
  fi
else
  echo "  supabase-rest 컨테이너를 찾지 못했습니다. PGRST_DB_SCHEMAS 에 trip 이 있는지 Coolify 에서 확인하세요."
fi

say "다음 단계"
cat <<'EOF'
  운영자 등록 (편집 콘솔 로그인 줄 생성):
    bash deploy/minipc/add-staff.sh "이름" product,editor 로그인아이디
  출력된 줄을 Coolify 허브 앱의 CONSOLE_USERS 에 넣고 Redeploy
EOF
