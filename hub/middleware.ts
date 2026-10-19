import { NextRequest, NextResponse } from "next/server";

// 편집 콘솔 보호: HTTP 기본 인증
// CONSOLE_USERS="이름:비밀번호:staff_uuid;이름2:비밀번호2:staff_uuid2"
//   - 비어 있으면 콘솔 전체가 404 (실수로 열린 채 배포되는 것을 막음)
//   - 데모(DB 미연결)에서만 CONSOLE_DEMO=1 이면 인증 없이 읽기 전용으로 열림
// 인증된 사람의 staff id 는 x-console-staff 헤더로 서버에 전달 (외부에서 보낸 같은 헤더는 지움)

type User = { name: string; pass: string; staff: string };

function users(): User[] {
  return (process.env.CONSOLE_USERS ?? "")
    .split(";").map((s) => s.trim()).filter(Boolean)
    .map((s) => { const [name, pass, staff] = s.split(":"); return { name, pass, staff }; })
    .filter((u) => u.name && u.pass && u.staff);
}

function same(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

export function middleware(req: NextRequest) {
  const headers = new Headers(req.headers);
  headers.delete("x-console-staff");
  headers.delete("x-console-name");

  const list = users();
  const demo = process.env.CONSOLE_DEMO === "1" && !process.env.SUPABASE_URL;
  if (!list.length) {
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
