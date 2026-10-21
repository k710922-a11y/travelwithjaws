import DocShell from "@/components/DocShell";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getHub, sourceLink, mmss, THEMES, type Card } from "@/lib/data";
import Track, { TrackedLink } from "@/components/Track";
import PrepCard from "@/components/PrepCard";

export const revalidate = 300;

type Props = { params: Promise<{ job: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { job } = await params;
  const { hub } = await getHub(job);
  if (!hub) return {};
  return { title: hub.question, description: hub.description ?? undefined };
}

const SECTIONS: { kind: Card["claim_kind"]; title: string; hint: string; color: string }[] = [
  { kind: "fact", title: "공식 안내에서 확인한 것", hint: "시설이 공지한 내용입니다. 일정·객실에 따라 달라질 수 있어요.", color: "var(--official)" },
  { kind: "experience", title: "방문자가 경험한 것", hint: "특정 방문자가 특정 조건에서 말한 내용입니다. 객실·시점이 다르면 함께 비교하지 마세요.", color: "var(--review)" },
  { kind: "interpretation", title: "편집팀의 해석", hint: "위 자료를 보고 정리한 선택 조언입니다. 사실 확인과 구분해 읽어 주세요.", color: "var(--editorial)" },
  { kind: "unverified", title: "아직 확인하지 못한 것", hint: "예약 전에 직접 확인이 필요한 항목입니다.", color: "var(--unverified)" },
];

export default async function HubPage({ params }: Props) {
  const { job } = await params;
  const { hub, cards, photo } = await getHub(job);
  if (!hub) notFound();

  const byClaim = new Map<string, Card[]>();
  for (const c of cards) byClaim.set(c.claim_id, [...(byClaim.get(c.claim_id) ?? []), c]);
  const claims = [...byClaim.values()];
  const checked = hub.checked_at ? new Date(hub.checked_at).toLocaleDateString("ko-KR") : "미기록";

  return (
    <DocShell demo={hub.is_demo}><main>
      <Track jobNo={hub.job_no} event="hub_arrive" />
      <p className="eyebrow">
        <span className="chip">{hub.segment === "inbound" ? "방한" : "국내"}</span>
        <span className="chip">{THEMES[hub.theme] ?? hub.theme}</span>
        <span>마지막 확인 {checked}</span>
        <span>· {hub.job_no}</span>
      </p>
      {photo && (
        <figure className="docph">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={`${photo.uri}&w=1200`} srcSet={`${photo.uri}&w=1200 1x, ${photo.uri}&w=2000 2x`} alt="" />
          {photo.credit && <figcaption>사진: {photo.credit.replace(/^Photo: /, "")} · 참고용 사진</figcaption>}
        </figure>
      )}
      <h1>{hub.question}</h1>
      <p className="place">
        <b>{hub.official_name}</b>
        {hub.local_name && hub.local_name !== hub.official_name && <> · {hub.local_name}</>}
        {hub.names_i18n?.en && <> · {hub.names_i18n.en}</>}
        {hub.region && <> · {hub.region}</>}
      </p>
      {hub.description && <p className="lead">{hub.description}</p>}

      {hub.sponsored && hub.disclosure && (
        <p className="disclose"><b>제휴·자료 제공 안내</b><br />{hub.disclosure}. 자료 제공 여부와 관계없이 같은 기준으로 확인하고, 불리한 경험도 지우지 않습니다.</p>
      )}

      {SECTIONS.map((s) => {
        const items = claims.filter((g) => g[0].claim_kind === s.kind);
        if (!items.length) return null;
        return (
          <section key={s.kind}>
            <h2><span className="dot" style={{ background: s.color }} />{s.title}</h2>
            <p className="hint">{s.hint}</p>
            {items.map((g) => {
              const c = g[0];
              return (
                <div key={c.claim_id} className={`card k-${s.kind}`}>
                  <p>{c.body}</p>
                  {g.some((e) => e.evidence_kind) && (
                    <div className="meta">
                      {g.filter((e) => e.evidence_kind).map((e, i) => {
                        const href = sourceLink(e);
                        return (
                          <span key={i}>
                            {e.author && <>{e.author}</>}
                            {e.room_type && <> · {e.room_type}</>}
                            {e.observed_at && <> · {e.observed_at}</>}
                            {href && (
                              <> · <TrackedLink jobNo={hub.job_no} event="source_open" href={href}>
                                {e.segment_start != null ? `원문 ${mmss(e.segment_start)}부터 보기` : "원문 보기"}
                              </TrackedLink></>
                            )}
                          </span>
                        );
                      })}
                    </div>
                  )}
                </div>
              );
            })}
          </section>
        );
      })}

      {(hub.prep_card?.before?.length || hub.prep_card?.onsite?.length) ? (
        <section>
          <h2>준비카드</h2>
          <p className="hint">함께 가는 사람과 나눠 보거나 저장해 두세요. 비밀 요령이 아니라 확인할 질문 목록입니다.</p>
          <PrepCard jobNo={hub.job_no} title={hub.question} place={hub.official_name} prep={hub.prep_card} checked={checked} />
        </section>
      ) : null}

      {hub.partner_links?.length > 0 && (
        <section>
          <h2>조건 확인하러 가기</h2>
          <p className="hint">외부 예약 사업자의 화면으로 이동합니다. 재고·요금·취소 규정은 그곳에서 최종 확인해 주세요. 제휴 링크일 수 있습니다.</p>
          <div className="actions">
            {hub.partner_links.map((l, i) => (
              <TrackedLink key={i} jobNo={hub.job_no} event="partner_click" href={l.url} className="btn primary" rel="sponsored noopener">
                {l.label}<small>{l.operator}(으)로 이동 · 외부 사이트</small>
              </TrackedLink>
            ))}
          </div>
        </section>
      )}

      <section>
        <p className="note">
          정보가 바뀌었거나 맥락이 빠졌다면 <a href={`/policy?job=${hub.job_no}#correction`}>정정 요청</a>을 남겨 주세요.
          {hub.youtube_url && <> · <a href={hub.youtube_url}>원본 쇼츠 보기</a></>}
        </p>
      </section>
    </main></DocShell>
  );
}
