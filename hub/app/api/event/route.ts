import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const EVENTS = new Set(["hub_arrive", "source_open", "partner_click", "card_save", "share"]);
const BOT = /bot|crawler|spider|preview|facebookexternalhit|slurp|headless/i;

export async function POST(req: NextRequest) {
  const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_ANON_KEY;
  let b: any;
  try { b = await req.json(); } catch { return NextResponse.json({ ok: false }, { status: 400 }); }
  if (!EVENTS.has(b?.event) || typeof b?.session_id !== "string") return NextResponse.json({ ok: false }, { status: 400 });

  // 확인 가능한 자동 요청은 분모에서 제외 (기록하지 않음)
  if (BOT.test(req.headers.get("user-agent") ?? "")) return NextResponse.json({ ok: true, skipped: "bot" });
  if (!url || !key) return NextResponse.json({ ok: true, demo: true });

  const db = createClient(url, key, { db: { schema: "trip" }, auth: { persistSession: false } });
  const { error } = await db.from("hub_events").insert({
    session_id: b.session_id.slice(0, 64),
    job_no: typeof b.job_no === "string" ? b.job_no.slice(0, 20) : null,
    event: b.event,
    ref: typeof b.ref === "string" ? b.ref.slice(0, 80) : null,
  });
  return NextResponse.json({ ok: !error });
}
