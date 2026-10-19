import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

// 정정 요청 접수. 개인 연락처는 받지 않는다 (계획서 43쪽: 필요 없는 정보는 받지 않음).
// 서버 전용 서비스 키로만 기록 — 브라우저에는 노출되지 않음.
export async function POST(req: NextRequest) {
  const form = await req.formData();
  const job = String(form.get("job") ?? "").slice(0, 20);
  const who = String(form.get("who") ?? "visitor").slice(0, 20);
  const reason = String(form.get("reason") ?? "").trim().slice(0, 2000);
  const proof = String(form.get("proof") ?? "").trim().slice(0, 500);
  if (reason.length < 5) return NextResponse.redirect(new URL(`/policy?job=${job}&r=short#correction`, req.url), 303);

  const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (url && key) {
    const db = createClient(url, key, { db: { schema: "trip" }, auth: { persistSession: false } });
    let place_id: string | null = null;
    if (job) {
      const { data } = await db.from("content_jobs").select("place_id").eq("job_no", job).maybeSingle();
      place_id = data?.place_id ?? null;
    }
    await db.from("corrections").insert({
      place_id, requester: who, reason: job ? `[${job}] ${reason}` : reason, proof_uri: proof || null,
    });
  }
  return NextResponse.redirect(new URL(`/policy?job=${job}&r=ok#correction`, req.url), 303);
}
