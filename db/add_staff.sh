#!/usr/bin/env bash
# 운영자 등록 + 편집 콘솔 로그인 줄 만들기
# 사용: DATABASE_URL=... ./db/add_staff.sh "이름" 역할[,역할] 로그인아이디
#   역할: product, editor, tech, partner, ops
# 출력된 CONSOLE_USERS 조각을 Coolify 환경변수에 ; 로 이어 붙인다. 비밀번호는 다시 볼 수 없으니 바로 보관할 것.
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL 이 필요합니다}"
name="${1:?이름}"; roles="${2:?역할 (예: product 또는 editor,ops)}"; login="${3:?로그인 아이디 (영문)}"
case "$login" in *[!a-zA-Z0-9._-]*) echo "로그인 아이디는 영문·숫자·._- 만" >&2; exit 1;; esac
id=$(echo "insert into trip.staff(name, roles) values (:'n', :'r'::text[]) returning id;" \
  | psql "$DATABASE_URL" -X -At -q -v ON_ERROR_STOP=1 -v n="$name" -v r="{$roles}" | head -1)
pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 20)
echo "등록: $name ($roles) → $id"
echo
echo "CONSOLE_USERS 에 추가할 값:"
echo "$login:$pass:$id"
