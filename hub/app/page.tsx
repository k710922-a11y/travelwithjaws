import Portal from "@/components/Portal";
import { getPortalData, heroVideo } from "@/lib/feed";
import { DEMO } from "@/lib/data";

export const dynamic = "force-dynamic"; // 빌드 때는 DB 에 닿지 않으므로 요청 시 렌더링

export default async function Home() {
  const data = await getPortalData();
  return <Portal data={data} heroVideo={heroVideo()} demo={DEMO} />;
}
