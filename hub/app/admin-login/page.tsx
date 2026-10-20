import type { Metadata } from "next";
import { adminConfig } from "@/lib/adminSession";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "관리자 로그인", robots: { index: false, follow: false } };

const MSG: Record<string, string> = {
  bad: "이메일 또는 비밀번호가 맞지 않습니다.",
  locked: "여러 번 틀려서 15분 동안 로그인이 막혔습니다. 잠시 뒤 다시 시도해 주세요.",
  off: "관리자 비밀번호가 아직 설정되지 않았습니다.",
};

type Props = { searchParams: Promise<{ e?: string; next?: string }> };

export default async function AdminLogin({ searchParams }: Props) {
  const { e, next } = await searchParams;
  const on = adminConfig().on;
  return (
    <main className="alogin">
      <form method="post" action="/api/admin/login" className="acard">
        <a href="/" className="abrand">Travel.with.Jaws</a>
        <h1>관리자 로그인</h1>
        <p className="asub">편집 콘솔은 허용된 관리자만 들어올 수 있습니다.</p>
        {(e || !on) && <p className="aerr" role="alert">{MSG[e ?? "off"] ?? MSG.bad}</p>}
        <input type="hidden" name="next" value={next ?? "/console"} />
        <label>이메일<input name="email" type="email" autoComplete="username" required inputMode="email" /></label>
        <label>비밀번호<input name="password" type="password" autoComplete="current-password" required /></label>
        <button type="submit" disabled={!on}>로그인</button>
        <a href="/" className="aback">포털로 돌아가기</a>
      </form>
    </main>
  );
}
