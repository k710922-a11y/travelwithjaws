import "./console.css";
import Link from "next/link";
import type { Metadata } from "next";
import { whoami, CONSOLE_DEMO, getSummary } from "@/lib/console";

export const metadata: Metadata = { title: "편집 콘솔", robots: { index: false, follow: false } };
export const dynamic = "force-dynamic";

export default async function ConsoleLayout({ children }: { children: React.ReactNode }) {
  const me = await whoami();
  const s = await getSummary();
  const nav = [
    { href: "/console", label: "작업 현황", n: s.in_review, hint: "검수 대기" },
    { href: "/console/feed", label: "피드 승인", n: s.feed_candidates, hint: "후보" },
    { href: "/console/longform", label: "롱폼", n: s.longform_ready, hint: "착수 가능 묶음" },
    { href: "/console/corrections", label: "정정 요청", n: s.open_corrections, hint: "미처리" },
  ];
  return (
    <div className="con">
      <aside className="side">
        <Link href="/" className="cbrand"><span>Travel<i>.</i>with<i>.</i>Jaws</span><small>편집 콘솔</small></Link>
        <nav aria-label="콘솔 메뉴">
          {nav.map((n) => (
            <Link key={n.href} href={n.href} className="nl">
              <span>{n.label}</span>
              <b title={n.hint} className={n.n ? "hot" : ""}>{n.n}</b>
            </Link>
          ))}
        </nav>
        <div className="me">
          <span>{me.name}</span>
          {process.env.CF_ACCESS_TEAM_DOMAIN && <a href="/cdn-cgi/access/logout" className="logout">로그아웃</a>}
          {CONSOLE_DEMO && <em>데모 데이터 · 저장 안 됨</em>}
        </div>
      </aside>
      <main className="cmain">{children}</main>
    </div>
  );
}
