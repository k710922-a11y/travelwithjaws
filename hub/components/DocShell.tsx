import Link from "next/link";
import { DEMO } from "@/lib/data";

const BRAND = process.env.NEXT_PUBLIC_BRAND ?? "Travel.with.Jaws";

// 판단 문서·정책 페이지용 읽기 화면 (포털 홈과 같은 토큰 사용)
export default function DocShell({ children, demo }: { children: React.ReactNode; demo?: boolean }) {
  return (
    <div className="wrap">
      <header className="top">
        <Link href="/" className="brand">{BRAND}</Link>
        <nav>
          <Link href="/">포털</Link>
          <Link href="/policy">편집 원칙</Link>
          <Link href="/policy#correction">정정 요청</Link>
          <a href="/console" className="admin-link">관리자</a>
        </nav>
      </header>
      {DEMO && <div className="demo">데모 모드 — DB가 연결되지 않아 예시 데이터를 보여줍니다. 실제 숙소·제휴가 아닙니다.</div>}
      {!DEMO && demo && <div className="demo">예시 판단 문서입니다 — 화면 확인용으로 만든 자료이며 실제 숙소·크리에이터·제휴가 아닙니다.</div>}
      {children}
      <footer>
        이 사이트는 여행 정보를 정리해 보여줄 뿐, 예약을 확정하거나 시설 이용을 보장하지 않습니다.
        최종 조건은 예약 사업자와 시설의 공식 안내에서 확인해 주세요.
      </footer>
    </div>
  );
}
