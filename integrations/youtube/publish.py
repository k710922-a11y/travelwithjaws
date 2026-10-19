#!/usr/bin/env python3
"""
유튜브 공식 업로드 연동 (계획서 24쪽 '채널 운영과 공식 배포', 38쪽 '예외 처리')

흐름
  1) auth      : 대표님이 직접 Google 로그인·동의 → token.json 저장 (이 PC/서버에만, 커밋 금지)
  2) upload    : DB에서 '승인' + 유튜브 배포 대기(queued) 건만 골라 **비공개**로 업로드
  3) verify    : 사람이 유튜브 스튜디오에서 재생·설명·링크를 확인한 뒤 공개 전환 + 확인자 기록
  4) status    : 대기/비공개업로드/공개/실패/수정필요 현황

안전장치
  - 업로드 직전 DB의 version_blockers()를 다시 검사 (권리 철회·근거 보류 반영)
  - 같은 버전·채널은 DB unique 제약으로 한 번만. 응답이 끊긴 경우 재시도 전에
    채널 최근 업로드에서 작업번호 태그를 조회해 중복 게시를 막음
  - 업로드 성공 ≠ 공개. 공개 전환은 verify 명령(확인자 필수)으로만
  - 웹 세션 자동화·로그인 우회 없음. 공식 Data API + OAuth만 사용

준비
  pip install google-api-python-client google-auth-oauthlib psycopg[binary]
  export DATABASE_URL=postgresql://...      (서비스 권한 DB 접속)
  client_secret.json : Google Cloud 콘솔 > OAuth 클라이언트 ID(데스크톱 앱)에서 내려받기
"""
from __future__ import annotations
import argparse, json, os, sys, time
from pathlib import Path

HERE = Path(__file__).parent
SECRET = Path(os.environ.get("YT_CLIENT_SECRET", HERE / "client_secret.json"))
TOKEN = Path(os.environ.get("YT_TOKEN", HERE / "token.json"))
SCOPES = [
    "https://www.googleapis.com/auth/youtube.upload",     # 업로드
    "https://www.googleapis.com/auth/youtube.force-ssl",  # 자막 업로드·공개 전환·조회
]
TAG_PREFIX = "tripjob:"   # 설명 마지막 줄에 넣어 중복 조회에 사용


# ------------------------------------------------------------------ 인증
def creds(interactive: bool = False):
    from google.oauth2.credentials import Credentials
    from google.auth.transport.requests import Request
    c = Credentials.from_authorized_user_file(str(TOKEN), SCOPES) if TOKEN.exists() else None
    if c and c.expired and c.refresh_token:
        c.refresh(Request())
        TOKEN.write_text(c.to_json())
    if (not c or not c.valid):
        if not interactive:
            sys.exit("인증 필요: python publish.py auth  (대표님이 직접 브라우저에서 로그인·동의)")
        from google_auth_oauthlib.flow import InstalledAppFlow
        if not SECRET.exists():
            sys.exit(f"{SECRET} 없음 — Google Cloud 콘솔에서 '데스크톱 앱' OAuth 클라이언트를 만들어 내려받으세요.")
        flow = InstalledAppFlow.from_client_secrets_file(str(SECRET), SCOPES)
        # 미니PC처럼 브라우저가 없는 곳: --no-browser 로 URL을 띄우고 다른 기기에서 승인
        c = flow.run_local_server(port=0, open_browser=os.environ.get("NO_BROWSER") != "1")
        TOKEN.write_text(c.to_json())
        os.chmod(TOKEN, 0o600)
    return c


def yt():
    from googleapiclient.discovery import build
    return build("youtube", "v3", credentials=creds(), cache_discovery=False)


def db():
    import psycopg
    dsn = os.environ.get("DATABASE_URL") or sys.exit("DATABASE_URL 이 필요합니다")
    return psycopg.connect(dsn, autocommit=True)


# ------------------------------------------------------------------ 설명문
def build_description(row: dict) -> str:
    lines = [row["question"], ""]
    if row["description"]:
        lines += [row["description"], ""]
    lines.append(f"▶ 공식 안내·후기 원문·준비카드: {row['hub_url']}")
    if row["sponsored"] and row["disclosure"]:
        lines.append(f"※ {row['disclosure']}")
    lines.append(f"※ 확인일 {row['checked']}. 예약 조건은 예약 사업자·시설 공식 안내에서 최종 확인하세요.")
    lines += ["", f"{TAG_PREFIX}{row['job_no']}-v{row['version']}-{row['lang']}"]
    return "\n".join(lines)[:4900]


# ------------------------------------------------------------------ 중복 조회
def find_existing(y, marker: str) -> str | None:
    ch = y.channels().list(part="contentDetails", mine=True).execute()
    uploads = ch["items"][0]["contentDetails"]["relatedPlaylists"]["uploads"]
    items = y.playlistItems().list(part="snippet", playlistId=uploads, maxResults=25).execute().get("items", [])
    for it in items:
        if marker in it["snippet"].get("description", ""):
            return it["snippet"]["resourceId"]["videoId"]
    return None


# ------------------------------------------------------------------ 업로드
QUEUE_SQL = """
select pb.id, pb.attempts, j.job_no, j.question, j.status as job_status, v.id as version_id, v.version, v.lang,
       v.title, v.description, v.sponsored, v.disclosure, v.render_uri,
       to_char(coalesce(v.approved_at, now()), 'YYYY.MM.DD') as checked,
       exists(select 1 from trip.version_assets va join trip.assets a on a.id = va.asset_id
              where va.version_id = v.id and a.source_type = 'generated') as synthetic,
       trip.version_blockers(v.id, 'youtube') as blockers
  from trip.publications pb
  join trip.content_versions v on v.id = pb.version_id
  join trip.content_jobs j on j.id = v.job_id
 where pb.channel = 'youtube' and pb.status in ('queued', 'failed')
   and j.status in ('approved', 'published') and pb.attempts < 3
 order by pb.created_at
 limit %s
"""


def cmd_upload(a):
    if not a.dry_run:
        from googleapiclient.http import MediaFileUpload
        from googleapiclient.errors import HttpError
    else:
        class HttpError(Exception): ...
    from psycopg.rows import dict_row
    hub_base = os.environ.get("HUB_BASE", "https://travel.jawsweb.site")
    y = None if a.dry_run else yt()
    with db() as conn:
        rows = conn.cursor(row_factory=dict_row).execute(QUEUE_SQL, (a.limit,)).fetchall()
        if not rows:
            print("업로드 대기 없음"); return
        for row in rows:
            row["hub_url"] = f"{hub_base}/p/{row['job_no']}?src=yt"
            tag = f"{row['job_no']} v{row['version']} {row['lang']}"
            if row["blockers"]:
                conn.execute("update trip.publications set status='needs_fix', last_error=%s where id=%s",
                             (" / ".join(row["blockers"]), row["id"]))
                print(f"[차단] {tag}: {row['blockers']}"); continue
            path = Path(row["render_uri"] or "")
            if not path.exists():
                conn.execute("update trip.publications set status='failed', attempts=attempts+1, last_error=%s where id=%s",
                             (f"파일 없음: {path}", row["id"]))
                print(f"[실패] {tag}: 파일 없음 {path}"); continue

            desc = build_description(row)
            marker = desc.splitlines()[-1]
            # 이전 시도에서 응답이 끊겼을 수 있으면 먼저 조회
            if row["attempts"] > 0:
                vid = find_existing(y, marker)
                if vid:
                    conn.execute("""update trip.publications set status='uploaded_private', external_id=%s,
                                    url=%s, last_error=null where id=%s""",
                                 (vid, f"https://youtube.com/shorts/{vid}", row["id"]))
                    print(f"[복구] {tag}: 이미 올라가 있던 영상 {vid} 연결"); continue

            body = {
                "snippet": {"title": row["title"][:100], "description": desc, "categoryId": "19",  # Travel & Events
                            "defaultLanguage": row["lang"], "defaultAudioLanguage": row["lang"]},
                "status": {"privacyStatus": "private",            # 항상 비공개로 올리고 사람이 확인 후 공개
                           "selfDeclaredMadeForKids": False,
                           "containsSyntheticMedia": bool(row["synthetic"])},
            }
            if a.dry_run:
                print(f"[시험] {tag}\n{json.dumps(body, ensure_ascii=False, indent=2)}"); continue
            conn.execute("update trip.publications set attempts=attempts+1 where id=%s", (row["id"],))
            try:
                req = y.videos().insert(part="snippet,status", body=body,
                                        media_body=MediaFileUpload(str(path), mimetype="video/mp4", resumable=True))
                resp = None
                while resp is None:
                    _, resp = req.next_chunk()
                vid = resp["id"]
                conn.execute("""update trip.publications set status='uploaded_private', external_id=%s, url=%s,
                                last_error=null where id=%s""", (vid, f"https://youtube.com/shorts/{vid}", row["id"]))
                print(f"[비공개 업로드] {tag} → {vid}")
                srt = path.with_suffix(".srt")
                if srt.exists() and a.captions:
                    y.captions().insert(part="snippet", body={"snippet": {"videoId": vid, "language": row["lang"],
                        "name": "편집 자막", "isDraft": False}}, media_body=MediaFileUpload(str(srt))).execute()
            except HttpError as e:
                reason = f"HTTP {e.resp.status}: {e._get_reason()}"
                conn.execute("update trip.publications set status='failed', last_error=%s where id=%s", (reason, row["id"]))
                print(f"[실패] {tag}: {reason}")
                if e.resp.status in (403, 429):   # 할당량·권한 문제 → 나머지도 멈춤
                    print("할당량 또는 권한 문제로 이번 회차를 중단합니다."); break
            except Exception as e:  # 연결 끊김 등 — 다음 시도에서 중복 조회 후 재처리
                conn.execute("update trip.publications set status='failed', last_error=%s where id=%s",
                             (f"{e.__class__.__name__}: {e}"[:500], row["id"]))
                print(f"[결과 불명] {tag}: {e}. 다음 실행 때 채널을 먼저 조회합니다.")
            time.sleep(2)


def cmd_verify(a):
    """사람이 스튜디오에서 재생·설명·링크를 직접 확인한 뒤에만 실행"""
    y = yt()
    with db() as conn:
        r = conn.execute("""select pb.id, pb.external_id, j.id from trip.publications pb
                            join trip.content_versions v on v.id = pb.version_id join trip.content_jobs j on j.id = v.job_id
                            where pb.channel='youtube' and j.job_no=%s and pb.status='uploaded_private'
                            order by v.version desc limit 1""", (a.job_no,)).fetchone()
        if not r:
            sys.exit("비공개 업로드 상태인 유튜브 게시물이 없습니다")
        pub_id, vid, job_id = r
        checks = ["영상이 끝까지 재생되고 자막이 잘리지 않음", "설명란의 허브 링크가 해당 페이지로 열림",
                  "제휴 고지가 영상·설명에 보임", "제목·장소명이 허브와 같음"]
        print("공개 전 확인 항목:"); [print(f"  - {c}") for c in checks]
        if not a.yes and input("모두 확인했나요? (yes 입력) ").strip() != "yes":
            sys.exit("취소했습니다")
        y.videos().update(part="status", body={"id": vid, "status": {"privacyStatus": "public",
                          "selfDeclaredMadeForKids": False}}).execute()
        # 실제 상태 재조회 후 기록
        st = y.videos().list(part="status", id=vid).execute()["items"][0]["status"]["privacyStatus"]
        if st != "public":
            sys.exit(f"공개 전환이 반영되지 않았습니다 (현재 {st})")
        conn.execute("update trip.publications set status='public', verified_by=%s, verified_at=now() where id=%s",
                     (a.verified_by, pub_id))
        conn.execute("update trip.content_jobs set status='published' where id=%s and status='approved'", (job_id,))
        print(f"[공개] {a.job_no} → https://youtube.com/shorts/{vid}")


def cmd_status(a):
    with db() as conn:
        for r in conn.execute("""select j.job_no, v.version, v.lang, pb.status, pb.attempts, coalesce(pb.url,''), coalesce(pb.last_error,'')
                                 from trip.publications pb join trip.content_versions v on v.id=pb.version_id
                                 join trip.content_jobs j on j.id=v.job_id where pb.channel='youtube'
                                 order by pb.updated_at desc limit 50"""):
            print(" | ".join(str(x) for x in r))


LF_SQL = """
select lp.id, lp.code, lp.title, lp.status, lp.render_uri, lp.youtube_id, lp.intro_script, lp.disclosure, lp.update_notes,
       trip.longform_blockers(lp.id) as blockers,
       coalesce(json_agg(json_build_object('pos', c.position, 'title', c.chapter_title, 'job', j.job_no)
                         order by c.position) filter (where c.job_id is not null), '[]') as chapters
  from trip.longform_projects lp
  left join trip.longform_chapters c on c.project_id = lp.id
  left join trip.content_jobs j on j.id = c.job_id
 where lp.code = %s
 group by lp.id
"""


def longform_description(row: dict, hub: str) -> str:
    lines = [row["title"], ""]
    if row["intro_script"]:
        lines += [row["intro_script"][:600], ""]
    lines.append("■ 챕터별 판단 문서 (공식 안내·후기 원문·준비카드)")
    for c in row["chapters"]:
        lines.append(f"{c['pos']}. {c['title']} — {hub}/p/{c['job']}?src=yt_long")
    if row["update_notes"]:
        lines += ["", "■ 쇼츠 공개 이후 바뀐 정보", row["update_notes"][:600]]
    if row["disclosure"]:
        lines += ["", f"※ {row['disclosure']}"]
    lines += ["", "※ 예약 조건은 예약 사업자·시설 공식 안내에서 최종 확인하세요.", "",
              f"{TAG_PREFIX}{row['code']}"]
    return "\n".join(lines)[:4900]


def cmd_longform(a):
    """승인된 롱폼(쇼츠 묶음)을 비공개로 업로드. 공개 전환은 스튜디오 확인 후 --make-public"""
    from psycopg.rows import dict_row
    hub = os.environ.get("HUB_BASE", "https://travel.jawsweb.site")
    with db() as conn:
        row = conn.cursor(row_factory=dict_row).execute(LF_SQL, (a.code,)).fetchone()
        if not row:
            sys.exit(f"{a.code} 없음")
        if row["status"] not in ("approved", "published"):
            sys.exit(f"{a.code} 상태가 {row['status']} — 승인된 롱폼만 올립니다")
        if row["blockers"]:
            sys.exit(f"차단: {' / '.join(row['blockers'])}")
        desc = longform_description(row, hub)
        body = {"snippet": {"title": row["title"][:100], "description": desc, "categoryId": "19",
                            "defaultLanguage": "ko", "defaultAudioLanguage": "ko"},
                "status": {"privacyStatus": "private", "selfDeclaredMadeForKids": False}}
        if a.dry_run:
            print(json.dumps(body, ensure_ascii=False, indent=2)); return
        y = yt()
        if a.make_public:
            if not row["youtube_id"]:
                sys.exit("아직 업로드되지 않았습니다")
            if not a.yes and input("스튜디오에서 재생·챕터·설명 링크·제휴 표시를 확인했나요? (yes) ").strip() != "yes":
                sys.exit("취소했습니다")
            y.videos().update(part="status", body={"id": row["youtube_id"], "status": {"privacyStatus": "public", "selfDeclaredMadeForKids": False}}).execute()
            conn.execute("update trip.longform_projects set status='published' where id=%s", (row["id"],))
            print(f"[공개] {a.code} → https://youtu.be/{row['youtube_id']}"); return
        if row["youtube_id"]:
            sys.exit(f"이미 업로드됨: {row['youtube_id']} (중복 업로드 방지)")
        from googleapiclient.http import MediaFileUpload
        existing = find_existing(y, desc.splitlines()[-1])
        if existing:
            conn.execute("update trip.longform_projects set youtube_id=%s where id=%s", (existing, row["id"]))
            print(f"[복구] 이미 올라가 있던 영상 {existing} 연결"); return
        req = y.videos().insert(part="snippet,status", body=body,
                                media_body=MediaFileUpload(row["render_uri"], mimetype="video/mp4", resumable=True))
        resp = None
        while resp is None:
            _, resp = req.next_chunk()
        conn.execute("update trip.longform_projects set youtube_id=%s where id=%s", (resp["id"], row["id"]))
        print(f"[비공개 업로드] {a.code} → {resp['id']}")


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("auth")
    u = sp.add_parser("upload"); u.add_argument("--limit", type=int, default=3)
    u.add_argument("--dry-run", action="store_true"); u.add_argument("--captions", action="store_true")
    v = sp.add_parser("verify"); v.add_argument("job_no"); v.add_argument("--verified-by", required=True)
    v.add_argument("--yes", action="store_true")
    sp.add_parser("status")
    lf = sp.add_parser("longform"); lf.add_argument("code"); lf.add_argument("--dry-run", action="store_true")
    lf.add_argument("--make-public", action="store_true"); lf.add_argument("--yes", action="store_true")
    a = ap.parse_args()
    if a.cmd == "auth":
        creds(interactive=True); print(f"인증 완료 → {TOKEN} (외부 공유·커밋 금지)")
    else:
        {"upload": cmd_upload, "verify": cmd_verify, "status": cmd_status, "longform": cmd_longform}[a.cmd](a)


if __name__ == "__main__":
    main()
