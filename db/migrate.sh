#!/usr/bin/env bash
# 운영 DB 마이그레이션: 아직 적용하지 않은 migrations/*.sql 만 번호 순서대로, 파일마다 한 트랜잭션으로 적용한다.
# 이미 적용한 파일이 바뀌었으면(체크섬 불일치) 멈춘다 — 적용된 파일은 고치지 말고 새 번호 파일을 추가할 것.
#
# 사용: DATABASE_URL=postgresql://postgres:비밀번호@호스트:5432/postgres ./db/migrate.sh [--dry-run]
set -euo pipefail
cd "$(dirname "$0")"
: "${DATABASE_URL:?DATABASE_URL 이 필요합니다}"
DRY="${1:-}"
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -X -q)

"${PSQL[@]}" -c "create table if not exists public.travelwithjaws_migrations (
  file text primary key, sha256 text not null, applied_at timestamptz not null default now())" >/dev/null

applied=0
for f in $(ls migrations/*.sql | sort); do
  name=$(basename "$f"); sum=$(sha256sum "$f" | cut -d' ' -f1)
  prev=$("${PSQL[@]}" -At -c "select sha256 from public.travelwithjaws_migrations where file = '$name'")
  if [ -n "$prev" ]; then
    if [ "$prev" != "$sum" ]; then
      echo "중단: $name 이 적용 후 바뀌었습니다. 적용된 파일은 수정하지 말고 새 번호 파일을 만드세요." >&2; exit 1
    fi
    echo "건너뜀  $name (적용됨)"; continue
  fi
  if [ "$DRY" = "--dry-run" ]; then echo "적용 예정 $name"; continue; fi
  echo "적용    $name"
  { echo "begin;"; cat "$f"; echo; echo "insert into public.travelwithjaws_migrations(file, sha256) values ('$name', '$sum');"; echo "commit;"; } \
    | "${PSQL[@]}" -f - >/dev/null
  applied=$((applied + 1))
done
echo "완료: 새로 적용 $applied개"
# PostgREST 가 새 뷰·함수를 바로 알도록 스키마 캐시 새로고침 요청
[ "$DRY" = "--dry-run" ] || "${PSQL[@]}" -c "notify pgrst, 'reload schema'" >/dev/null || true
