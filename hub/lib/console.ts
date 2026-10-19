import "server-only";
import { headers } from "next/headers";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import * as demo from "./consoleDemo";

// 서버 전용: service_role 키로 콘솔 뷰·함수에 접속 (브라우저로 키가 나가지 않음)
const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
export const CONSOLE_DEMO = !url || !key;

let client: SupabaseClient<any, any, any> | null = null;
function db() {
  if (CONSOLE_DEMO) return null;
  client ??= createClient(url!, key!, { db: { schema: "trip" }, auth: { persistSession: false } });
  return client;
}

export async function whoami() {
  const h = await headers();
  return { staff: h.get("x-console-staff"), name: decodeURIComponent(h.get("x-console-name") ?? "") || "데모 보기" };
}

export type Job = {
  id: string; job_no: string; question: string; segment: string; status: string; hold_reason: string | null;
  question_type: string | null; updated_at: string; place: string; region: string | null; theme: string;
  version: number | null; title: string | null; render_uri: string | null; sponsored: boolean | null;
  made_by: string | null; reviewed_by: string | null; approved_by: string | null;
  blockers: string[]; youtube_status: string | null; youtube_url: string | null; next_statuses: string[];
};
export type FeedRow = {
  id: string; title: string; status: string; published_at: string; url: string; platform: string; creator: string;
  agreement: string; summary_allowed: boolean; summary: string | null; summary_status: string; sponsored: boolean;
  disclosure: string | null; place_label: string | null; region: string | null; theme: string; sea_city: number;
};
export type Summary = {
  jobs: number; in_review: number; held: number; published: number; feed_candidates: number;
  open_corrections: number; public_shorts: number; longform_threshold: number; longform_ready: number;
};
export type Candidate = { bundle_type: string; bundle_key: string; shorts: number; eligible_shorts: number; has_sponsored: boolean; ready: boolean; reason: string };
export type Longform = { id: string; code: string; title: string; format: string; bundle_key: string; status: string; hold_reason: string | null; chapters: number; blockers: string[]; youtube_id: string | null };
export type Correction = { id: string; reason: string; requester: string | null; proof_uri: string | null; status: string; resolution: string | null; created_at: string };

async function q<T>(view: string, build?: (b: any) => any): Promise<T[]> {
  const c = db()!;
  let b: any = c.from(view).select("*");
  if (build) b = build(b);
  const { data, error } = await b;
  if (error) throw new Error(`${view}: ${error.message}`);
  return data as T[];
}

export async function getSummary(): Promise<Summary> {
  if (CONSOLE_DEMO) return demo.summary;
  return (await q<Summary>("console_summary"))[0];
}
export async function getJobs(status?: string): Promise<Job[]> {
  if (CONSOLE_DEMO) return status ? demo.jobs.filter((j) => j.status === status) : demo.jobs;
  return q<Job>("console_jobs", (b) => (status ? b.eq("status", status) : b).order("updated_at", { ascending: false }).limit(200));
}
export async function getFeed(status = "candidate"): Promise<FeedRow[]> {
  if (CONSOLE_DEMO) return demo.feed.filter((f) => f.status === status);
  return q<FeedRow>("console_feed_queue", (b) => b.eq("status", status).order("published_at", { ascending: false }).limit(200));
}
export async function getCandidates(): Promise<Candidate[]> {
  if (CONSOLE_DEMO) return demo.candidates;
  return q<Candidate>("longform_candidates");
}
export async function getLongforms(): Promise<Longform[]> {
  if (CONSOLE_DEMO) return demo.longforms;
  return q<Longform>("console_longform", (b) => b.order("created_at", { ascending: false }));
}
export async function getSettings(): Promise<Record<string, number>> {
  if (CONSOLE_DEMO) return demo.settings;
  return (await q<Record<string, number>>("longform_settings"))[0];
}
export async function getCorrections(): Promise<Correction[]> {
  if (CONSOLE_DEMO) return demo.corrections;
  return q<Correction>("corrections", (b) => b.in("status", ["received", "investigating"]).order("created_at", { ascending: true }));
}

export async function rpc(fn: string, args: Record<string, unknown>) {
  if (CONSOLE_DEMO) return { ok: false, message: "데모 모드에서는 저장되지 않습니다. DB를 연결하면 실제로 반영됩니다." };
  const { error } = await db()!.rpc(fn, args);
  // DB 규칙이 거부한 사유를 그대로 보여 준다 (예: 승인 차단: 근거 미확인 핵심 주장 1건)
  return error ? { ok: false, message: error.message } : { ok: true, message: "" };
}

export const STATUS_KO: Record<string, string> = {
  received: "접수", material_check: "자료 확인", ready: "제작 대기", rendering: "합성", review: "검수",
  approved: "승인", published: "공개", held: "보류",
};
export const PLATFORM_KO: Record<string, string> = {
  yt_shorts: "쇼츠", yt: "유튜브", ig_reels: "릴스", ig_post: "인스타", tiktok: "틱톡", blog: "블로그", official: "공식 안내", news: "기사", hub_doc: "판단 문서",
};
