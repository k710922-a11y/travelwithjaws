import { NextRequest, NextResponse } from "next/server";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { adminConfig, readSession, same, SESSION_COOKIE } from "./lib/adminSession";

// 편집 콘솔(관리자) 보호 — 아래 중 설정된 방식으로 입장
//
// 1) 관리자 로그인 (기본): /admin-login 에서 이메일 + 비밀번호 → 서명된 세션 쿠키(12시간)
//    ADMIN_EMAIL="k710922@gmail.com", ADMIN_PASSWORD_HASH="pbkdf2_sha256:…", ADMIN_SESSION_SECRET, ADMIN_STAFF(선택)
//    비밀번호는 deploy/minipc/set-admin-password.sh 로 대표가 직접 정한다 (평문 저장 없음).
// 2) Cloudflare Access (선택): CF_ACCESS_TEAM_DOMAIN + CF_ACCESS_AUD + CONSOLE_ADMINS="이메일=staff_uuid"
//    설정되면 Cloudflare 이메일 인증을 통과한 허용 이메일만 입장 (서명 토큰을 서버에서 재검증).
// 3) 예전 방식: HTTP 기본 인증 CONSOLE_USERS="이름:비밀번호:staff_uuid" — 관리자 로그인이 설정되면 꺼진다.
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
    return typeof payload.email === "string" ? payload.email.toLowerCase() : null;
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
  const pass = (staff: string, name: string) => {
    headers.set("x-console-staff", staff);
    headers.set("x-console-name", encodeURIComponent(name));
    return NextResponse.next({ request: { headers } });
  };

  // 2) Cloudflare Access 가 설정되면 그것만 받는다
  const team = (process.env.CF_ACCESS_TEAM_DOMAIN ?? "").replace(/^https?:\/\//, "").replace(/\/+$/, "");
  const aud = process.env.CF_ACCESS_AUD ?? "";
  if (team && aud) {
    const email = await accessEmail(req, team, aud);
    if (!email) return deny("관리자 로그인(Cloudflare 이메일 인증)을 거쳐 들어와 주세요. 포털 오른쪽 위 <b>관리자</b> 버튼을 누르면 로그인 화면으로 갑니다.");
    const a = admins().find((x) => x.email === email);
    if (!a) return deny("허용된 관리자 이메일이 아닙니다. 다른 계정으로 로그인했다면 <a href=\"/cdn-cgi/access/logout\">로그아웃</a> 후 다시 시도해 주세요.");
    return pass(a.staff, email);
  }

  // 1) 관리자 로그인 (이메일 + 비밀번호 → 세션 쿠키)
  const admin = adminConfig();
  if (admin.on) {
    const email = await readSession(req.cookies.get(SESSION_COOKIE)?.value, admin.secret);
    if (email && same(email, admin.email)) return pass(admin.staff, email);
    const login = new URL("/admin-login", req.url);
    login.searchParams.set("next", req.nextUrl.pathname + req.nextUrl.search);
    if (req.method !== "GET") return deny("로그인이 만료되었습니다. 다시 로그인해 주세요.", 401);
    return NextResponse.redirect(login);
  }

  // 3) 예전 방식 (관리자 로그인을 설정하기 전까지)
  const list = users();
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
    const name = decoded.slice(0, i), pw = decoded.slice(i + 1);
    const u = list.find((x) => same(x.name, name) && same(x.pass, pw));
    if (u) return pass(u.staff, u.name);
  }
  return new NextResponse("편집 콘솔 로그인이 필요합니다", {
    status: 401,
    headers: { "WWW-Authenticate": 'Basic realm="Travel.with.Jaws console", charset="UTF-8"', "Cache-Control": "no-store" },
  });
}

export const config = { matcher: ["/console/:path*"] };
