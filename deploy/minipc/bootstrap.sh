#!/usr/bin/env bash
# Travel.with.Jaws 미니PC 원클릭 설치 (Coolify API)
#
# 작업 PC PowerShell 에서:
#   $OutputEncoding = [Text.Encoding]::UTF8
#   Get-Content -LiteralPath "<저장소>\deploy\minipc\bootstrap.sh" -Raw | ssh keymedi@192.168.0.202 "COOLIFY_TOKEN=<토큰> bash -s"
# 미니PC 에서 직접:
#   COOLIFY_TOKEN=<토큰> bash deploy/minipc/bootstrap.sh
#
# 하는 일 (여러 번 실행해도 안전: 이미 있으면 재사용)
#   1) Coolify 서버·프로젝트·GitHub 앱 확인
#   2) Supabase 서비스(travel-supabase) 생성 → API 에 trip 스키마 노출 → 시작·대기
#   3) 허브 앱(travelwithjaws-hub) 생성 (GitHub main 푸시 시 자동 배포)
#   4) 환경변수: Supabase 내부 주소·키, DB 주소(시작 시 마이그레이션), 콘솔 로그인
#   5) 배포 → 상태 확인 주소 응답 대기
#   6) Cloudflare Tunnel 설정 상태 안내
# 비밀번호·키는 화면 마지막 요약과 ~/travelwithjaws-secrets.txt(권한 600)에만 남긴다.
set -euo pipefail

COOLIFY_URL="${COOLIFY_URL:-http://localhost:8000}"
TOKEN="${COOLIFY_TOKEN:?COOLIFY_TOKEN 이 필요합니다 (Coolify → Keys & Tokens → API tokens, 권한 root)}"
PROJECT_NAME="${PROJECT_NAME:-keymedi}"
ENV_NAME="${ENV_NAME:-production}"
REPO="${REPO:-k710922-a11y/travelwithjaws}"
BRANCH="${BRANCH:-main}"
DOMAIN="${DOMAIN:-https://travel.jawsweb.site}"
SVC_NAME="${SVC_NAME:-travel-supabase}"
APP_NAME="${APP_NAME:-travelwithjaws-hub}"
STAFF_NAME="${STAFF_NAME:-Jungsoo}"
STAFF_LOGIN="${STAFF_LOGIN:-jungsoo}"
SECRETS_FILE="${SECRETS_FILE:-$HOME/travelwithjaws-secrets.txt}"
WAIT_SVC="${WAIT_SVC:-900}"   # Supabase 첫 실행은 이미지 내려받기로 몇 분 걸림
PROXY_BASE="${PROXY_BASE:-http://localhost}"   # 미니PC 의 Coolify 프록시(Traefik)

say()  { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m⚠\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
command -v curl >/dev/null || die "curl 이 없습니다"
command -v python3 >/dev/null || die "python3 이 없습니다"

# api METHOD PATH [JSON] → 결과를 전역 BODY, CODE 에 담는다 (하위 셸을 쓰지 않음)
api() {
  local m="$1" p="$2" d="${3:-}" out
  out=$(mktemp)
  if [ -n "$d" ]; then
    CODE=$(curl -sS -o "$out" -w '%{http_code}' -X "$m" "$COOLIFY_URL/api/v1$p" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" --data "$d" || echo 000)
  else
    CODE=$(curl -sS -o "$out" -w '%{http_code}' -X "$m" "$COOLIFY_URL/api/v1$p" \
      -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" || echo 000)
  fi
  BODY=$(cat "$out"); rm -f "$out"
}
# jget JSON 파이썬식 → 값
jget() { python3 -c "import json,sys; d=json.loads(sys.argv[1] or 'null'); print(eval(sys.argv[2]))" "$1" "$2"; }
jstr() { python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1"; }

# ─────────────────────────────────────────────────────────────
say "1. Coolify 확인"
api GET /version; v=$BODY; [ "$CODE" = 200 ] || die "API 접속 실패 (HTTP $CODE). 토큰 또는 Settings → API Access 를 확인하세요: $v"
ok "Coolify $v"

api GET /servers; servers=$BODY
SERVER_UUID=$(jget "$servers" "next((s['uuid'] for s in d if s.get('name')=='localhost' or s.get('ip') in ('host.docker.internal','localhost','127.0.0.1')), d[0]['uuid'] if d else '')")
[ -n "$SERVER_UUID" ] || die "서버를 찾지 못했습니다"
ok "서버 $SERVER_UUID"

api GET /projects; projects=$BODY
PROJECT_UUID=$(jget "$projects" "next((p['uuid'] for p in d if p['name']=='$PROJECT_NAME'), '')")
[ -n "$PROJECT_UUID" ] || die "프로젝트 '$PROJECT_NAME' 이 없습니다. 있는 프로젝트: $(jget "$projects" "', '.join(p['name'] for p in d)")"
ok "프로젝트 $PROJECT_NAME / $ENV_NAME"

api GET /github-apps; apps=$BODY
GH_APP_UUID="${GITHUB_APP_UUID:-$(jget "$apps" "(lambda a: a[0]['uuid'] if len(a)==1 else '')([x for x in d if not x.get('is_public')])")}"
if [ -z "$GH_APP_UUID" ]; then
  warn "GitHub 앱이 여러 개이거나 없습니다:"; jget "$apps" "'\n'.join(f\"    {x['uuid']}  {x['name']}  public={x.get('is_public')}\" for x in d)"
  die "GITHUB_APP_UUID=<uuid> 를 붙여 다시 실행하세요"
fi
GH_APP_ID=$(jget "$apps" "next(x['id'] for x in d if x['uuid']=='$GH_APP_UUID')")
ok "GitHub 앱 $(jget "$apps" "next(x['name'] for x in d if x['uuid']=='$GH_APP_UUID')")"

api GET "/github-apps/$GH_APP_ID/repositories"; repos=$BODY
if [ "$CODE" = 200 ]; then
  has=$(jget "$repos" "any(r.get('full_name','').lower()=='$REPO'.lower() for r in (d.get('repositories', d) if isinstance(d, dict) else d))")
  if [ "$has" != "True" ]; then
    warn "GitHub 앱이 $REPO 에 접근할 수 없습니다."
    echo "    GitHub → Settings → Applications → Installed GitHub Apps → (Coolify 앱) → Configure → Repository access 에 travelwithjaws 추가 후 다시 실행"
    exit 2
  fi
  ok "저장소 접근 확인: $REPO"
else
  warn "저장소 목록을 확인하지 못했습니다 (HTTP $CODE). 계속 진행합니다."
fi

# ─────────────────────────────────────────────────────────────
say "2. Supabase ($SVC_NAME)"
api GET /services; svcs=$BODY
SVC_UUID=$(jget "$svcs" "next((s['uuid'] for s in d if s.get('name')=='$SVC_NAME'), '')")
if [ -z "$SVC_UUID" ]; then
  body=$(python3 -c "import json; print(json.dumps({'type':'supabase','name':'$SVC_NAME','project_uuid':'$PROJECT_UUID','environment_name':'$ENV_NAME','server_uuid':'$SERVER_UUID','instant_deploy':False,'connect_to_docker_network':True,'description':'Travel.with.Jaws DB/API'}))")
  api POST /services "$body"; r=$BODY; [ "$CODE" = 201 ] || [ "$CODE" = 200 ] || die "Supabase 생성 실패 (HTTP $CODE): $r"
  SVC_UUID=$(jget "$r" "d['uuid']"); ok "생성: $SVC_UUID"
else
  ok "기존 서비스 사용: $SVC_UUID"
fi

api GET "/services/$SVC_UUID/envs"; envs=$BODY
envval() { jget "$envs" "next((e.get('real_value') or e.get('value') or '' for e in d if e['key']=='$1'), '')"; }
cur=$(envval PGRST_DB_SCHEMAS); SCHEMA_CHANGED=0
if echo ",$cur," | grep -q ",trip,"; then ok "API 노출 스키마에 trip 있음"
else
  new="${cur:-public,storage,graphql_public}"; new="${new%,},trip"
  api PATCH "/services/$SVC_UUID/envs" "{\"key\":\"PGRST_DB_SCHEMAS\",\"value\":\"$new\"}"
  if [ "$CODE" != 201 ] && [ "$CODE" != 200 ]; then api POST "/services/$SVC_UUID/envs" "{\"key\":\"PGRST_DB_SCHEMAS\",\"value\":\"$new\"}"; fi
  [ "$CODE" = 201 ] || [ "$CODE" = 200 ] || die "PGRST_DB_SCHEMAS 설정 실패 (HTTP $CODE)"
  ok "API 노출 스키마: $new"; SCHEMA_CHANGED=1
fi

api GET "/services/$SVC_UUID"; status=$(jget "$BODY" "d.get('status','')")
if [[ "$status" != running* ]]; then api GET "/services/$SVC_UUID/start"; ok "시작 요청"
elif [ "$SCHEMA_CHANGED" = 1 ]; then api GET "/services/$SVC_UUID/restart"; ok "스키마 반영을 위해 재시작"
else ok "이미 실행 중"; fi
printf '  Supabase 준비 대기'
t=0
while :; do
  api GET "/services/$SVC_UUID"; status=$(jget "$BODY" "d.get('status','')")
  [[ "$status" == running:healthy ]] && break
  [ $t -ge "$WAIT_SVC" ] && { echo; warn "아직 $status — 계속 진행합니다 (허브는 시작 시 DB 를 최대 90초 기다림)"; break; }
  printf '.'; sleep 10; t=$((t+10))
done
echo; ok "상태 $status"

api GET "/services/$SVC_UUID/envs"; envs=$BODY
PG_PASS=$(envval SERVICE_PASSWORD_POSTGRES)
ANON=$(envval SERVICE_SUPABASEANON_KEY)
SERVICE_KEY=$(envval SERVICE_SUPABASESERVICE_KEY)
[ -n "$PG_PASS" ] && [ -n "$ANON" ] && [ -n "$SERVICE_KEY" ] || die "Supabase 키를 읽지 못했습니다 (SERVICE_PASSWORD_POSTGRES / SERVICE_SUPABASEANON_KEY / SERVICE_SUPABASESERVICE_KEY)"
SUPA_URL="http://supabase-kong-$SVC_UUID:8000"
DB_URL="postgresql://postgres:$PG_PASS@supabase-db-$SVC_UUID:5432/postgres"
ok "키 확인 (내부 주소 $SUPA_URL)"

# ─────────────────────────────────────────────────────────────
say "3. 허브 앱 ($APP_NAME)"
api GET /applications; allapps=$BODY
APP_UUID=$(jget "$allapps" "next((a['uuid'] for a in d if a.get('name')=='$APP_NAME'), '')")
if [ -z "$APP_UUID" ]; then
  body=$(python3 - "$PROJECT_UUID" "$SERVER_UUID" "$ENV_NAME" "$GH_APP_UUID" "$REPO" "$BRANCH" "$DOMAIN" "$APP_NAME" <<'PY'
import json, sys
p, s, e, g, repo, br, dom, name = sys.argv[1:]
print(json.dumps({
  "project_uuid": p, "server_uuid": s, "environment_name": e, "github_app_uuid": g,
  "git_repository": repo, "git_branch": br, "build_pack": "dockerfile",
  "base_directory": "/", "dockerfile_location": "/Dockerfile", "ports_exposes": "3000",
  "name": name, "description": "Travel.with.Jaws 웹허브 (main 푸시 시 자동 배포)",
  "domains": dom, "autogenerate_domain": False, "is_auto_deploy_enabled": True,
  "health_check_enabled": True, "health_check_path": "/api/health", "health_check_port": "3000",
  "health_check_start_period": 90, "connect_to_docker_network": True, "instant_deploy": False,
}))
PY
)
  api POST /applications/private-github-app "$body"; r=$BODY
  [ "$CODE" = 201 ] || [ "$CODE" = 200 ] || die "허브 앱 생성 실패 (HTTP $CODE): $r"
  APP_UUID=$(jget "$r" "d['uuid']"); ok "생성: $APP_UUID"
else
  ok "기존 앱 사용: $APP_UUID"
fi

# ─────────────────────────────────────────────────────────────
say "4. 환경변수"
api GET "/applications/$APP_UUID/envs"; aenvs=$BODY
aval() { jget "$aenvs" "next((e.get('real_value') or e.get('value') or '' for e in d if e['key']=='$1' and not e.get('is_preview')), '')"; }

CONSOLE_USERS=$(aval CONSOLE_USERS); CONSOLE_STAFF=$(aval CONSOLE_STAFF); NEW_LOGIN=""
if [ -z "$CONSOLE_USERS" ]; then
  STAFF_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
  PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(15))")
  CONSOLE_USERS="$STAFF_LOGIN:$PASS:$STAFF_ID"
  CONSOLE_STAFF="$STAFF_ID|$STAFF_NAME|product,editor"
  NEW_LOGIN="$STAFF_LOGIN / $PASS"
fi

setenv() { # key value
  local k="$1" v="$2" j
  j=$(python3 -c "import json,sys; print(json.dumps({'key':sys.argv[1],'value':sys.argv[2],'is_preview':False}))" "$k" "$v")
  api PATCH "/applications/$APP_UUID/envs" "$j"
  if [ "$CODE" != 201 ] && [ "$CODE" != 200 ]; then api POST "/applications/$APP_UUID/envs" "$j"; fi
  [ "$CODE" = 201 ] || [ "$CODE" = 200 ] || die "$k 설정 실패 (HTTP $CODE)"
  ok "$k"
}
setenv SUPABASE_URL "$SUPA_URL"
setenv SUPABASE_ANON_KEY "$ANON"
setenv SUPABASE_SERVICE_ROLE_KEY "$SERVICE_KEY"
setenv DATABASE_URL "$DB_URL"
setenv CONSOLE_USERS "$CONSOLE_USERS"
setenv CONSOLE_STAFF "$CONSOLE_STAFF"
setenv NEXT_PUBLIC_BRAND "Travel.with.Jaws"
setenv NEXT_PUBLIC_SITE_URL "$DOMAIN"

# ─────────────────────────────────────────────────────────────
say "5. 배포"
api GET "/deploy?uuid=$APP_UUID&force=false"; r=$BODY; [ "$CODE" = 200 ] || die "배포 요청 실패 (HTTP $CODE): $r"
ok "배포 요청 — 첫 빌드는 3~6분 걸립니다"
printf '  허브 응답 대기'
t=0; HEALTH=""; HOK=""
while [ $t -lt 900 ]; do
  api GET "/applications/$APP_UUID"; st=$(jget "$BODY" "d.get('status','')")
  if [[ "$st" == running* ]]; then
    HEALTH=$(curl -s -m 5 -H "Host: ${DOMAIN#https://}" "$PROXY_BASE/api/health" || true)
    HOK=$(python3 -c "import json,sys
try: d=json.loads(sys.argv[1]); print('db' if d.get('ok') and d.get('db')=='up' else ('ok' if d.get('ok') else ''))
except Exception: print('')" "$HEALTH")
    [ -n "$HOK" ] && break
  fi
  [[ "$st" == exited* ]] && [ $t -gt 300 ] && break
  printf '.'; sleep 15; t=$((t+15))
done
echo
if [ "$HOK" = db ]; then ok "허브 정상, DB 연결됨: $HEALTH"
elif [ "$HOK" = ok ]; then warn "허브는 떴지만 DB 응답이 다릅니다: $HEALTH"
else warn "아직 확인되지 않았습니다 (상태: ${st:-?}). Coolify → $APP_NAME → Deployments 로그를 확인하세요."; fi

# ─────────────────────────────────────────────────────────────
say "6. Cloudflare Tunnel"
host="${DOMAIN#https://}"
if [ -r /etc/cloudflared/config.yml ] || [ -r "$HOME/.cloudflared/config.yml" ]; then
  cfg=$( [ -r /etc/cloudflared/config.yml ] && echo /etc/cloudflared/config.yml || echo "$HOME/.cloudflared/config.yml")
  if grep -q "$host" "$cfg" || grep -qE 'hostname: *"?\*\.jawsweb\.site' "$cfg"; then ok "로컬 설정($cfg)에 $host 경로 있음"
  else warn "로컬 터널 설정($cfg)에 $host 가 없습니다 — haedong 과 같은 서비스로 추가가 필요합니다"; grep -nE 'hostname|service' "$cfg" | head -12 | sed 's/^/    /'; fi
else
  echo "  터널이 Cloudflare 대시보드에서 관리되는 방식입니다. Zero Trust → Tunnels 에서 $host 를 haedong.jawsweb.site 와 같은 서비스로 추가해야 합니다."
fi
code=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "$DOMAIN/api/health" || true)
[ "$code" = 200 ] && ok "외부 접속 확인: $DOMAIN" || warn "외부 주소 아직 응답 없음 (HTTP ${code:-없음})"

# ─────────────────────────────────────────────────────────────
umask 077
{
  echo "# Travel.with.Jaws ($(date '+%F %T'))"
  echo "COOLIFY_SUPABASE_SERVICE=$SVC_UUID"
  echo "COOLIFY_HUB_APP=$APP_UUID"
  echo "SUPABASE_URL(내부)=$SUPA_URL"
  [ -n "$NEW_LOGIN" ] && echo "CONSOLE_LOGIN=$NEW_LOGIN"
} >> "$SECRETS_FILE"

say "완료"
echo "  허브:   $DOMAIN"
echo "  콘솔:   $DOMAIN/console"
if [ -n "$NEW_LOGIN" ]; then echo "  콘솔 로그인(새로 만듦): $NEW_LOGIN"; echo "  ※ 위 비밀번호는 $SECRETS_FILE 에도 저장했습니다 (권한 600)."
else echo "  콘솔 로그인: 기존 값 유지 (Coolify → $APP_NAME → Environment Variables → CONSOLE_USERS)"; fi
echo "  이후 배포: GitHub main 에 푸시하면 자동"
