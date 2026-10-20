#!/usr/bin/env bash
# Travel.with.Jaws - one-shot install on the mini PC via the Coolify API.
# ASCII only on purpose: Windows PowerShell 5.1 re-encodes piped text, which corrupts non-ASCII bytes.
#
# From the work PC (PowerShell):
#   Get-Content -LiteralPath "<repo>\deploy\minipc\bootstrap.sh" -Raw | ssh keymedi@192.168.0.202 "COOLIFY_TOKEN='<token>' bash -s"
# On the mini PC:
#   COOLIFY_TOKEN='<token>' bash deploy/minipc/bootstrap.sh
#
# Steps (safe to re-run; existing resources are reused):
#   1) check Coolify server / project / GitHub app
#   2) Supabase service (travel-supabase): create, expose the trip schema to the API, start, wait
#   3) hub app (travelwithjaws-hub): create from GitHub, auto-deploy on push to main
#   4) env vars: internal Supabase URL + keys, DATABASE_URL (migrations run on container start), console login
#   5) deploy and wait for /api/health
#   6) report the Cloudflare Tunnel setup
# Secrets are printed once at the end and appended to ~/travelwithjaws-secrets.txt (mode 600).
set -euo pipefail

COOLIFY_URL="${COOLIFY_URL:-http://localhost:8000}"
TOKEN="${COOLIFY_TOKEN:?COOLIFY_TOKEN is required (Coolify > Keys & Tokens > API tokens, permission root)}"
TOKEN=$(printf '%s' "$TOKEN" | tr -d '[:space:]\r' | sed $'s/^\xef\xbb\xbf//')   # strip spaces / CR / BOM picked up while copying
TOKEN="${TOKEN#\'}"; TOKEN="${TOKEN%\'}"; TOKEN="${TOKEN#\"}"; TOKEN="${TOKEN%\"}"   # and stray quotes
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
WAIT_SVC="${WAIT_SVC:-900}"   # first Supabase start pulls images (minutes)
PROXY_BASE="${PROXY_BASE:-http://localhost}"   # Coolify proxy (Traefik) on the mini PC

say()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m[!]\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m[FAIL] %s\033[0m\n' "$*" >&2; exit 1; }
command -v curl >/dev/null || die "curl not found"
command -v python3 >/dev/null || die "python3 not found"

# api METHOD PATH [JSON] -> sets globals BODY and CODE (no subshell, so CODE survives)
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
# jget JSON python-expression -> value
jget() { python3 -c "import json,sys; d=json.loads(sys.argv[1] or 'null'); print(eval(sys.argv[2]))" "$1" "$2"; }
jstr() { python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1"; }

# create_with_retry PATH JSON -> POST; if Coolify answers 422 "This field is not allowed",
# drop those fields and retry (Coolify versions differ). Dropped field names go to DROPPED.
create_with_retry() {
  local path="$1" body="$2" i bad
  DROPPED=""
  for i in 1 2 3 4; do
    api POST "$path" "$body"
    [ "$CODE" = 422 ] || return 0
    bad=$(python3 -c "import json,sys
try: e=json.loads(sys.argv[1]).get('errors',{})
except Exception: e={}
print(' '.join(k for k,v in e.items() if any('not allowed' in str(x) for x in (v if isinstance(v,list) else [v]))))" "$BODY")
    [ -n "$bad" ] || return 0
    DROPPED="$DROPPED $bad"
    body=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); [d.pop(k,None) for k in sys.argv[2].split()]; print(json.dumps(d))" "$body" "$bad")
  done
}

# ensure_network KIND UUID -> make sure the resource joins the predefined 'coolify' docker network
# (the hub reaches supabase-db / supabase-kong by container name). Sets NET_CHANGED=1 if it changed it.
ensure_network() {
  local kind="$1" uuid="$2" cur
  NET_CHANGED=0
  api GET "/$kind/$uuid"; cur=$(jget "$BODY" "str(d.get('connect_to_docker_network', ''))")
  [ "$cur" = "True" ] && { ok "$kind joins the coolify network"; return 0; }
  api PATCH "/$kind/$uuid" '{"connect_to_docker_network":true}'
  if [ "$CODE" = 200 ] || [ "$CODE" = 201 ]; then NET_CHANGED=1; ok "$kind now joins the coolify network"; return 0; fi
  warn "could not enable 'Connect To Predefined Network' via API (HTTP $CODE): $BODY"
  if [ "$kind" = services ]; then
    echo "    Coolify > $SVC_NAME > General (settings) > enable 'Connect To Predefined Network' > Save, then re-run"
  else
    echo "    Coolify > $APP_NAME > Advanced > enable 'Connect To Predefined Network' > Save, then re-run"
  fi
  exit 3
}

# ------------------------------------------------------------
say "1. Coolify"
api GET /version; v=$BODY
if [ "$CODE" != 200 ]; then
  echo "  API response: HTTP $CODE $v"
  case "$TOKEN" in *"|"*) shape="looks like id|secret (id ${TOKEN%%|*})";; *) shape="no '|' found - copy the whole token including the leading 'id|'";; esac
  echo "  token shape: ${#TOKEN} chars, $shape"
  hc=$(curl -s -o /dev/null -w '%{http_code}' "$COOLIFY_URL/api/health" || true)
  echo "  Coolify /api/health: HTTP $hc"
  case "$CODE" in
    401) die "token rejected: deleted, or only partly copied. Create a new token and pass the full 'id|secret' in single quotes." ;;
    403) die "API disabled or this IP not allowed: Settings > Advanced > API access = Enabled, leave Allowed API IPs empty." ;;
    *)   die "cannot reach the Coolify API (COOLIFY_URL=$COOLIFY_URL)." ;;
  esac
fi
ok "Coolify $v"

api GET /servers; servers=$BODY
SERVER_UUID=$(jget "$servers" "next((s['uuid'] for s in d if s.get('name')=='localhost' or s.get('ip') in ('host.docker.internal','localhost','127.0.0.1')), d[0]['uuid'] if d else '')")
[ -n "$SERVER_UUID" ] || die "no server found"
ok "server $SERVER_UUID"

api GET /projects; projects=$BODY
PROJECT_UUID=$(jget "$projects" "next((p['uuid'] for p in d if p['name']=='$PROJECT_NAME'), '')")
[ -n "$PROJECT_UUID" ] || die "project '$PROJECT_NAME' not found. Projects: $(jget "$projects" "', '.join(p['name'] for p in d)")"
ok "project $PROJECT_NAME / $ENV_NAME"

api GET /github-apps; apps=$BODY
GH_APP_UUID="${GITHUB_APP_UUID:-$(jget "$apps" "(lambda a: a[0]['uuid'] if len(a)==1 else '')([x for x in d if not x.get('is_public')])")}"
if [ -z "$GH_APP_UUID" ]; then
  warn "zero or several private GitHub apps:"; jget "$apps" "'\n'.join(f\"    {x['uuid']}  {x['name']}  public={x.get('is_public')}\" for x in d)"
  die "re-run with GITHUB_APP_UUID=<uuid>"
fi
GH_APP_ID=$(jget "$apps" "next(x['id'] for x in d if x['uuid']=='$GH_APP_UUID')")
ok "GitHub app $(jget "$apps" "next(x['name'] for x in d if x['uuid']=='$GH_APP_UUID')")"

api GET "/github-apps/$GH_APP_ID/repositories"; repos=$BODY
if [ "$CODE" = 200 ]; then
  has=$(jget "$repos" "any(r.get('full_name','').lower()=='$REPO'.lower() for r in (d.get('repositories', d) if isinstance(d, dict) else d))")
  if [ "$has" != "True" ]; then
    warn "the GitHub app cannot access $REPO."
    echo "    GitHub > Settings > Applications > Installed GitHub Apps > (Coolify app) > Configure > Repository access: add travelwithjaws, then re-run"
    exit 2
  fi
  ok "repository access: $REPO"
else
  warn "could not list repositories (HTTP $CODE); continuing"
fi

# ------------------------------------------------------------
say "2. Supabase ($SVC_NAME)"
api GET /services; svcs=$BODY
SVC_UUID=$(jget "$svcs" "next((s['uuid'] for s in d if s.get('name')=='$SVC_NAME'), '')")
if [ -z "$SVC_UUID" ]; then
  body=$(python3 -c "import json; print(json.dumps({'type':'supabase','name':'$SVC_NAME','project_uuid':'$PROJECT_UUID','environment_name':'$ENV_NAME','server_uuid':'$SERVER_UUID','instant_deploy':False,'connect_to_docker_network':True,'description':'Travel.with.Jaws DB/API'}))")
  create_with_retry /services "$body"; r=$BODY; [ "$CODE" = 201 ] || [ "$CODE" = 200 ] || die "Supabase create failed (HTTP $CODE): $r"
  [ -n "$DROPPED" ] && ok "retried without fields this Coolify rejects:$DROPPED"
  SVC_UUID=$(jget "$r" "d['uuid']"); ok "created: $SVC_UUID"
else
  ok "existing service: $SVC_UUID"
fi
ensure_network services "$SVC_UUID"; SVC_NET_CHANGED=$NET_CHANGED

api GET "/services/$SVC_UUID/envs"; envs=$BODY
envval() { jget "$envs" "next((e.get('real_value') or e.get('value') or '' for e in d if e['key']=='$1'), '')"; }
cur=$(envval PGRST_DB_SCHEMAS); SCHEMA_CHANGED=0
if echo ",$cur," | grep -q ",trip,"; then ok "trip schema already exposed"
else
  new="${cur:-public,storage,graphql_public}"; new="${new%,},trip"
  api PATCH "/services/$SVC_UUID/envs" "{\"key\":\"PGRST_DB_SCHEMAS\",\"value\":\"$new\"}"
  if [ "$CODE" != 201 ] && [ "$CODE" != 200 ]; then api POST "/services/$SVC_UUID/envs" "{\"key\":\"PGRST_DB_SCHEMAS\",\"value\":\"$new\"}"; fi
  [ "$CODE" = 201 ] || [ "$CODE" = 200 ] || die "setting PGRST_DB_SCHEMAS failed (HTTP $CODE)"
  ok "exposed schemas: $new"; SCHEMA_CHANGED=1
fi

api GET "/services/$SVC_UUID"; status=$(jget "$BODY" "d.get('status','')")
if [[ "$status" != running* ]]; then api GET "/services/$SVC_UUID/start"; ok "start requested"
elif [ "$SCHEMA_CHANGED" = 1 ] || [ "$SVC_NET_CHANGED" = 1 ]; then api GET "/services/$SVC_UUID/restart"; ok "restarted to apply schema / network changes"
else ok "already running"; fi
printf '  waiting for Supabase'
t=0
while :; do
  api GET "/services/$SVC_UUID"; status=$(jget "$BODY" "d.get('status','')")
  [[ "$status" == running:healthy ]] && break
  [ $t -ge "$WAIT_SVC" ] && { echo; warn "still $status - continuing (the hub waits up to 90s for the DB)"; break; }
  printf '.'; sleep 10; t=$((t+10))
done
echo; ok "status $status"

api GET "/services/$SVC_UUID/envs"; envs=$BODY
PG_PASS=$(envval SERVICE_PASSWORD_POSTGRES)
ANON=$(envval SERVICE_SUPABASEANON_KEY)
SERVICE_KEY=$(envval SERVICE_SUPABASESERVICE_KEY)
[ -n "$PG_PASS" ] && [ -n "$ANON" ] && [ -n "$SERVICE_KEY" ] || die "could not read Supabase keys (SERVICE_PASSWORD_POSTGRES / SERVICE_SUPABASEANON_KEY / SERVICE_SUPABASESERVICE_KEY) - token needs root or read:sensitive"
SUPA_URL="http://supabase-kong-$SVC_UUID:8000"
DB_URL="postgresql://postgres:$PG_PASS@supabase-db-$SVC_UUID:5432/postgres"
ok "keys read (internal URL $SUPA_URL)"

# ------------------------------------------------------------
say "3. Hub app ($APP_NAME)"
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
  "name": name, "description": "Travel.with.Jaws hub (auto-deploy on push to main)",
  "domains": dom, "autogenerate_domain": False, "is_auto_deploy_enabled": True,
  "health_check_enabled": True, "health_check_path": "/api/health", "health_check_port": "3000",
  "health_check_start_period": 90, "connect_to_docker_network": True, "instant_deploy": False,
}))
PY
)
  create_with_retry /applications/private-github-app "$body"; r=$BODY
  [ "$CODE" = 201 ] || [ "$CODE" = 200 ] || die "hub app create failed (HTTP $CODE): $r"
  [ -n "$DROPPED" ] && ok "retried without fields this Coolify rejects:$DROPPED"
  APP_UUID=$(jget "$r" "d['uuid']"); ok "created: $APP_UUID"
else
  ok "existing app: $APP_UUID"
fi
ensure_network applications "$APP_UUID"

# ------------------------------------------------------------
say "4. Environment variables"
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
  [ "$CODE" = 201 ] || [ "$CODE" = 200 ] || die "setting $k failed (HTTP $CODE)"
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

# ------------------------------------------------------------
say "5. Deploy"
api GET "/deploy?uuid=$APP_UUID&force=false"; r=$BODY; [ "$CODE" = 200 ] || die "deploy request failed (HTTP $CODE): $r"
ok "deploy queued - first build takes 3-6 minutes"
printf '  waiting for the hub'
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
if [ "$HOK" = db ]; then ok "hub healthy, DB connected: $HEALTH"
elif [ "$HOK" = ok ]; then warn "hub is up but DB check differs: $HEALTH"
else warn "not confirmed yet (status ${st:-?}). See Coolify > $APP_NAME > Deployments logs."; fi

# ------------------------------------------------------------
say "6. Cloudflare Tunnel"
host="${DOMAIN#https://}"
if [ -r /etc/cloudflared/config.yml ] || [ -r "$HOME/.cloudflared/config.yml" ]; then
  cfg=$( [ -r /etc/cloudflared/config.yml ] && echo /etc/cloudflared/config.yml || echo "$HOME/.cloudflared/config.yml")
  if grep -q "$host" "$cfg" || grep -qE 'hostname: *"?\*\.jawsweb\.site' "$cfg"; then ok "local tunnel config ($cfg) already routes $host"
  else warn "local tunnel config ($cfg) has no route for $host - add it like haedong"; grep -nE 'hostname|service' "$cfg" | head -12 | sed 's/^/    /'; fi
else
  echo "  TUNNEL=dashboard-managed: add public hostname $host in Cloudflare Zero Trust > Tunnels, same service as haedong.jawsweb.site"
fi
code=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "$DOMAIN/api/health" || true)
[ "$code" = 200 ] && ok "public URL OK: $DOMAIN" || warn "public URL not answering yet (HTTP ${code:-none})"

# ------------------------------------------------------------
umask 077
{
  echo "# Travel.with.Jaws ($(date '+%F %T'))"
  echo "COOLIFY_SUPABASE_SERVICE=$SVC_UUID"
  echo "COOLIFY_HUB_APP=$APP_UUID"
  echo "SUPABASE_URL_INTERNAL=$SUPA_URL"
  [ -n "$NEW_LOGIN" ] && echo "CONSOLE_LOGIN=$NEW_LOGIN"
} >> "$SECRETS_FILE"

say "Done"
echo "  hub:     $DOMAIN"
echo "  console: $DOMAIN/console"
if [ -n "$NEW_LOGIN" ]; then echo "  console login (new): $NEW_LOGIN"; echo "  (also saved to $SECRETS_FILE, mode 600)"
else echo "  console login: unchanged (Coolify > $APP_NAME > Environment Variables > CONSOLE_USERS)"; fi
echo "  next deploys: push to GitHub main"
