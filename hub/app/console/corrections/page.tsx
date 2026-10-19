import { getCorrections } from "@/lib/console";
import { CorrectionForm } from "@/components/console/Forms";

const WHO: Record<string, string> = { visitor: "이용자", creator: "후기 원작자", provider: "시설·자료 제공자" };

export default async function CorrectionsPage() {
  const rows = await getCorrections();
  return (
    <>
      <header className="ch">
        <h1>정정 요청</h1>
        <p>열려 있는 요청은 해당 쇼츠를 롱폼 묶음에서 빼 둡니다. 반영하거나 기각하면 결과가 기록됩니다.</p>
      </header>
      <div className="cards">
        {rows.length === 0 && <p className="empty">처리할 정정 요청이 없습니다.</p>}
        {rows.map((c) => (
          <article key={c.id} className="fcard">
            <div className="fmeta"><span>{WHO[c.requester ?? ""] ?? c.requester ?? "요청자 미기재"}</span><span>{new Date(c.created_at).toLocaleString("ko-KR")}</span>
              <span className={`st st-${c.status === "received" ? "review" : "ready"}`}>{c.status === "received" ? "접수" : "확인 중"}</span></div>
            <p className="creason">{c.reason}</p>
            {c.proof_uri && <p className="place"><a href={c.proof_uri} target="_blank" rel="noopener">확인 자료 열기</a></p>}
            <CorrectionForm id={c.id} />
          </article>
        ))}
      </div>
    </>
  );
}
