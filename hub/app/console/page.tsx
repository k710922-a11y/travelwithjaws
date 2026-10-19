import Link from "next/link";
import { getJobs, getSummary, STATUS_KO } from "@/lib/console";
import { JobStatusForm } from "@/components/console/Forms";

const FLOW = ["received", "material_check", "ready", "rendering", "review", "approved", "published", "held"];

type Props = { searchParams: Promise<{ s?: string }> };

export default async function JobsPage({ searchParams }: Props) {
  const { s: filter } = await searchParams;
  const [jobs, sum] = await Promise.all([getJobs(), getSummary()]);
  const count = (st: string) => jobs.filter((j) => j.status === st).length;
  const list = filter ? jobs.filter((j) => j.status === filter) : jobs;
  const toLong = Math.max(0, sum.longform_threshold - sum.public_shorts);

  return (
    <>
      <header className="ch">
        <h1>작업 현황</h1>
        <p>쇼츠 작업 {sum.jobs}건 · 공개 쇼츠 {sum.public_shorts}편{toLong ? ` · 롱폼 착수 조건까지 ${toLong}편 남음` : " · 롱폼 착수 조건 충족"}</p>
      </header>

      <nav className="flow" aria-label="상태별 보기">
        <Link href="/console" className={!filter ? "on" : ""}>전체 <b>{jobs.length}</b></Link>
        {FLOW.map((st) => (
          <Link key={st} href={`/console?s=${st}`} className={`${filter === st ? "on" : ""} ${st === "held" ? "warnc" : ""}`}>
            {STATUS_KO[st]} <b>{count(st)}</b>
          </Link>
        ))}
      </nav>

      <div className="tbl-wrap">
        <table className="ctable">
          <thead>
            <tr><th>작업</th><th>질문 · 장소</th><th>상태</th><th>제작 · 검수 · 승인</th><th>차단 사유</th><th>다음 단계</th></tr>
          </thead>
          <tbody>
            {list.length === 0 && <tr><td colSpan={6} className="empty">이 상태의 작업이 없습니다.</td></tr>}
            {list.map((j) => (
              <tr key={j.id} className={j.status === "held" ? "row-held" : ""}>
                <td className="mono">{j.job_no}<small>v{j.version ?? "-"} · {j.segment === "inbound" ? "방한" : "국내"}</small></td>
                <td className="q"><b>{j.question}</b><small>{j.place} · {j.region ?? ""}{j.question_type ? ` · ${j.question_type}` : ""}{j.sponsored ? " · 제휴" : ""}</small></td>
                <td>
                  <span className={`st st-${j.status}`}>{STATUS_KO[j.status]}</span>
                  {j.youtube_status && <small className="yt">유튜브 {j.youtube_status === "public" ? "공개" : j.youtube_status === "uploaded_private" ? "비공개 업로드" : j.youtube_status}</small>}
                  {j.hold_reason && <small className="hold">{j.hold_reason}</small>}
                </td>
                <td><div className="who"><span>{j.made_by ?? "—"}</span><span>{j.reviewed_by ?? "—"}</span><span>{j.approved_by ?? "—"}</span></div></td>
                <td>{j.blockers.length ? <ul className="blk">{j.blockers.map((b) => <li key={b}>{b}</li>)}</ul> : <span className="clear">없음</span>}</td>
                <td><JobStatusForm job={j.job_no} next={j.next_statuses} blockers={j.blockers} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="foot-note">상태 변경은 DB 규칙을 그대로 따릅니다. 권리 미확인 자산, 근거 미확인 주장, 검수·승인자 누락이 있으면 바뀌지 않고 그 사유가 표시됩니다.</p>
    </>
  );
}
