import { createClient } from "@supabase/supabase-js";
import { demoHub, demoCards } from "./demo";

export type HubRow = {
  job_no: string;
  question: string;
  segment: "domestic_kr" | "inbound";
  slug: string;
  official_name: string;
  local_name: string | null;
  names_i18n: Record<string, string>;
  region: string | null;
  theme: string;
  sub_questions: string[];
  lang: string;
  title: string;
  description: string | null;
  sponsored: boolean;
  disclosure: string | null;
  partner_links: { label: string; operator: string; url: string }[];
  prep_card: { before?: string[]; onsite?: string[]; official_contact?: string };
  checked_at: string | null;
  version_id: string;
  youtube_url: string | null;
  is_demo?: boolean;
};

export type Card = {
  version_id: string;
  claim_id: string;
  claim_kind: "fact" | "experience" | "interpretation" | "unverified";
  body: string;
  evidence_kind: "official" | "review" | "editorial" | null;
  source_url: string | null;
  author: string | null;
  observed_at: string | null;
  room_type: string | null;
  segment_start: number | null;
  segment_end: number | null;
};

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_ANON_KEY;
export const DEMO = !url || !key;

// 공개 뷰(public_hub / public_cards)만 읽는다 — 승인·공개된 것만 노출됨
const db = DEMO ? null : createClient(url!, key!, { db: { schema: "trip" }, auth: { persistSession: false } });

export async function listHub(): Promise<HubRow[]> {
  if (!db) return demoHub;
  const { data, error } = await db.from("public_hub").select("*").order("checked_at", { ascending: false });
  if (error) throw error;
  return data as HubRow[];
}

export async function getHub(jobNo: string): Promise<{ hub: HubRow | null; cards: Card[] }> {
  if (!db) {
    const hub = demoHub.find((h) => h.job_no === jobNo) ?? null;
    return { hub, cards: hub ? demoCards.filter((c) => c.version_id === hub.version_id) : [] };
  }
  const { data: hub, error } = await db.from("public_hub").select("*").eq("job_no", jobNo).maybeSingle();
  if (error) throw error;
  if (!hub) return { hub: null, cards: [] };
  const { data: cards, error: e2 } = await db.from("public_cards").select("*").eq("version_id", hub.version_id);
  if (e2) throw e2;
  return { hub: hub as HubRow, cards: (cards ?? []) as Card[] };
}

export function sourceLink(c: Card): string | null {
  if (!c.source_url) return null;
  if (c.segment_start != null && /youtu\.?be/.test(c.source_url)) {
    const u = new URL(c.source_url);
    u.searchParams.set("t", `${c.segment_start}s`);
    return u.toString();
  }
  return c.source_url;
}

export function mmss(s: number | null) {
  if (s == null) return "";
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export const THEMES: Record<string, string> = {
  youth_mood: "청년 감성", value: "가성비", worth: "가심비", premium: "고급형",
  couple_midlife: "중년부부", family: "가족", big_family: "대가족", nature: "자연·해변",
  hanok_kculture: "한옥·한류", tech_korea: "첨단한국", night_food: "야간·미식",
};
