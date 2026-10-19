import { createClient } from "@supabase/supabase-js";
import demo from "./portalDemo.json";

export type FeedItem = {
  id: string; platform: string; creator: string; title: string; published: string; duration: string;
  place: string; region: string; theme: string; segment: string; seaCity: number; with: string[];
  summary: string | null; summaryReason?: string | null; evidence: "official" | "review" | "none";
  sponsored: boolean; disclosure?: string | null; url: string; job?: string | null; ledger?: number[];
};
export type Collection = { id: string; title: string; sub: string; mood: "sea" | "mix" | "city"; items: string[] };
export type PortalData = { items: FeedItem[]; collections: Collection[]; themes: { key: string; label: string; segment: string }[] };

const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_ANON_KEY;

// 공개 뷰(public_feed / public_collections / public_cards)만 읽는다
export async function getPortalData(): Promise<PortalData> {
  if (!url || !key) return demo as unknown as PortalData;
  const db = createClient(url, key, { db: { schema: "trip" }, auth: { persistSession: false } });
  const [{ data: feed, error: e1 }, { data: cols, error: e2 }, { data: cards }] = await Promise.all([
    db.from("public_feed").select("*").order("published_at", { ascending: false }).limit(120),
    db.from("public_collections").select("*").order("published_at", { ascending: false }),
    db.from("public_cards").select("version_id, claim_kind"),
  ]);
  if (e1) throw e1;
  if (e2) throw e2;
  const order = ["fact", "experience", "interpretation", "unverified"];
  const ledger = new Map<string, number[]>();
  for (const c of cards ?? []) {
    const l = ledger.get(c.version_id) ?? [0, 0, 0, 0];
    l[order.indexOf(c.claim_kind)]++;
    ledger.set(c.version_id, l);
  }
  const items: FeedItem[] = (feed ?? []).map((f: any) => ({
    id: f.id, platform: f.platform, creator: f.creator, title: f.title, published: String(f.published_at),
    duration: f.duration_label ?? "", place: f.place_label ?? "", region: f.region ?? "", theme: f.theme, segment: f.segment,
    seaCity: f.sea_city ?? 0, with: f.companions ?? [], summary: f.summary, summaryReason: f.summary_reason,
    evidence: f.evidence, sponsored: f.sponsored, disclosure: f.disclosure, url: f.url, job: f.job_no,
    ledger: f.platform === "hub_doc" ? ledger.get(f.id) : undefined,
  }));
  const collections: Collection[] = (cols ?? []).map((c: any) => ({ id: c.slug, title: c.title, sub: c.subtitle ?? "", mood: c.mood, items: c.item_ids }));
  return { items, collections, themes: (demo as any).themes };
}

// 히어로 영상: 권리 승인된 자산의 공개 주소만 넣는다 (없으면 캔버스 장면)
export function heroVideo() {
  const src = process.env.HERO_VIDEO_URL;
  return src ? { src, poster: process.env.HERO_VIDEO_POSTER ?? "" } : null;
}
