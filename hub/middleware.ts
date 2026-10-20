import { NextRequest, NextResponse } from "next/server";
import { createRemoteJWKSet, jwtVerify } from "jose";

// 편집 콘솔(관리자) 보호
//
// 1) 기본: Cloudflare Access — 허용된 이메일만 입장
//    CF_ACCESS_TEAM_DOMAIN="<팀>.cloudflareaccess.com", CF_ACCESS_AUD="<Access 앱의 AUD 태그>"
//    CONSOLE_ADMINS="k710922@gmail.com=<staff_uuid>"  (여러 명은 ; 로 구분)
//    Cloudflare 가 붙여 주는 서명 토큰(Cf-Access-Jwt-Assertion)을 서버가 다시 검증한다.
//    → 터널을 거치지 않고 미니PC로 직접 들어오는 요청, 토큰 위조, 허용 목록 밖의 이메일은 모두 막힌다.
// 2) 예비: HTTP 기본 인증 — Access 설정 전까지만. CONSOLE_USERS="이름:비밀번호:staff_uuid;…"
//    Access 가 설정되면 기본 인증은 꺼진다 (CONSOLE_BASIC_FALLBACK=1 일 때만 함께 허용).
// 아무것도 설정되지 않으면 콘솔 전체가 404. 데모(DB 미연결)에서만 CONSOLE_DEMO=1 이면 읽기 전용으로 열림.
// 인증된 사람의 staff id 는 x-console-staff 헤더로 서버에 전달 (외부에서 보낸 같은 헤더는 지움)

type User = { name: string; pass: string; staff: string };
type Admin = { email: string; staff: string };

function users(): User[] {
  return (process.env.CONSOLE_USERS ?? "")
    .split(";").map((s) => s.trim()).filter(Boolean)
    .map((s) => { const [name, pass, staff] = s.split(":"); return { name, pass, staff }; })
    .filter((u) => u.name && u.pass && u.staff);
}

function admins(): Admin[] {
  return (process.env.CONSOLE_ADMINS ?? "")
    .split(";").map((s) => s.trim()).filter(Boolean)
    .map((s) => { const [email, staff] = s.split("="); return { email: (email ?? "").trim().toLowerCase(), staff: (staff ?? "").trim() }; })
    .filter((a) => a.email.includes("@") && a.staff);
}

function same(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

let jwks: ReturnType<typeof createRemoteJWKSet> | null = null;
let jwksFor = "";

async function accessEmail(req: NextRequest, team: string, aud: string): Promise<string | null> {
  const token = req.headers.get("cf-access-jwt-assertion") ?? req.cookies.get("CF_Authorization")?.value;
  if (!token) return null;
  if (!jwks || jwksFor !== team) {
    // CF_ACCESS_CERTS_URL 은 시험용(로컬 가짜 서명키). 운영에서는 비워 둔다.
    jwks = createRemoteJWKSet(new URL(process.env.CF_ACCESS_CERTS_URL || `https://${team}/cdn-cgi/access/certs`));
    jwksFor = team;
  }
  try {
    const { payload } = await jwtVerify(token, jwks, { issuer: `https://${team}`, audience: aud });
    const email = typeof payload.email === "string" ? payload.email.toLowerCase() : null;
    return email;
  } catch {
    return null;
  }
}

const deny = (msg: string, status = 403) =>
  new NextResponse(
    `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>관리자 전용</title>` +
      `<body style="font-family:system-ui,sans-serif;max-width:32rem;margin:15vh auto;padding:0 16px;line-height:1.6;color:#0f2a3d">` +
      `<h1 style="font-size:1.3rem">관리자 전용 화면입니다</h1><p>${msg}</p><p><a href="/">포털로 돌아가기</a></p></body>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } },
  );

export async function middleware(req: NextRequest) {
  const headers = new Headers(req.headers);
  headers.delete("x-console-staff");
  headers.delete("x-console-name");

  const team = (process.env.CF_ACCESS_TEAM_DOMAIN ?? "").replace(/^https?:\/\//, "").replace(/\/+$/, "");
  const aud = process.env.CF_ACCESS_AUD ?? "";
  const accessOn = !!(team && aud);
  const list = users();
  const basicOn = !accessOn || process.env.CONSOLE_BASIC_FALLBACK === "1";

  if (accessOn) {
    const email = await accessEmail(req, team, aud);
    if (email) {
      const a = admins().find((x) => x.email === email);
      if (!a) return deny("허용된 관리자 이메일이 아닙니다. 다른 계정으로 로그인했다면 <a href=\"/cdn-cgi/access/logout\">로그아웃</a> 후 다시 시도해 주세요.");
      headers.set("x-console-staff", a.staff);
      headers.set("x-console-name", encodeURIComponent(email));
      return NextResponse.next({ request: { headers } });
    }
    if (!basicOn) return deny("관리자 로그인(Cloudflare 이메일 인증)을 거쳐 들어와 주세요. 포털 오른쪽 위 <b>관리자</b> 버튼을 누르면 로그인 화면으로 갑니다.");
  }

  if (!list.length) {
    const demo = process.env.CONSOLE_DEMO === "1" && !process.env.SUPABASE_URL;
    if (demo) return NextResponse.next({ request: { headers } });
    return new NextResponse("Not found", { status: 404 });
  }

  const auth = req.headers.get("authorization") ?? "";
  if (auth.startsWith("Basic ")) {
    let decoded = "";
    try { decoded = atob(auth.slice(6)); } catch {}
    const i = decoded.indexOf(":");
    const name = decoded.slice(0, i), pass = decoded.slice(i + 1);
    const u = list.find((x) => same(x.name, name) && same(x.pass, pass));
    if (u) {
      headers.set("x-console-staff", u.staff);
      headers.set("x-console-name", encodeURIComponent(u.name));
      return NextResponse.next({ request: { headers } });
    }
  }
  return new NextResponse("편집 콘솔 로그인이 필요합니다", {
    status: 401,
    headers: { "WWW-Authenticate": 'Basic realm="Travel.with.Jaws console", charset="UTF-8"', "Cache-Control": "no-store" },
  });
}

export const config = { matcher: ["/console/:path*"] };
