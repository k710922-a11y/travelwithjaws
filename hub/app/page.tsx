import Portal from "@/components/Portal";
import { getPortalData, heroVideo, heroPhotos } from "@/lib/feed";
import { DEMO } from "@/lib/data";

export const dynamic = "force-dynamic"; // 빌드 때는 DB 에 닿지 않으므로 요청 시 렌더링

export default async function Home() {
  const [data, photos] = await Promise.all([getPortalData(), heroPhotos()]);
  // DB 미연결 데모 모드이거나, DB에 예시 데이터가 섞여 있으면 화면 위에 알린다
  const notice = DEMO ? "db" : data.items.some((i) => i.demo) ? "mixed" : null;
  return <Portal data={data} heroVideo={heroVideo()} heroPhotos={photos} demo={notice} />;
}
