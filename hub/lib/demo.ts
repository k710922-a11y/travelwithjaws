// 데모 모드(DB 미연결) 전용 예시 데이터. 실제 숙소·원작자·제휴가 아닙니다.
import type { HubRow, Card } from "./data";

export const demoHub: HubRow[] = [
  {
    job_no: "TRP-00001",
    question: "아이 둘과 묵을 때 이 객실 침구로 충분할까?",
    segment: "domestic_kr",
    slug: "demo-family-stay",
    official_name: "[예시] 가족형 리조트 A",
    local_name: "예시 리조트 A",
    names_i18n: { en: "[Sample] Family Resort A" },
    region: "강원",
    theme: "family",
    sub_questions: ["침구 구성", "공용시설 이용조건"],
    lang: "ko",
    title: "아이 둘 가족, 이 객실 침구로 충분할까?",
    description: "패밀리 객실의 침구 구성과 수영장 이용 조건을 공식 안내와 방문 후기로 나눠 정리했습니다.",
    sponsored: true,
    disclosure: "자료 제공: 숙소 측 · 평가는 편집팀 판단",
    partner_links: [{ label: "객실 조건 확인하기", operator: "예시 예약사", url: "https://example.com/" }],
    prep_card: {
      before: ["엑스트라 베드 신청 가능 여부와 신청 방법", "실내 수영장 이용이 요금에 포함되는지", "유아 침대 가드 대여 여부"],
      onsite: ["체크인 시 배정된 객실이 패밀리 타입인지", "수영장 운영 시간과 아동 동반 규정"],
      official_contact: "숙소 공식 고객센터 (예약 사업자 화면의 연락처를 우선 확인)",
    },
    checked_at: "2026-10-18T09:00:00+09:00",
    version_id: "demo-v1",
    youtube_url: null,
  },
];

export const demoCards: Card[] = [
  {
    version_id: "demo-v1", claim_id: "c1", claim_kind: "fact",
    body: "패밀리 객실은 더블 침대 1개와 싱글 침대 2개 구성으로 공지되어 있다.",
    evidence_kind: "official", source_url: "https://example.com/notice", author: "숙소 공식 안내",
    observed_at: "2026-10-01", room_type: "패밀리", segment_start: null, segment_end: null,
  },
  {
    version_id: "demo-v1", claim_id: "c2", claim_kind: "experience",
    body: "초등 저학년 두 명과 묵은 방문자는 싱글 침대를 붙여 쓰니 공간이 넉넉했다고 말했다.",
    evidence_kind: "review", source_url: "https://www.youtube.com/watch?v=EXAMPLE", author: "예시 리뷰어 (협약 자막)",
    observed_at: "2026-08-14", room_type: "패밀리", segment_start: 132, segment_end: 158,
  },
  {
    version_id: "demo-v1", claim_id: "c3", claim_kind: "experience",
    body: "다른 방문자는 디럭스 객실에 묵어 침대가 좁았다고 했다 — 객실 유형이 달라 직접 비교는 어렵다.",
    evidence_kind: "review", source_url: "https://www.youtube.com/watch?v=EXAMPLE2", author: "예시 리뷰어 B (협약 자막)",
    observed_at: "2026-07-02", room_type: "디럭스", segment_start: 47, segment_end: 61,
  },
  {
    version_id: "demo-v1", claim_id: "c4", claim_kind: "interpretation",
    body: "아이가 미취학이면 침대 가드, 초등 고학년 이상이면 엑스트라 베드 가능 여부를 먼저 확인하는 편이 좋다.",
    evidence_kind: "editorial", source_url: null, author: "편집팀",
    observed_at: null, room_type: null, segment_start: null, segment_end: null,
  },
  {
    version_id: "demo-v1", claim_id: "c5", claim_kind: "unverified",
    body: "실내 수영장 이용이 객실 요금에 포함되는지는 확인되지 않았다.",
    evidence_kind: null, source_url: null, author: null,
    observed_at: null, room_type: null, segment_start: null, segment_end: null,
  },
];
