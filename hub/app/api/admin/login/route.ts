import { NextRequest, NextResponse } from "next/server";
import { adminConfig, checkPassword, makeSession, same, SESSION_COOKIE, SESSION_HOURS } from "@/lib/adminSession";

export const dynamic = "force-dynamic";

// 같은 주소에서 15분에 10번 틀리면 15분 동안 막는다 (무차별 대입 방지)
const tries = new Map<string, { n: number; until: number }>();
const WINDOW = 15 * 60 * 1000, MAX = 10;

function ip(req: NextRequest) {
  return req.headers.get("cf-connecting-ip") ?? req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "local";
}
const safeNext = (n: string | null) => (n && n.startsWith("/console") && !n.startsWith("//") ? n : "/console");

export async function POST(req: NextRequest) {
  const form = await req.formData();
  const email = String(form.get("email") ?? "").trim().toLowerCase();
  const password = String(form.get("password") ?? "");
  const next = safeNext(String(form.get("next") ?? ""));
  const back = (code: string) => {
    const u = new URL("/admin-login", req.url);
    u.searchParams.set("e", code); u.searchParams.set("next", next);
    return NextResponse.redirect(u, 303);
  };

  const cfg = adminConfig();
  if (!cfg.on) return back("off");

  const key = ip(req), now = Date.now();
  const t = tries.get(key);
  if (t && t.until > now && t.n >= MAX) return back("locked");

  const ok = same(email, cfg.email) && (await checkPassword(password, cfg.hash));
  if (!ok) {
    const cur = t && t.until > now ? t : { n: 0, until: now + WINDOW };
    cur.n += 1; tries.set(key, cur);
    await new Promise((r) => setTimeout(r, 800));
    return back(cur.n >= MAX ? "locked" : "bad");
  }
  tries.delete(key);

  const res = NextResponse.redirect(new URL(next, req.url), 303);
  res.cookies.set(SESSION_COOKIE, await makeSession(cfg.email, cfg.secret), {
    httpOnly: true, secure: req.nextUrl.protocol === "https:" || req.headers.get("x-forwarded-proto") === "https",
    sameSite: "lax", path: "/", maxAge: SESSION_HOURS * 3600,
  });
  return res;
}
