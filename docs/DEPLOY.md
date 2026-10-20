# 미니PC 배포 — travel.jawsweb.site

## 가장 빠른 방법: 원클릭 설치 (권장)

1. Coolify(http://192.168.0.202:8000) → **Keys & Tokens → API tokens** → 이름 `travelwithjaws`, 권한 **root** 로 토큰 생성 → 복사
   (Settings → Advanced(또는 Configuration)에서 **API Access** 가 꺼져 있으면 켭니다)
2. 작업 PC PowerShell 에 붙여 넣기 (`<토큰>` 만 바꿔서):

```powershell
Get-Content -LiteralPath "$HOME\Documents\[AI.프로젝트] 라이브.프로젝트\travelwithjaws\deploy\minipc\bootstrap.sh" -Raw | ssh keymedi@192.168.0.202 "COOLIFY_TOKEN='<토큰>' bash -s"
```
토큰은 `1|abc…` 처럼 가운데 `|` 가 있으므로 **작은따옴표로 감싸야** 합니다. 스크립트는 영문(ASCII)만 써서 PowerShell 인코딩 설정과 무관하게 동작합니다.

스크립트가 하는 일: Supabase(travel-supabase) 생성·시작 → API 에 `trip` 노출 → 허브 앱 생성(GitHub 자동 배포) →
환경변수(내부 DB·API 주소, 키, 콘솔 로그인) → 배포 → 상태 확인. 허브 컨테이너가 시작할 때 DB 마이그레이션을 스스로 적용합니다.
여러 번 실행해도 이미 만든 것은 재사용합니다. 마지막에 콘솔 로그인 정보가 나오고 미니PC `~/travelwithjaws-secrets.txt` 에도 저장됩니다.

남는 일: Cloudflare Tunnel 에 `travel.jawsweb.site` 공개 호스트 추가 (아래 1-5).

---

## 수동 설치 (참고)

GitHub `k710922-a11y/travelwithjaws` 의 `main` 에 푸시하면 Coolify 가 허브를 다시 빌드해 배포합니다.
haedong.jawsweb.site 와 같은 방식입니다. DB 는 Travel.with.Jaws 전용 Supabase 를 따로 둡니다.

```
GitHub main ──push──▶ GitHub Actions (DB 규칙 53건 · 합성기 · 허브 빌드 시험)
      │
      └──webhook──▶ Coolify (keymedi-mini-pc)
                      ├─ travelwithjaws-hub  (Dockerfile, /hub)  ── travel.jawsweb.site
                      └─ travel-supabase     (Supabase 서비스)   ── api-travel.jawsweb.site
                               ▲
              deploy/minipc/setup-db.sh  (마이그레이션 적용)
```

## 1. 처음 한 번

### 1-1. Coolify 가 저장소를 읽을 수 있게
Coolify 에 연결된 GitHub 앱(haedong-web 배포에 쓰는 것)의 저장소 접근 목록에 `travelwithjaws` 를 추가합니다.
GitHub → Settings → Applications → Installed GitHub Apps → (Coolify 앱) → Configure → Repository access.

### 1-2. Supabase (DB·API)
1. Coolify → Project(예: jawsweb) → New Resource → Service → **Supabase** → 이름 `travel-supabase`
2. Kong 도메인: `https://api-travel.jawsweb.site`
3. Environment Variables 에서 `PGRST_DB_SCHEMAS` 끝에 `,trip` 추가 → Deploy
4. 서비스 화면에서 `SERVICE_SUPABASEANON_KEY`, `SERVICE_SUPABASESERVICE_KEY` 값을 확인해 둡니다 (허브 환경변수에 씀)

### 1-3. 미니PC에서 DB 마이그레이션
```bash
ssh keymedi@192.168.0.202          # 밖에서는 Tailscale 주소
git clone https://github.com/k710922-a11y/travelwithjaws.git ~/travelwithjaws   # 처음 한 번
cd ~/travelwithjaws && git pull
DRY_RUN=1 bash deploy/minipc/setup-db.sh      # 적용 예정 확인
bash deploy/minipc/setup-db.sh                # 적용
bash deploy/minipc/add-staff.sh "정수" product,editor jungsoo   # 콘솔 로그인 줄 생성
```
- Supabase DB 가 여러 개(haedong 등)면 스크립트가 멈추고 이름 목록을 보여 줍니다. Travel 용 이름을 인자로 다시 실행하세요.
- 비공개 저장소라 clone 에 GitHub 로그인이 필요합니다. haedong-web 을 받을 때 쓰는 방법(토큰 또는 SSH 키)을 그대로 쓰면 됩니다.

### 1-4. 허브 앱
Coolify → New Resource → Application → GitHub App(위 1-1) → `travelwithjaws`, 브랜치 `main`

| 항목 | 값 |
|---|---|
| Build Pack | Dockerfile |
| Base Directory | `/` (Dockerfile `/Dockerfile`) |
| Port | 3000 |
| Domain | `https://travel.jawsweb.site` |
| Health Check Path | `/api/health` |
| Auto Deploy | 켬 (push 시 자동 배포) |

환경변수:

| 이름 | 값 |
|---|---|
| `SUPABASE_URL` | `http://supabase-kong-<서비스uuid>:8000` (내부 주소, 앱·서비스 모두 'Connect to Predefined Network' 켬) |
| `DATABASE_URL` | `postgresql://postgres:<SERVICE_PASSWORD_POSTGRES>@supabase-db-<서비스uuid>:5432/postgres` — 시작 시 마이그레이션 |
| `CONSOLE_STAFF` | `staff_uuid|이름|역할` — CONSOLE_USERS 의 staff_uuid 와 같은 값, 시작 시 등록 |
| `SUPABASE_ANON_KEY` | 1-2 의 anon 키 |
| `SUPABASE_SERVICE_ROLE_KEY` | 1-2 의 service 키 (**Build Variable 체크 해제**, 런타임 전용) |
| `CONSOLE_USERS` | 1-3 add-staff 출력. 여러 명은 `;` 로 연결 |
| `NEXT_PUBLIC_BRAND` | `Travel.with.Jaws` |
| `NEXT_PUBLIC_SITE_URL` | `https://travel.jawsweb.site` |
| `HERO_VIDEO_URL` | (선택) 권리 승인된 히어로 영상 주소 |

### 1-5. Cloudflare Tunnel
Zero Trust → Networks → Tunnels → 기존 미니PC 터널 → Public Hostname 추가

| 호스트 | 서비스 |
|---|---|
| `travel.jawsweb.site` | Coolify 프록시 (haedong 과 같은 대상) |
| `api-travel.jawsweb.site` | Coolify 프록시 |

### 1-6. 확인
- `https://travel.jawsweb.site/api/health` → `{"ok":true,"db":"up"}` (DB 미연결이면 `"demo"`)
- `https://travel.jawsweb.site` 상단에 "데모 모드" 띠가 없으면 DB 연결 완료
- `https://travel.jawsweb.site/console` → 로그인 창 → 1-3 에서 만든 아이디·비밀번호

## 2. 평소 배포

```
코드 수정 → git push → Actions 시험 통과 확인 → Coolify 자동 배포
DB 변경이 있으면: 새 번호 파일(db/migrations/006_….sql) 추가 → 미니PC에서 git pull && bash deploy/minipc/setup-db.sh
```
- 이미 적용한 마이그레이션 파일은 고치지 않습니다. 고치면 setup-db.sh 가 변조로 판단하고 멈춥니다.
- DB 변경과 화면 변경이 함께 있으면 **DB 먼저** 적용한 뒤 허브가 배포되게 합니다.

## 3. 백업
Coolify → travel-supabase → Backups → 매일 1회, 보관 7일 이상. 첫 운영 데이터가 들어가기 전에 복원 시험을 한 번 해 둡니다.

## 화면 확인용 예시 데이터

- `trip.load_demo()` 로 넣고 `trip.remove_demo()` 로 지운다 (`db/migrations/006_demo.sql`). 실제 데이터는 건드리지 않는다.
- 예시도 실제와 같은 권리·근거·승인 절차를 거쳐 공개되며, 공개 뷰의 `is_demo` 로 화면에 **예시** 표시와 상단 안내가 붙는다.
- 넣기·지우기 방법 (둘 중 하나)
  - 편집 콘솔 `/console` 상단의 **넣기 / 새로 고침**, **모두 지우기**
  - 작업 PC PowerShell:
    `Get-Content -LiteralPath "<repo>\deploy\minipc\demo-data.sh" -Raw | ssh keymedi@192.168.0.202 "bash -s"` (지우기는 `"ACTION=remove bash -s"`)
- 실제 운영을 시작하기 전에 반드시 지운다.

## 관리자(편집 콘솔) 입장 — k710922@gmail.com 전용

- 포털 오른쪽 위 **관리자** 버튼 → `/console`. 입장은 Cloudflare Access(이메일 일회용 코드)로만 허용한다.
- 허브 서버(`hub/middleware.ts`)가 Cloudflare 서명 토큰과 이메일을 다시 검증한다 — 터널을 거치지 않은 직접 접속·토큰 위조는 403.
- 환경변수: `CF_ACCESS_TEAM_DOMAIN`, `CF_ACCESS_AUD`, `CONSOLE_ADMINS="k710922@gmail.com=<staff_uuid>"`.
  설정되면 기존 아이디/비밀번호(`CONSOLE_USERS`) 로그인은 꺼진다 (`CONSOLE_BASIC_FALLBACK=1` 일 때만 함께 허용).
- Cloudflare 설정: Zero Trust → Access → Applications → Self-hosted → 도메인 `travel.jawsweb.site`, 경로 `console`
  → 정책 Allow · Include · Emails `k710922@gmail.com` → 로그인 방식 One-time PIN. 앱의 AUD 태그와 팀 도메인을 복사해
  `deploy/minipc/set-admin-access.sh` 로 넣는다.

### 관리자 비밀번호 (기본 입장 방식)

- `/admin-login` 에서 `k710922@gmail.com` + 비밀번호 → 12시간 세션. 같은 주소에서 15분에 10번 틀리면 15분 잠금.
- 비밀번호는 PBKDF2-SHA256 해시(`ADMIN_PASSWORD_HASH`)로만 저장한다. 바꿀 때마다 세션 비밀값이 바뀌어 모든 기기가 로그아웃된다.
- 설정·변경: `deploy/minipc/set-admin-password.sh` (PowerShell 에서 비밀번호를 숨김 입력 → base64 로 전달).
- 설정되면 예전 아이디/비밀번호 창(`CONSOLE_USERS`)은 꺼진다. Cloudflare Access 를 켜면 그것이 우선한다.
