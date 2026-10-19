import Link from "next/link";
import { getFeed, PLATFORM_KO } from "@/lib/console";
import { FeedActions } from "@/components/console/Forms";

type Props = { searchParams: Promise<{ s?: string }> };
const TABS = [["candidate", "승인 대기"], ["approved", "공개 중"], ["hidden", "숨김"]];

export default async function FeedPage({ searchParams }: Props) {
  const { s = "candidate" } = await searchParams;
  const rows = await getFeed(s);
  return (
    <>
      <header className="ch">
        <h1>피드 승인</h1>
        <p>포털에 올라갈 콘텐츠를 확인합니다. 요약은 출처가 요약을 허락했거나 자사 채널일 때만 공개됩니다.</p>
      </header>
      <nav className="flow" aria-label="피드 상태">
        {TABS.map(([k, l]) => <Link key={k} href={`/console/feed?s=${k}`} className={s === k ? "on" : ""}>{l}</Link>)}
      </nav>
      <div className="cards">
        {rows.length === 0 && <p className="empty">이 목록이 비어 있습니다.</p>}
        {rows.map((f) => (
          <article key={f.id} className="fcard">
            <div className="fmeta">
              <span className={`pfc pf-${f.platform}`}>{PLATFORM_KO[f.platform] ?? f.platform}</span>
              <span>{f.creator}</span><span>{f.published_at}</span>
              <span className={`agr agr-${f.agreement}`}>{f.agreement === "agreed" ? "협약" : f.agreement === "none" ? "협약 없음" : f.agreement}</span>
            </div>
            <h2><a href={f.url} target="_blank" rel="noopener">{f.title}</a></h2>
            <p className="place">{f.place_label} · {f.region} · 바다↔도시 {f.sea_city > 0 ? `도시 ${f.sea_city}` : f.sea_city < 0 ? `바다 ${-f.sea_city}` : "중간"}</p>
            {f.summary_allowed
              ? <p className="sum">{f.summary ?? "요약 미작성"} <em>({f.summary_status === "verified" ? "확인완료" : f.summary_status === "draft" ? "초안" : "없음"})</em></p>
              : <p className="sum none">요약 허락이 없는 출처라 포털에는 제목과 원본 링크만 나갑니다.</p>}
            {f.sponsored && <p className="spon">{f.disclosure}</p>}
            <FeedActions id={f.id} summaryAllowed={f.summary_allowed} summaryStatus={f.summary_status} />
          </article>
        ))}
      </div>
    </>
  );
}
