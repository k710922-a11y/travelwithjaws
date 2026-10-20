"use client";
import { useEffect, useRef } from "react";
// @ts-ignore — 프레임워크 없는 화면 로직 (미리보기 페이지와 같은 코드)
import { mountPortal } from "./portal.js";
// @ts-ignore
import { startHeroScene } from "./heroScene.js";
import { send } from "./Track";
import type { PortalData } from "@/lib/feed";

export default function Portal({ data, heroVideo, demo }: { data: PortalData; heroVideo: { src: string; poster: string } | null; demo?: "db" | "mixed" | null }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!ref.current) return;
    const p = mountPortal(ref.current, data, {
      startScene: startHeroScene,
      heroVideo,
      hubBase: "",
      onOpen: (i: any) => i.job && send(i.job, "hub_arrive"),
      onOut: (i: any) => send(i.job ?? "", "source_open"),
    });
    return () => p.destroy();
  }, [data, heroVideo]);

  // 스크립트가 돌기 전·검색 수집기용: 같은 내용을 단순 목록으로 먼저 그려 둔다
  return (
    <>
    {demo === "db" && <div className="demo-strip gut">데모 모드 — 예시 데이터입니다. 실제 크리에이터·숙소·제휴가 아닙니다.</div>}
    {demo === "mixed" && <div className="demo-strip gut">화면 확인용 예시 데이터가 들어 있습니다 — <b>예시</b> 표시가 붙은 크리에이터·숙소·공지는 실제가 아니며 링크는 example.com 입니다.</div>}
    <div ref={ref}>
      <main className="gut" style={{ paddingBlock: 40 }}>
        <div className="in">
          <h1 style={{ margin: "0 0 16px" }}>바다에서 시작해 도시의 불빛까지</h1>
          <ul>
            {data.items.map((i) => (
              <li key={i.id}>
                <a href={i.platform === "hub_doc" && i.job ? `/p/${i.job}` : i.url}>{i.title}</a> {i.place} {i.summary ?? ""}
              </li>
            ))}
          </ul>
        </div>
      </main>
    </div>
    </>
  );
}
