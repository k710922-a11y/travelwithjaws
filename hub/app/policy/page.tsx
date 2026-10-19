import DocShell from "@/components/DocShell";
import type { Metadata } from "next";

export const metadata: Metadata = { title: "편집 원칙과 정정 요청" };

type Props = { searchParams: Promise<{ job?: string; r?: string }> };

export default async function Policy({ searchParams }: Props) {
  const { job = "", r } = await searchParams;
  return (
    <DocShell><main>
      <h1>편집 원칙</h1>
      <section>
        <div className="card k-official"><p><b>공식 안내</b>는 시설이 공지한 내용과 확인 날짜를 함께 적습니다. 일정·객실에 따라 달라질 수 있습니다.</p></div>
        <div className="card k-review"><p><b>방문 경험</b>은 원작자와 협의해 받은 자막에서만 정리하고, 누가 어떤 객실·시점에서 말했는지 남기며 원문 구간으로 연결합니다. 자막이 없는 영상은 요약하지 않습니다.</p></div>
        <div className="card k-editorial"><p><b>편집 해석</b>은 여러 자료를 보고 정리한 선택 조언이며, 사실 확인과 구분해 표시합니다.</p></div>
        <div className="card k-unverified"><p>확인하지 못한 내용은 빈칸을 추측으로 채우지 않고 그대로 표시합니다.</p></div>
        <p className="note">
          자료 제공·협찬이 있는 경우 영상·설명·이 페이지에 모두 알립니다. 자료 제공을 이유로 불리한 경험을 지우거나 평가를 바꾸지 않습니다.
          예약·결제·취소는 외부 예약 사업자가 처리하며, 이 사이트는 예약을 확정하거나 시설 이용을 보장하지 않습니다.
          의료 상담이나 시술 연결은 하지 않습니다.
        </p>
      </section>

      <section id="correction">
        <h2>정정 요청</h2>
        <p className="hint">원작자·시설·이용자 누구나 남길 수 있습니다. 연락처는 받지 않으며, 처리 결과는 해당 페이지의 수정 이력으로 알려 드립니다.</p>
        {r === "ok" && <p className="disclose">접수되었습니다. 근거를 대조한 뒤 수정하거나 보류합니다.</p>}
        {r === "short" && <p className="disclose">내용을 조금 더 구체적으로 적어 주세요.</p>}
        <form action="/api/correction" method="post" className="prep">
          <input type="hidden" name="job" value={job} />
          <h3>요청하는 분</h3>
          <select name="who" className="btn" defaultValue="visitor" style={{ textAlign: "left" }}>
            <option value="visitor">이용자</option>
            <option value="creator">후기 원작자</option>
            <option value="provider">시설·자료 제공자</option>
          </select>
          <h3 style={{ marginTop: 14 }}>무엇이 다른가요? {job && <span className="note">({job})</span>}</h3>
          <textarea name="reason" required minLength={5} rows={5} className="btn" style={{ textAlign: "left", fontWeight: 400 }}
            placeholder="예: 수영장 이용 조건이 10월부터 바뀌었습니다 / 제 영상의 발언 맥락이 빠졌습니다" />
          <h3 style={{ marginTop: 14 }}>확인할 수 있는 자료 주소 (선택)</h3>
          <input name="proof" type="url" className="btn" style={{ textAlign: "left", fontWeight: 400 }} placeholder="https://" />
          <p className="note">여권·결제·건강 정보 등 개인 정보는 적지 마세요.</p>
          <button className="btn primary" type="submit">정정 요청 보내기</button>
        </form>
      </section>
    </main></DocShell>
  );
}
