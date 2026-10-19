import Portal from "@/components/Portal";
import { getPortalData, heroVideo } from "@/lib/feed";
import { DEMO } from "@/lib/data";

export const revalidate = 300;

export default async function Home() {
  const data = await getPortalData();
  return <Portal data={data} heroVideo={heroVideo()} demo={DEMO} />;
}
