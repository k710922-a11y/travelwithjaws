import { NextResponse } from "next/server";

// Coolify 상태 확인용. DB가 연결되어 있으면 공개 뷰를 한 번 읽어 본다 (키 값은 노출하지 않음)
export const dynamic = "force-dynamic";

export async function GET() {
  const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_ANON_KEY;
  if (!url || !key) return NextResponse.json({ ok: true, db: "demo" });
  try {
    const r = await fetch(`${url}/rest/v1/public_hub?select=job_no&limit=1`, {
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Accept-Profile": "trip" }, cache: "no-store",
      signal: AbortSignal.timeout(3000),
    });
    return NextResponse.json({ ok: r.ok, db: r.ok ? "up" : `http ${r.status}` }, { status: r.ok ? 200 : 503 });
  } catch {
    return NextResponse.json({ ok: false, db: "unreachable" }, { status: 503 });
  }
}
