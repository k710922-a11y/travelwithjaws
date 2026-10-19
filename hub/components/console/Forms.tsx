"use client";
import { useActionState, useRef, useState } from "react";
import { setJobStatus, feedAction, closeCorrection, type ActionState } from "@/app/console/actions";

const STATUS_KO: Record<string, string> = {
  received: "접수", material_check: "자료 확인", ready: "제작 대기", rendering: "합성", review: "검수",
  approved: "승인", published: "공개", held: "보류",
};

function Result({ s }: { s: ActionState }) {
  if (!s) return null;
  return <p className={`res ${s.ok ? "ok" : "bad"}`} role="status">{s.message}</p>;
}

export function JobStatusForm({ job, next, blockers }: { job: string; next: string[]; blockers: string[] }) {
  const [state, act, pending] = useActionState(setJobStatus, null);
  const [to, setTo] = useState(next[0] ?? "");
  if (!next.length) return null;
  const willBlock = (to === "approved" || to === "published") && blockers.length > 0;
  return (
    <form action={act} className="jform">
      <input type="hidden" name="job" value={job} />
      <label className="sr" htmlFor={`to-${job}`}>다음 상태</label>
      <select id={`to-${job}`} name="to" value={to} onChange={(e) => setTo(e.target.value)}>
        {next.map((n) => <option key={n} value={n}>{STATUS_KO[n] ?? n}(으)로</option>)}
      </select>
      {to === "held" && <input name="reason" id={`reason-${job}`} placeholder="보류 사유 (필수)" aria-label="보류 사유" required minLength={3} />}
      <button type="submit" disabled={pending}>{pending ? "바꾸는 중" : "상태 바꾸기"}</button>
      {willBlock && <p className="res warn">차단 사유가 남아 있어 DB가 거부합니다.</p>}
      <Result s={state} />
    </form>
  );
}

export function FeedActions({ id, summaryAllowed, summaryStatus }: { id: string; summaryAllowed: boolean; summaryStatus: string }) {
  const [state, act, pending] = useActionState(feedAction, null);
  // 누른 버튼의 값은 브라우저·전송 방식에 따라 빠질 수 있어, 누르는 순간 숨은 입력란에 직접 넣는다
  const op = useRef<HTMLInputElement>(null);
  const pick = (v: string) => () => { if (op.current) op.current.value = v; };
  return (
    <form action={act} className="factions">
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="op" ref={op} defaultValue="" />
      {summaryAllowed && summaryStatus === "draft" && <button type="submit" onClick={pick("verify_summary")} disabled={pending}>요약 확인완료</button>}
      <button type="submit" onClick={pick("approve")} className="primary" disabled={pending}>포털에 공개</button>
      <button type="submit" onClick={pick("hide")} disabled={pending}>숨기기</button>
      <Result s={state} />
    </form>
  );
}

export function CorrectionForm({ id }: { id: string }) {
  const [state, act, pending] = useActionState(closeCorrection, null);
  const st = useRef<HTMLInputElement>(null);
  const pick = (v: string) => () => { if (st.current) st.current.value = v; };
  return (
    <form action={act} className="cform">
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="status" ref={st} defaultValue="" />
      <label htmlFor={`res-${id}`} className="sr">처리 결과</label>
      <input id={`res-${id}`} name="resolution" placeholder="처리 결과 (반영·기각 시 필수)" />
      <div className="row">
        <button type="submit" onClick={pick("investigating")} disabled={pending}>확인 중으로</button>
        <button type="submit" onClick={pick("fixed")} className="primary" disabled={pending}>반영 완료</button>
        <button type="submit" onClick={pick("rejected")} disabled={pending}>기각</button>
      </div>
      <Result s={state} />
    </form>
  );
}
