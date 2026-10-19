"use server";
import { revalidatePath } from "next/cache";
import { rpc, whoami } from "@/lib/console";

export type ActionState = { ok: boolean; message: string } | null;

async function actor() {
  const { staff } = await whoami();
  return staff;
}

export async function setJobStatus(_: ActionState, form: FormData): Promise<ActionState> {
  const staff = await actor();
  const job = String(form.get("job") ?? ""), to = String(form.get("to") ?? ""), reason = String(form.get("reason") ?? "").trim();
  if (to === "held" && reason.length < 3) return { ok: false, message: "보류 사유를 적어 주세요." };
  const r = await rpc("console_set_job_status", { p_job_no: job, p_to: to, p_actor: staff, p_reason: reason || null });
  if (r.ok) revalidatePath("/console");
  return r.ok ? { ok: true, message: `${job} 상태를 바꿨습니다.` } : r;
}

export async function feedAction(_: ActionState, form: FormData): Promise<ActionState> {
  const staff = await actor();
  const id = String(form.get("id") ?? ""), action = String(form.get("op") ?? "");
  const r = await rpc("console_feed_action", { p_item: id, p_action: action, p_actor: staff });
  if (r.ok) { revalidatePath("/console/feed"); revalidatePath("/"); }
  const done: Record<string, string> = { approve: "포털에 공개했습니다.", hide: "숨겼습니다.", verify_summary: "요약을 확인완료로 바꿨습니다." };
  return r.ok ? { ok: true, message: done[action] ?? "반영했습니다." } : r;
}

export async function closeCorrection(_: ActionState, form: FormData): Promise<ActionState> {
  const staff = await actor();
  const id = String(form.get("id") ?? ""), status = String(form.get("status") ?? ""), resolution = String(form.get("resolution") ?? "").trim();
  if (status !== "investigating" && resolution.length < 3) return { ok: false, message: "처리 결과를 적어 주세요." };
  const r = await rpc("console_close_correction", { p_id: id, p_status: status, p_resolution: resolution || null, p_actor: staff });
  if (r.ok) revalidatePath("/console/corrections");
  return r.ok ? { ok: true, message: "정정 요청을 처리했습니다." } : r;
}
