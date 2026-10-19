# 설치 가이드 — 미니PC(Coolify) + 유튜브 연동

대상 환경: keymedi-mini-pc (Ubuntu 24.04, Coolify, Cloudflare Tunnel, `jawsweb.site`)
상업 서비스이므로 Vercel Hobby가 아니라 미니PC에서 운영합니다 (계획서 36쪽, S5).

---

## 1. DB (셀프호스팅 Supabase)

기존 `haedong-web`과 **분리된 새 Supabase 인스턴스**를 권장합니다 (권한·백업·장애 범위 분리).

1. Coolify → New Resource → Service → **Supabase** → 이름 `travel-supabase`
2. 도메인: `api-travel.jawsweb.site` (Cloudflare Tunnel에 공개 호스트 추가 → Kong 8000)
3. 환경변수 `PGRST_DB_SCHEMAS` 에 `trip` 추가 (예: `public,storage,graphql_public,trip`) → 재배포
4. Studio → SQL Editor 에서 순서대로 실행
   - `db/migrations/001_core.sql`
   - `db/migrations/002_access.sql`
   - `db/migrations/003_portal.sql`
5. (선택) 규칙 검증: 시험용 인스턴스에서 `test_rules.sql` → `test_portal.sql` 순서로 실행 → NOTICE에 `OK` 33개
   > 운영 DB에는 seed 파일을 실행하지 마세요 (예시 데이터가 들어갑니다).
6. Settings → API 에서 `anon` 키, `service_role` 키 확인 (service_role은 서버에만)

## 2. 웹허브

1. 이 폴더를 GitHub `k710922-a11y/travel-with-jaws` (비공개) 로 올립니다.
2. Coolify → New Resource → Application → GitHub → `trip-hub`
   - Base Directory: `/hub` · Build Pack: **Dockerfile** · Port: `3000`
   - 도메인: `travel.jawsweb.site`
   - 환경변수: `.env.example` 참고 (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `NEXT_PUBLIC_BRAND`)
3. Cloudflare Tunnel에 `travel.jawsweb.site` 공개 호스트 추가
4. 확인: `https://travel.jawsweb.site` 상단에 '데모 모드' 띠가 **없어야** DB에 연결된 것입니다.

## 3. 쇼츠 합성 (작업 PC 또는 미니PC)

```bash
sudo apt install ffmpeg fonts-noto-cjk     # 미니PC
pip install edge-tts "psycopg[binary]"
export DATABASE_URL=postgresql://postgres:<비밀번호>@<미니PC>:5432/postgres
python pipeline/render_short.py <작업.json> --out renders --db "$DATABASE_URL"
```
- `--db` 를 주면 자산 권리를 매니페스트가 아니라 **DB(asset_usable)** 에서 확인합니다. 운영에서는 항상 `--db`.
- 결과 `.json`의 `render_sha256`, `render_uri` 를 `content_versions`에 기록한 뒤 상태를 `review`로 넘깁니다.
- edge-tts 는 Microsoft 서버에 접속하므로 인터넷이 필요합니다. 음성 사용 조건은 착수 시 별도 확인 대상(계획서 39쪽).

## 4. 유튜브 연동 (대표님이 직접 하실 부분 포함)

### 4-1. Google Cloud 설정 — 대표님 직접
1. https://console.cloud.google.com → 새 프로젝트 `travel-with-jaws-youtube`
2. API 및 서비스 → 라이브러리 → **YouTube Data API v3** 사용 설정
3. OAuth 동의 화면 → 외부(External) → 앱 이름·지원 이메일 입력 → 범위 추가:
   `youtube.upload`, `youtube.force-ssl`
4. 테스트 사용자에 채널 소유 구글 계정 추가
5. 사용자 인증 정보 → OAuth 클라이언트 ID → **데스크톱 앱** → JSON 다운로드 →
   `integrations/youtube/client_secret.json` 으로 저장

> ⚠️ 동의 화면이 '테스트' 상태면 갱신 토큰이 일정 기간 뒤 만료되어 재인증이 필요할 수 있습니다.
> 안정 운영 단계에서 '프로덕션'으로 게시를 검토하세요.

### 4-2. 인증 — 대표님 직접 (1회)
```bash
pip install google-api-python-client google-auth-oauthlib "psycopg[binary]"
python integrations/youtube/publish.py auth
```
브라우저가 열리면 **채널 소유 계정으로 직접 로그인·동의**합니다. `token.json` 이 생성됩니다 (권한 600, 커밋 금지).
미니PC처럼 브라우저가 없으면 작업 PC에서 인증 후 `token.json`을 안전하게 복사하세요.

### 4-3. 운영 흐름
```bash
python integrations/youtube/publish.py upload --dry-run   # 올릴 본문 미리보기
python integrations/youtube/publish.py upload --captions  # 승인건 → 비공개 업로드 (+자막)
# ↓ 유튜브 스튜디오에서 재생·자막·설명 링크·제휴 고지 직접 확인
python integrations/youtube/publish.py verify TRP-00001 --verified-by <staff uuid>
python integrations/youtube/publish.py status
```

### 4-4. 알아둘 제한 (2026.10.19 공식 문서 기준)
- 업로드(`videos.insert`)는 '동영상 업로드' 할당량에서 호출당 1단위, **하루 100회** 한도가 표시되어 있습니다.
  계획서의 주당 2편 운영에는 충분하지만, 실패 재시도도 1회로 셉니다.
- `status.containsSyntheticMedia` 를 업로드 시 지정할 수 있어, 자산에 `generated`(합성)가 있으면 자동으로 `true`로 표시합니다.
- 할당량·권한 오류(403/429)가 나면 그 회차 업로드를 즉시 멈춥니다.

## 5. 백업
- Coolify의 Supabase 리소스 → Backups → 매일 1회 + 외부(Google Drive 등) 보관 설정
- `token.json`, `client_secret.json`, `.env` 는 백업 대상이지만 **저장소에는 절대 커밋하지 않습니다** (`.gitignore` 반영).
