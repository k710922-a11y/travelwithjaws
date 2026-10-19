"use client";
import { useState } from "react";
import { send } from "./Track";

type Prep = { before?: string[]; onsite?: string[]; official_contact?: string };

export default function PrepCard({ jobNo, title, place, prep, checked }:
  { jobNo: string; title: string; place: string; prep: Prep; checked: string }) {
  const [msg, setMsg] = useState("");

  // 전달받은 사람이 이미지/텍스트만 받아도 장소·확인 시점·출처를 알 수 있게
  const text = [
    `[준비카드] ${place}`,
    `질문: ${title}`,
    prep.before?.length ? `\n■ 예약 전에 확인\n${prep.before.map((x) => `- ${x}`).join("\n")}` : "",
    prep.onsite?.length ? `\n■ 현장에서 확인\n${prep.onsite.map((x) => `- ${x}`).join("\n")}` : "",
    prep.official_contact ? `\n문의: ${prep.official_contact}` : "",
    `\n마지막 확인 ${checked} · 최신 내용: ${typeof location !== "undefined" ? location.href : ""}`,
  ].filter(Boolean).join("\n");

  async function share() {
    send(jobNo, "share");
    try {
      if (navigator.share) { await navigator.share({ title: `준비카드 · ${place}`, text }); return; }
    } catch { return; }
    copy();
  }
  async function copy() {
    send(jobNo, "card_save");
    try { await navigator.clipboard.writeText(text); setMsg("복사했어요. 메모나 대화방에 붙여 넣으세요."); }
    catch { setMsg("복사가 막혀 있어요. 화면을 길게 눌러 선택해 주세요."); }
  }

  return (
    <div className="prep">
      {prep.before?.length ? (<><h3>예약 전에 확인</h3><ul>{prep.before.map((x, i) => <li key={i}>{x}</li>)}</ul></>) : null}
      {prep.onsite?.length ? (<><h3>현장에서 확인</h3><ul>{prep.onsite.map((x, i) => <li key={i}>{x}</li>)}</ul></>) : null}
      {prep.official_contact && <p className="note">문의 경로: {prep.official_contact}</p>}
      <div className="actions" style={{ gridTemplateColumns: "1fr 1fr" }}>
        <button className="btn" onClick={share}>함께 갈 사람에게 보내기</button>
        <button className="btn" onClick={copy}>텍스트로 저장</button>
      </div>
      {msg && <p className="note" role="status">{msg}</p>}
    </div>
  );
}
