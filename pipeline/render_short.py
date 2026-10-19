#!/usr/bin/env python3
"""
쇼츠 로컬 합성기 (계획서 22쪽 '쇼츠 제작 명세', 39~40쪽 '로컬 도구·품질 검수')

원칙
- 권리가 승인된 자산만 받는다. 하나라도 사용 불가면 합성하지 않고 종료한다.
- 사진은 늘이지 않는다(비율 유지 + 흐린 배경 채움). 확대/이동은 allow_edit 자산에만, 아주 약하게.
- 자막은 플랫폼 UI가 가리는 하단·우측 영역을 피한다. 제휴 고지는 상단에 상시 표시.
- 결과 파일은 '후보'다. 검수·승인은 DB 상태 전이로만 한다.

사용
  python render_short.py job.json --out renders/            # 매니페스트의 권리 정보로 검사
  python render_short.py job.json --out renders/ --db "$DATABASE_URL"   # DB(trip.asset_usable)로 검사
  옵션: --tts edge|none  (기본 edge, 실패 시 오류. none 은 무음+장면 길이 고정 시험용)
"""
from __future__ import annotations
import argparse, asyncio, hashlib, json, os, shutil, subprocess, sys, tempfile
from pathlib import Path

W, H, FPS = 1080, 1920, 30
FONT = "Noto Sans CJK KR"
SAFE_BOTTOM = 420          # 하단 UI(제목·버튼) 회피
SAFE_RIGHT = 160           # 우측 좋아요/공유 버튼 회피
MAX_CPS = 9.0              # 한국어 자막 초당 글자 수 상한 (읽기 시간 확보)
MIN_SCENE, MAX_SCENE = 2.0, 6.0
VOICES = {"ko": "ko-KR-SunHiNeural", "en": "en-US-JennyNeural", "ja": "ja-JP-NanamiNeural"}


class Blocked(Exception):
    pass


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise RuntimeError(f"명령 실패: {' '.join(cmd[:4])}…\n{r.stderr[-1500:]}")
    return r


def probe_duration(p: Path) -> float:
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(p)])
    return float(r.stdout.strip())


# ---------------------------------------------------------------- 권리 검사
def check_rights(job: dict, dsn: str | None) -> list[str]:
    problems = []
    ids = [s["asset_id"] for s in job["scenes"]] + [a["asset_id"] for a in job.get("audio_assets", [])]
    if dsn:
        import psycopg  # pip install psycopg[binary]
        with psycopg.connect(dsn) as conn:
            rows = conn.execute(
                "select id::text, trip.asset_usable(a, 'youtube'::trip.channel_t), allow_edit "
                "from trip.assets a where id = any(%s::uuid[])", (ids,)).fetchall()
        found = {r[0]: (r[1], r[2]) for r in rows}
        for i in ids:
            if i not in found:
                problems.append(f"{i}: 자산대장에 없음")
            elif not found[i][0]:
                problems.append(f"{i}: 권리 미확인/철회/만료 또는 유튜브 미허용")
        for s in job["scenes"]:
            s["allow_edit"] = found.get(s["asset_id"], (False, False))[1]
    else:
        ledger = {a["asset_id"]: a for a in job.get("rights", [])}
        for i in ids:
            a = ledger.get(i)
            if not a:
                problems.append(f"{i}: 권리 기록 없음")
            elif a.get("rights_status") != "approved":
                problems.append(f"{i}: rights_status={a.get('rights_status')}")
            elif "youtube" not in a.get("allowed_media", []):
                problems.append(f"{i}: 유튜브 사용 미허용")
        for s in job["scenes"]:
            s["allow_edit"] = ledger.get(s["asset_id"], {}).get("allow_edit", False)
    return problems


def check_script(job: dict) -> list[str]:
    p = []
    if not job.get("question"):
        p.append("고객 질문(question) 없음")
    for n, s in enumerate(job["scenes"], 1):
        if not Path(s["image"]).exists():
            p.append(f"장면 {n}: 이미지 파일 없음 {s['image']}")
        if not s.get("claim_ids") and s.get("role") == "evidence":
            p.append(f"장면 {n}: 근거 장면인데 연결된 주장(claim_ids) 없음")
    if job.get("sponsored") and not job.get("disclosure"):
        p.append("제휴/협찬인데 고지 문구 없음")
    if not job.get("hub_url"):
        p.append("허브 연결 주소 없음")
    return p


# ---------------------------------------------------------------- 음성
async def _edge(text: str, voice: str, out: Path):
    import edge_tts  # pip install edge-tts
    await edge_tts.Communicate(text, voice, rate="+5%").save(str(out))


def make_voice(text: str, lang: str, out: Path, mode: str) -> float:
    if mode == "edge" and text.strip():
        try:
            asyncio.run(_edge(text, VOICES.get(lang, VOICES["ko"]), out))
        except Exception as e:
            raise SystemExit(f"음성 생성 실패(edge-tts 서버 접속 불가 등): {e.__class__.__name__}. "
                             f"네트워크를 확인하거나 --tts none 으로 시험 합성하세요.")
        return probe_duration(out)
    return 0.0


# ---------------------------------------------------------------- 자막(ASS)
def ass_time(t: float) -> str:
    h, rem = divmod(t, 3600); m, s = divmod(rem, 60)
    return f"{int(h)}:{int(m):02d}:{s:05.2f}"


def wrap(text: str, width: int = 14) -> str:
    out, line = [], ""
    for word in text.split(" "):
        if len(line) + len(word) + 1 > width and line:
            out.append(line); line = word
        else:
            line = (line + " " + word).strip()
    out.append(line)
    return r"\N".join(out)


def build_ass(scenes: list[dict], job: dict, path: Path):
    mv = SAFE_BOTTOM
    head = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 2

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,{FONT},64,&H00FFFFFF,&H00FFFFFF,&H00000000,&H96000000,1,0,0,0,100,100,0,0,3,0,0,2,80,{80 + SAFE_RIGHT},{mv},1
Style: Q,{FONT},70,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,1,0,0,0,100,100,0,0,1,5,0,8,80,{80 + SAFE_RIGHT},260,1
Style: Tag,{FONT},38,&H00FFFFFF,&H00FFFFFF,&H00000000,&HB4000000,0,0,0,0,100,100,0,0,3,0,0,7,60,60,90,1
Style: Src,{FONT},34,&H00E6E6E6,&H00E6E6E6,&H00000000,&H78000000,0,0,0,0,100,100,0,0,3,0,0,1,60,{60 + SAFE_RIGHT},{mv - 120},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    ev = []
    total = sum(s["dur"] for s in scenes)
    tag = job.get("disclosure") if job.get("sponsored") else None
    if tag:
        ev.append(f"Dialogue: 2,{ass_time(0)},{ass_time(total)},Tag,,0,0,0,,{tag}")
    t = 0.0
    for s in scenes:
        st, en = t, t + s["dur"]
        if s.get("role") == "question":
            ev.append(f"Dialogue: 1,{ass_time(st)},{ass_time(en)},Q,,0,0,0,,{wrap(s['caption'], 12)}")
        else:
            ev.append(f"Dialogue: 1,{ass_time(st)},{ass_time(en)},Cap,,0,0,0,,{wrap(s['caption'])}")
        if s.get("source_label"):
            ev.append(f"Dialogue: 1,{ass_time(st)},{ass_time(en)},Src,,0,0,0,,{s['source_label']}")
        t = en
    path.write_text(head + "\n".join(ev) + "\n", encoding="utf-8")


def build_srt(scenes: list[dict], path: Path):
    def ts(x):
        h, r = divmod(x, 3600); m, s = divmod(r, 60)
        return f"{int(h):02d}:{int(m):02d}:{int(s):02d},{int((s % 1) * 1000):03d}"
    t, out = 0.0, []
    for i, s in enumerate(scenes, 1):
        out.append(f"{i}\n{ts(t)} --> {ts(t + s['dur'])}\n{s['caption']}\n")
        t += s["dur"]
    path.write_text("\n".join(out), encoding="utf-8")


# ---------------------------------------------------------------- 장면 영상
def scene_clip(img: Path, dur: float, allow_edit: bool, out: Path):
    frames = int(round(dur * FPS))
    # 배경: 같은 사진을 흐리게 채움 / 전경: 비율 유지로 맞춤 (늘이지 않음)
    fg_chain = f"[0:v]scale={W}:{H}:force_original_aspect_ratio=decrease,fps={FPS}"
    if allow_edit:
        # 최대 4%까지만 천천히 확대 — 주목 지점을 돕는 수준, 없는 시설을 만들지 않음
        fg_chain += f",scale=w='trunc(iw*(1+0.04*t/{dur:.3f})/2)*2':h=-2:eval=frame"
    fg_chain += "[fg]"
    fc = (f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},boxblur=30:2,"
          f"eq=brightness=-0.15,fps={FPS}[bg];{fg_chain};"
          f"[bg][fg]overlay=(W-w)/2:(H-h)/2:shortest=1,format=yuv420p[v]")
    run(["ffmpeg", "-y", "-loop", "1", "-i", str(img), "-filter_complex", fc, "-map", "[v]",
         "-t", f"{dur:.3f}", "-r", str(FPS), "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", str(out)])


# ---------------------------------------------------------------- 품질 검사 (40쪽)
def qc(video: Path, scenes: list[dict]) -> dict:
    r = run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,width,height", "-of", "json", str(video)])
    streams = json.loads(r.stdout)["streams"]
    v = next(s for s in streams if s["codec_type"] == "video")
    has_audio = any(s["codec_type"] == "audio" for s in streams)
    bd = subprocess.run(["ffmpeg", "-i", str(video), "-vf", "blackdetect=d=0.5:pix_th=0.05", "-an", "-f", "null", "-"],
                        capture_output=True, text=True).stderr
    cps = [round(len(s["caption"].replace(" ", "")) / s["dur"], 1) for s in scenes]
    res = {
        "resolution_ok": (v["width"], v["height"]) == (W, H),
        "has_audio": has_audio,
        "duration": round(probe_duration(video), 2),
        "black_segments": bd.count("black_start"),
        "caption_cps": cps,
        "caption_too_fast": [i + 1 for i, c in enumerate(cps) if c > MAX_CPS],
    }
    res["blocking"] = [k for k, bad in [
        ("해상도 불일치", not res["resolution_ok"]),
        ("오디오 트랙 없음", not has_audio),
        ("검은 화면 구간", res["black_segments"] > 0),
        ("자막 읽기 시간 부족", bool(res["caption_too_fast"])),
    ] if bad]
    return res


# ---------------------------------------------------------------- 메인
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("job")
    ap.add_argument("--out", default="renders")
    ap.add_argument("--db", default=os.environ.get("DATABASE_URL"))
    ap.add_argument("--tts", choices=["edge", "none"], default="edge")
    ap.add_argument("--music", help="(선택) 승인된 배경음 파일 — audio_assets 에 권리 기록 필요")
    a = ap.parse_args()

    job_path = Path(a.job).resolve()
    job = json.loads(job_path.read_text(encoding="utf-8"))
    base = job_path.parent
    for s in job["scenes"]:
        s["image"] = str((base / s["image"]).resolve())

    problems = check_rights(job, a.db) + check_script(job)
    if problems:
        print("합성 차단:\n  - " + "\n  - ".join(problems), file=sys.stderr)
        sys.exit(2)

    out_dir = Path(a.out); out_dir.mkdir(parents=True, exist_ok=True)
    stem = f"{job['job_no']}_v{job.get('version', 1)}_{job.get('lang', 'ko')}"
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        # 1) 장면별 음성 → 길이 결정 (자막 읽기 시간 하한 함께 고려)
        voice_parts = []
        for i, s in enumerate(job["scenes"]):
            vo = td / f"vo{i}.mp3"
            d = make_voice(s.get("narration", ""), job.get("lang", "ko"), vo, a.tts)
            read_min = len(s["caption"].replace(" ", "")) / MAX_CPS
            s["dur"] = round(min(max(d + 0.35, read_min + 0.3, MIN_SCENE), max(MAX_SCENE, d + 0.35)), 2)
            voice_parts.append((vo if d > 0 else None, s["dur"]))

        # 2) 장면 영상
        clips = []
        for i, s in enumerate(job["scenes"]):
            c = td / f"c{i}.mp4"
            scene_clip(Path(s["image"]), s["dur"], bool(s.get("allow_edit")), c)
            clips.append(c)
        lst = td / "list.txt"
        lst.write_text("".join(f"file '{c}'\n" for c in clips))
        silent = td / "silent.mp4"
        run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(silent)])

        # 3) 내레이션 트랙 (장면 길이에 맞춰 패딩)
        inputs, chains = [], []
        for i, (vo, dur) in enumerate(voice_parts):
            if vo:
                inputs += ["-i", str(vo)]
            else:
                inputs += ["-f", "lavfi", "-t", f"{dur}", "-i", "anullsrc=r=44100:cl=stereo"]
            chains.append(f"[{i}:a]aresample=44100,aformat=channel_layouts=stereo,apad=whole_dur={dur}[a{i}]")
        n = len(voice_parts)
        fc = ";".join(chains) + ";" + "".join(f"[a{i}]" for i in range(n)) + f"concat=n={n}:v=0:a=1[narr]"
        narr = td / "narr.m4a"
        run(["ffmpeg", "-y", *inputs, "-filter_complex", fc, "-map", "[narr]", "-c:a", "aac", "-b:a", "160k", str(narr)])

        if a.music:
            mixed = td / "mix.m4a"
            # 배경음은 안내 음성을 가리지 않게 덕킹
            run(["ffmpeg", "-y", "-i", str(narr), "-stream_loop", "-1", "-i", a.music, "-filter_complex",
                 "[1:a]volume=0.18[m];[m][0:a]sidechaincompress=threshold=0.05:ratio=8[d];[0:a][d]amix=inputs=2:duration=first[o]",
                 "-map", "[o]", "-c:a", "aac", str(mixed)])
            narr = mixed

        # 4) 자막 굽기 + 합치기
        ass = td / "subs.ass"
        build_ass(job["scenes"], job, ass)
        out = out_dir / f"{stem}.mp4"
        run(["ffmpeg", "-y", "-i", str(silent), "-i", str(narr), "-vf", f"ass={ass}",
             "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
             "-c:a", "copy", "-shortest", "-movflags", "+faststart", str(out)])
        shutil.copy(ass, out_dir / f"{stem}.ass")
    build_srt(job["scenes"], out_dir / f"{stem}.srt")

    # 5) 품질 검사 + 근거 묶음
    q = qc(out, job["scenes"])
    sha = hashlib.sha256(out.read_bytes()).hexdigest()
    sidecar = {
        "job_no": job["job_no"], "version": job.get("version", 1), "lang": job.get("lang", "ko"),
        "render_uri": str(out), "render_sha256": sha,
        "asset_ids": [s["asset_id"] for s in job["scenes"]],
        "claim_ids": sorted({c for s in job["scenes"] for c in s.get("claim_ids", [])}),
        "scenes": [{k: s[k] for k in ("role", "asset_id", "caption", "dur") if k in s} for s in job["scenes"]],
        "qc": q,
        "status": "candidate" if not q["blocking"] else "qc_failed",
        "note": "후보 파일입니다. 공개는 DB에서 검수·승인 전이를 거친 뒤에만 가능합니다.",
    }
    (out_dir / f"{stem}.json").write_text(json.dumps(sidecar, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"out": str(out), "qc": q}, ensure_ascii=False, indent=2))
    sys.exit(0 if not q["blocking"] else 3)


if __name__ == "__main__":
    main()
