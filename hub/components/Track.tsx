"use client";
import { useEffect } from "react";

type Ev = "hub_arrive" | "source_open" | "partner_click" | "card_save" | "share";

// 30분 비활동 시 새 세션 (계획서 45쪽 초기안). 개인 식별정보는 보내지 않는다.
function sessionId(): string {
  try {
    const now = Date.now();
    const raw = sessionStorage.getItem("th_sid");
    if (raw) {
      const [id, last] = raw.split("|");
      if (now - Number(last) < 30 * 60 * 1000) {
        sessionStorage.setItem("th_sid", `${id}|${now}`);
        return id;
      }
    }
    const id = crypto.randomUUID();
    sessionStorage.setItem("th_sid", `${id}|${now}`);
    return id;
  } catch {
    return "nostore";
  }
}

function ref(): string {
  try {
    const p = new URLSearchParams(location.search);
    return p.get("src") ?? (document.referrer ? new URL(document.referrer).hostname : "direct");
  } catch {
    return "unknown";
  }
}

export function send(jobNo: string, event: Ev) {
  const body = JSON.stringify({ session_id: sessionId(), job_no: jobNo, event, ref: ref() });
  try {
    if (navigator.sendBeacon) navigator.sendBeacon("/api/event", new Blob([body], { type: "application/json" }));
    else fetch("/api/event", { method: "POST", body, headers: { "content-type": "application/json" }, keepalive: true });
  } catch {}
}

export default function Track({ jobNo, event }: { jobNo: string; event: Ev }) {
  useEffect(() => { send(jobNo, event); }, [jobNo, event]);
  return null;
}

export function TrackedLink({ jobNo, event, children, ...rest }:
  { jobNo: string; event: Ev } & React.AnchorHTMLAttributes<HTMLAnchorElement>) {
  return (
    <a target="_blank" rel="noopener" {...rest} onClick={() => send(jobNo, event)}>
      {children}
    </a>
  );
}
