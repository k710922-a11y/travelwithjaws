import "./portal.css";
import "./globals.css";
import type { Metadata } from "next";

const BRAND = process.env.NEXT_PUBLIC_BRAND ?? "Travel.with.Jaws";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "https://travel.jawsweb.site"),
  openGraph: { siteName: BRAND, locale: "ko_KR", type: "website" },
  title: { default: BRAND, template: `%s · ${BRAND}` },
  description: "바다에서 도시까지, 확인하고 떠나는 여행. 쇼츠·릴스·블로그·공식 안내에 흩어진 여행 이야기를 모아 요약하고, 확인된 사실과 경험을 나눠 보여 줍니다.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600;12..96,800&family=IBM+Plex+Sans+KR:wght@400;500;600;700&display=swap" />
      </head>
      <body>{children}</body>
    </html>
  );
}
