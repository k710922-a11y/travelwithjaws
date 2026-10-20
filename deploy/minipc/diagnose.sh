#!/usr/bin/env bash
# Travel.with.Jaws - read-only diagnosis on the mini PC (changes nothing).
# ASCII only (see bootstrap.sh). Secrets (JWTs, passwords, keys) are masked before printing.
#
# From the work PC (PowerShell):
#   Get-Content -LiteralPath "<repo>\deploy\minipc\diagnose.sh" -Raw | ssh keymedi@192.168.0.202 "COOLIFY_TOKEN='<token>' bash -s"
set -uo pipefail
COOLIFY_URL="${COOLIFY_URL:-http://localhost:8000}"
TOKEN="${COOLIFY_TOKEN:?COOLIFY_TOKEN is required}"
TOKEN=$(printf '%s' "$TOKEN" | tr -d '[:space:]\r' | sed $'s/^\xef\xbb\xbf//'); TOKEN="${TOKEN#\'}"; TOKEN="${TOKEN%\'}"
SVC_NAME="${SVC_NAME:-travel-supabase}"
APP_NAME="${APP_NAME:-travelwithjaws-hub}"
LINES="${LINES:-40}"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

say() { printf '\n== %s\n' "$*"; }
get() { curl -s -m 20 -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" "$COOLIFY_URL/api/v1$1"; }

# collect secret values to mask (service + app env values whose key looks secret)
get /services > "$WORK/services.json"
SVC_UUID=$(python3 -c "import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: d=[]
print(next((s['uuid'] for s in d if s.get('name')==sys.argv[2]),''))" "$WORK/services.json" "$SVC_NAME")
get /applications > "$WORK/apps.json"
APP_UUID=$(python3 -c "import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: d=[]
print(next((s['uuid'] for s in d if s.get('name')==sys.argv[2]),''))" "$WORK/apps.json" "$APP_NAME")
[ -n "$SVC_UUID" ] && get "/services/$SVC_UUID/envs" > "$WORK/svc_env.json"
[ -n "$APP_UUID" ] && get "/applications/$APP_UUID/envs" > "$WORK/app_env.json"
python3 - "$WORK" <<'PY' > "$WORK/mask.txt"
import json, sys, os, re
out=set()
for f in ("svc_env.json","app_env.json"):
    p=os.path.join(sys.argv[1],f)
    try: d=json.load(open(p))
    except Exception: continue
    for e in d if isinstance(d,list) else []:
        k=str(e.get('key','')); v=str(e.get('value') or e.get('real_value') or '')
        if re.search(r'PASS|KEY|SECRET|TOKEN|JWT|CONSOLE_USERS|DATABASE_URL', k, re.I) and len(v) >= 6:
            out.add(v)
            for part in re.split(r'[:;@/|]', v):
                if len(part) >= 12: out.add(part)
for v in sorted(out, key=len, reverse=True): print(v)
PY
mask() { python3 -c "
import sys, re
masks=[l.rstrip('\n') for l in open(sys.argv[1]) if l.strip()]
for line in sys.stdin:
    for m in masks: line=line.replace(m,'***')
    line=re.sub(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_.-]+','***JWT***',line)
    line=re.sub(r'(?i)(password[\"=: ]+)[^ \"&,]+',r'\1***',line)
    sys.stdout.write(line)
" "$WORK/mask.txt"; }

say "Coolify"
echo "  version: $(get /version)"
echo "  service $SVC_NAME: ${SVC_UUID:-NOT FOUND}"
echo "  app $APP_NAME: ${APP_UUID:-NOT FOUND}"

if [ -n "$SVC_UUID" ]; then
  say "Supabase sub-containers (Coolify view)"
  get "/services/$SVC_UUID" | python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception as e: print('  (unreadable)', e); sys.exit()
print('  overall:', d.get('status'))
for grp in ('applications','databases'):
    for a in d.get(grp) or []:
        print('  %-28s %-22s %s' % (a.get('name'), a.get('status'), a.get('image','')))"
fi

say "Docker"
DOCKER=""
if docker ps >/dev/null 2>&1; then DOCKER=docker
elif sudo -n docker ps >/dev/null 2>&1; then DOCKER="sudo -n docker"; fi
if [ -z "$DOCKER" ]; then
  echo "  no docker access for $(whoami) without a password."
  echo "  (optional, once on the mini PC: sudo usermod -aG docker $(whoami)  then log in again)"
else
  echo "  containers for this project:"
  $DOCKER ps -a --format '  {{.Names}}\t{{.Status}}' | grep -E "${SVC_UUID:-none}|${APP_UUID:-none}" || echo "  (none found - Coolify never created them)"
  for c in $($DOCKER ps -a --format '{{.Names}}' | grep -E "${SVC_UUID:-none}|${APP_UUID:-none}"); do
    st=$($DOCKER inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$c" 2>/dev/null)
    case "$st" in running\ healthy|running\ ) continue;; esac
    say "logs: $c ($st)"
    $DOCKER logs --tail "$LINES" "$c" 2>&1 | mask | sed 's/^/  /'
  done
  if [ -n "$SVC_UUID" ]; then
    say "Supabase: compose files Coolify generated"
    ls -la "/data/coolify/services/$SVC_UUID" 2>&1 | sed 's/^/  /' | head -15
    say "Supabase: last start attempts (Coolify activity log)"
    $DOCKER exec coolify-db psql -U coolify -d coolify -At -F ' | ' -c "select id, created_at, coalesce(properties->>'status',''), right(regexp_replace(coalesce(description,''), '\\s+', ' ', 'g'), 2500) from activity_log where properties::text like '%$SVC_UUID%' or coalesce(description,'') like '%$SVC_UUID%' order by id desc limit 3" 2>&1 | mask | fold -w 300 | sed 's/^/  /'
    say "Coolify app log: recent errors"
    $DOCKER logs --since 90m coolify 2>&1 | grep -iE "error|exception|fail" | grep -v -i "deprecat" | tail -15 | mask | cut -c1-300 | sed 's/^/  /'
  fi
  say "networks (hub must share one with supabase-db)"
  for c in $($DOCKER ps -a --format '{{.Names}}' | grep -E "^supabase-db-${SVC_UUID:-none}$|^${APP_UUID:-none}"); do
    echo "  $c: $($DOCKER inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$c" 2>/dev/null)"
  done
  say "disk / memory"
  df -h / /var/lib/docker 2>/dev/null | sed 's/^/  /'
  free -h | sed 's/^/  /'
fi

if [ -n "$APP_UUID" ]; then
  say "hub: latest deployment log (Coolify)"
  get "/deployments/applications/$APP_UUID?skip=0&take=1" | python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception as e: print('  (unreadable)', e); sys.exit()
deps=d.get('deployments') if isinstance(d,dict) else d
if not isinstance(deps,list) or not deps: print('  (no deployment list):', str(d)[:300]); sys.exit()
x=deps[0]; print('  status:', x.get('status'), ' commit:', str(x.get('commit',''))[:8])
logs=x.get('logs') or '[]'
try: logs=json.loads(logs)
except Exception: logs=[{'output':str(logs)}]
lines=[ln for l in logs for ln in str(l.get('output','')).splitlines() if ln.strip() and 'Healthcheck logs' not in ln and not ln.startswith('[{"Start')]
for l in lines[-int(sys.argv[1])-30:]: print('  ', l.rstrip()[:300])" "$LINES" | mask
  say "hub: container log (Coolify)"
  get "/applications/$APP_UUID/logs?lines=$LINES" | python3 -c "import json,sys
try: d=json.load(sys.stdin); print(d.get('logs', d) if isinstance(d,dict) else d)
except Exception as e: print('  (unreadable)', e)" | mask | sed 's/^/  /'
fi
echo
echo "== end (nothing was changed)"
exit 0
