import { getCandidates, getLongforms, getSettings, getSummary } from "@/lib/console";

const FORMAT_KO: Record<string, string> = { route: "지역 동선형", compare: "같은 질문 비교형", viewer_qa: "시청자 질문 답변형", inbound_prep: "방한 준비형" };
const LF_STATUS: Record<string, string> = { planning: "기획", rights_check: "권리 재확인", editing: "편집", review: "검수", approved: "승인", published: "공개", held: "보류" };

export default async function LongformPage() {
  const [cands, lfs, set, sum] = await Promise.all([getCandidates(), getLongforms(), getSettings(), getSummary()]);
  const pct = Math.min(100, Math.round((sum.public_shorts / Math.max(1, set.min_channel_shorts)) * 100));
  return (
    <>
      <header className="ch">
        <h1>롱폼</h1>
        <p>공개된 쇼츠를 묶음 기준에 따라 롱폼으로 만듭니다. 기준값은 DB 설정 표(longform_settings)에서 바꿉니다.</p>
      </header>

      <section className="gauge" aria-label="채널 누적 쇼츠">
        <div className="gl"><b>채널 공개 쇼츠 {sum.public_shorts}편</b><span>롱폼 착수 기준 {set.min_channel_shorts}편</span></div>
        <div className="gbar"><span style={{ width: `${pct}%` }} /></div>
        <ul className="rules">
          <li>묶음당 쇼츠 <b>{set.min_bundle_shorts}편</b></li>
          <li>공개 후 관측 <b>{set.min_age_days}일</b></li>
          <li>근거 재확인 <b>{set.recheck_days}일</b></li>
          <li>자산 기한 여유 <b>{set.rights_margin_days}일</b></li>
        </ul>
      </section>

      <h2 className="sh">후보 묶음</h2>
      <div className="tbl-wrap">
        <table className="ctable">
          <thead><tr><th>묶음</th><th>키</th><th className="num">쇼츠</th><th className="num">기준 통과</th><th>협찬 포함</th><th>상태</th></tr></thead>
          <tbody>
            {cands.length === 0 && <tr><td colSpan={6} className="empty">아직 공개된 쇼츠가 없습니다. 쇼츠에 지역과 질문 유형을 기록하면 묶음이 여기에 쌓입니다.</td></tr>}
            {cands.map((c) => (
              <tr key={c.bundle_type + c.bundle_key}>
                <td>{c.bundle_type === "region" ? "지역" : "질문 × 테마"}</td>
                <td><b>{c.bundle_key}</b></td>
                <td className="num">{c.shorts}</td>
                <td className="num">{c.eligible_shorts}<small> / {set.min_bundle_shorts}</small></td>
                <td>{c.has_sponsored ? "있음 (표시 필요)" : "—"}</td>
                <td>{c.ready ? <span className="st st-approved">착수 가능</span> : <span className="wait">{c.reason}</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2 className="sh">롱폼 프로젝트</h2>
      {lfs.length === 0
        ? <p className="empty">아직 롱폼 프로젝트가 없습니다. 착수 가능한 묶음이 생기면 이 묶음으로 프로젝트를 만듭니다.</p>
        : <div className="tbl-wrap"><table className="ctable">
            <thead><tr><th>코드</th><th>제목</th><th>형식 · 묶음</th><th className="num">챕터</th><th>상태</th><th>차단 사유</th></tr></thead>
            <tbody>{lfs.map((l) => (
              <tr key={l.id}>
                <td className="mono">{l.code}</td><td><b>{l.title}</b></td>
                <td>{FORMAT_KO[l.format]}<small>{l.bundle_key}</small></td><td className="num">{l.chapters}</td>
                <td><span className={`st st-${l.status}`}>{LF_STATUS[l.status]}</span>{l.hold_reason && <small className="hold">{l.hold_reason}</small>}</td>
                <td>{l.blockers.length ? <ul className="blk">{l.blockers.map((b) => <li key={b}>{b}</li>)}</ul> : <span className="clear">없음</span>}</td>
              </tr>))}
            </tbody></table></div>}
    </>
  );
}
