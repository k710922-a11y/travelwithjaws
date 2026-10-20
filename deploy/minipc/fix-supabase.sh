#!/usr/bin/env bash
# Travel.with.Jaws - repair the Coolify Supabase service on the mini PC.
# ASCII only (see bootstrap.sh).
#
# Why: Docker Hub stopped serving minio/mc (and minio/minio), so Coolify's Supabase template
# cannot pull the image of its "minio-createbucket" helper and the whole service never starts.
# What it does (only on the travel-supabase service; nothing else is touched):
#   1) find a client image that still pulls and has /bin/sh + mc
#   2) swap "image: minio/mc..." in the service compose for it (via Coolify API) and keep a backup
#   3) start the service and wait until the DB container is up
#   4) print the tail of the hub's last build log (incl. debug lines) so the build error can be read
#
# From the work PC (PowerShell):
#   Get-Content -LiteralPath "<repo>\deploy\minipc\fix-supabase.sh" -Raw | ssh keymedi@192.168.0.202 "COOLIFY_TOKEN='<token>' bash -s"
set -uo pipefail
COOLIFY_URL="${COOLIFY_URL:-http://localhost:8000}"
TOKEN="${COOLIFY_TOKEN:?COOLIFY_TOKEN is required}"
TOKEN=$(printf '%s' "$TOKEN" | tr -d '[:space:]\r' | sed $'s/^\xef\xbb\xbf//'); TOKEN="${TOKEN#\'}"; TOKEN="${TOKEN%\'}"
SVC_NAME="${SVC_NAME:-travel-supabase}"
APP_NAME="${APP_NAME:-travelwithjaws-hub}"
WAIT_SVC="${WAIT_SVC:-900}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/travelwithjaws-backup}"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

say()  { printf '\n== %s\n' "$*"; }
ok()   { printf '  [ok] %s\n' "$*"; }
warn() { printf '  [!] %s\n' "$*"; }
die()  { printf '  [FAIL] %s\n' "$*" >&2; exit 1; }
api() {
  local m="$1" p="$2" d="${3:-}"
  if [ -n "$d" ]; then
    CODE=$(curl -s -m 60 -o "$WORK/body" -w '%{http_code}' -X "$m" "$COOLIFY_URL/api/v1$p" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" --data @"$d" || echo 000)
  else
    CODE=$(curl -s -m 60 -o "$WORK/body" -w '%{http_code}' -X "$m" "$COOLIFY_URL/api/v1$p" -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" || echo 000)
  fi
  BODY=$(cat "$WORK/body" 2>/dev/null)
}
uuid_of() { python3 -c "import json,sys
try: d=json.loads(sys.argv[1])
except Exception: d=[]
print(next((s['uuid'] for s in d if s.get('name')==sys.argv[2]),''))" "$1" "$2"; }

DOCKER=""
if docker ps >/dev/null 2>&1; then DOCKER=docker; elif sudo -n docker ps >/dev/null 2>&1; then DOCKER="sudo -n docker"; fi
[ -n "$DOCKER" ] || die "no docker access for $(whoami)"

say "1. find the service"
api GET /services; SVC_UUID=$(uuid_of "$BODY" "$SVC_NAME"); [ -n "$SVC_UUID" ] || die "service $SVC_NAME not found"
ok "$SVC_NAME: $SVC_UUID"
api GET "/services/$SVC_UUID"; printf '%s' "$BODY" > "$WORK/svc.json"
python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('docker_compose_raw') or '')" "$WORK/svc.json" > "$WORK/compose.yml"
[ -s "$WORK/compose.yml" ] || die "could not read the service compose from the API"
mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"
BK="$BACKUP_DIR/supabase-compose-$(date +%Y%m%d-%H%M%S).yml"; cp "$WORK/compose.yml" "$BK"; chmod 600 "$BK"
ok "compose backed up: $BK"

CUR=$(grep -E '^\s*image:\s*["'\'']?(docker\.io/)?minio/mc' "$WORK/compose.yml" | head -1 | sed -E 's/^\s*image:\s*//; s/["'\'']//g')
MINIO_IMG=$(grep -E '^\s*image:\s*.*minio:' "$WORK/compose.yml" | grep -v '/mc' | head -1 | sed -E 's/^\s*image:\s*//; s/["'\'']//g')

say "2. bucket helper image"
if [ -z "$CUR" ]; then
  ok "compose no longer uses minio/mc"
  NEW=""
else
  echo "  current: $CUR (no longer on Docker Hub)"
  NEW=""
  for cand in ${MC_IMAGE:-} quay.io/minio/mc:latest "$MINIO_IMG" cgr.dev/chainguard/minio-client:latest-dev; do
    [ -n "$cand" ] || continue
    printf '  trying %s ... ' "$cand"
    if ! $DOCKER pull -q "$cand" >/dev/null 2>&1; then echo "cannot pull"; continue; fi
    if $DOCKER run --rm --entrypoint /bin/sh "$cand" -c 'command -v mc >/dev/null && mc --version >/dev/null' >/dev/null 2>&1; then
      echo "ok"; NEW="$cand"; break
    fi
    echo "no /bin/sh + mc"
  done
  [ -n "$NEW" ] || die "no working mc image found. Set MC_IMAGE=<image> and re-run."
  python3 - "$WORK/compose.yml" "$CUR" "$NEW" "$WORK/patch.json" <<'PY'
import sys, json, base64, re
p, cur, new, out = sys.argv[1:]
s = open(p).read()
s2 = re.sub(r'(^\s*image:\s*["\']?)' + re.escape(cur) + r'(["\']?\s*$)', lambda m: m.group(1) + new + m.group(2), s, flags=re.M)
assert s2 != s, "image line not replaced"
open(p + ".new", "w").write(s2)
json.dump({"docker_compose_raw": base64.b64encode(s2.encode()).decode()}, open(out, "w"))
PY
  [ $? = 0 ] || die "could not edit the compose"
  api PATCH "/services/$SVC_UUID" "$WORK/patch.json"
  [ "$CODE" = 200 ] || [ "$CODE" = 201 ] || die "compose update failed (HTTP $CODE): $BODY"
  api GET "/services/$SVC_UUID"
  if printf '%s' "$BODY" | python3 -c "import json,sys; c=json.load(sys.stdin).get('docker_compose_raw') or ''; sys.exit(0 if sys.argv[1] in c and 'image: minio/mc' not in c else 1)" "$NEW"; then
    ok "compose now uses $NEW"
  else
    # some Coolify versions take the raw text instead of base64
    python3 -c "import json,sys; json.dump({'docker_compose_raw': open(sys.argv[1]).read()}, open(sys.argv[2],'w'))" "$WORK/compose.yml.new" "$WORK/patch.json"
    api PATCH "/services/$SVC_UUID" "$WORK/patch.json"
    api GET "/services/$SVC_UUID"
    printf '%s' "$BODY" | python3 -c "import json,sys; c=json.load(sys.stdin).get('docker_compose_raw') or ''; sys.exit(0 if sys.argv[1] in c else 1)" "$NEW" \
      || die "Coolify did not keep the new image. In Coolify > $SVC_NAME > Edit Compose File, change '$CUR' to '$NEW', Save, Start."
    ok "compose now uses $NEW"
  fi
fi

say "3. start Supabase"
api POST "/services/$SVC_UUID/start"; { [ "$CODE" = 405 ] || [ "$CODE" = 404 ]; } && api GET "/services/$SVC_UUID/start"
case "$CODE" in 200|201|202) ok "start requested";; *) die "start failed (HTTP $CODE): $BODY";; esac
printf '  waiting (first start pulls ~15 images)'
t=0; st=""
while [ $t -lt "$WAIT_SVC" ]; do
  sleep 15; t=$((t+15)); printf '.'
  db=$($DOCKER ps --format '{{.Names}} {{.Status}}' | grep "supabase-db-$SVC_UUID" || true)
  api GET "/services/$SVC_UUID"; st=$(printf '%s' "$BODY" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('status',''))
except Exception: print('')")
  [[ "$st" == running:healthy ]] && break
  if [ -z "$db" ] && [ $t -ge 120 ]; then
    # nothing created after 2 minutes: show the newest start log line with an error
    $DOCKER exec coolify-db psql -U coolify -d coolify -At -c "select coalesce(properties->>'status','') from activity_log where properties::text like '%$SVC_UUID%' order by id desc limit 1" 2>/dev/null | grep -q error && { echo; warn "start reported an error:"; \
      $DOCKER exec coolify-db psql -U coolify -d coolify -At -c "select right(description, 1500) from activity_log where properties::text like '%$SVC_UUID%' order by id desc limit 1" 2>/dev/null | grep -oE '"output":"[^"]*(rror|denied)[^"]*"' | head -5 | sed 's/^/    /'; break; }
  fi
done
echo
echo "  service status: ${st:-?}"
$DOCKER ps -a --format '  {{.Names}}\t{{.Status}}' | grep "$SVC_UUID" | sed -E "s/-$SVC_UUID//" || echo "  (no containers yet)"

say "4. hub: last build log (tail, incl. debug)"
api GET /applications; APP_UUID=$(uuid_of "$BODY" "$APP_NAME")
if [ -n "$APP_UUID" ]; then
  api GET "/deployments/applications/$APP_UUID?skip=0&take=1"
  printf '%s' "$BODY" | python3 -c "import json,sys,re
try: d=json.load(sys.stdin)
except Exception as e: print('  (unreadable)'); sys.exit()
deps=d.get('deployments') if isinstance(d,dict) else d
if not isinstance(deps,list) or not deps: print('  (no deployments)'); sys.exit()
x=deps[0]; print('  status:', x.get('status'))
try: logs=json.loads(x.get('logs') or '[]')
except Exception: logs=[]
out=[]
for l in logs:
    for line in str(l.get('output','')).splitlines():
        line=re.sub(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_.-]+','***',line)
        line=re.sub(r'(?i)(postgres(ql)?://[^:]+:)[^@]+@',r'\1***@',line)
        out.append(line[:240])
for line in out[-70:]: print('   ', line)"
fi
echo
echo "== end"
exit 0
