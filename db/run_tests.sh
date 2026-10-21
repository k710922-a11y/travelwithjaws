#!/usr/bin/env bash
# DB 규칙 시험: 빈 데이터베이스를 두 번 만들어 전체 시나리오를 실행하고, FAIL 이나 오류가 하나라도 있으면 실패로 끝난다.
# 사용: PGURL=postgresql://postgres:postgres@localhost:5432 ./db/run_tests.sh
#   PGURL 은 데이터베이스 이름 없이 (서버 주소까지만). 시험용 DB trip_test_a / trip_test_b 를 만들었다 지운다.
#   운영 DB 주소를 넣지 마세요 — 시험 데이터가 들어갑니다.
set -euo pipefail
cd "$(dirname "$0")"
PGURL="${PGURL:-postgresql://postgres:postgres@localhost:5432}"
MIG="$(ls migrations/*.sql | sort | tr '\n' ' ')"

run_suite() {
  local db="$1"; shift
  psql "$PGURL/postgres" -qc "drop database if exists $db" -qc "create database $db" >/dev/null 2>&1
  local out
  out=$(for f in $MIG "$@"; do psql "$PGURL/$db" -v ON_ERROR_STOP=1 -q -f "$f" 2>&1 || echo "ERROR: $f 실행 실패"; done)
  psql "$PGURL/postgres" -qc "drop database if exists $db" >/dev/null
  echo "$out" | grep -E "NOTICE:  (OK|FAIL)|ERROR" | sed 's/.*NOTICE:  //'
}

result=$( { run_suite trip_test_a seed/test_rules.sql seed/test_portal.sql seed/test_console.sql seed/test_demo.sql; run_suite trip_test_b seed/test_longform.sql; } )
echo "$result"
ok=$(grep -c "^OK" <<<"$result" || true)
bad=$(grep -cE "^FAIL|ERROR" <<<"$result" || true)
echo "----"
echo "통과 $ok · 실패 $bad"
[ "$bad" -eq 0 ] && [ "$ok" -ge 68 ]
