// 데모 콘솔 데이터 (DB 미연결 시). 모두 예시이며 실제 숙소·원작자·작업이 아닙니다.
import type { Job, FeedRow, Summary, Candidate, Longform, Correction } from "./console";

export const summary: Summary = {
  jobs: 6, in_review: 2, held: 1, published: 2, feed_candidates: 3, open_corrections: 1,
  public_shorts: 22, longform_threshold: 30, longform_ready: 0,
};

const base = { segment: "domestic_kr", question_type: "침구·객실", theme: "family", render_uri: null, sponsored: false,
  made_by: "편집 담당", reviewed_by: null, approved_by: null, youtube_status: null, youtube_url: null, hold_reason: null, version: 1 };

export const jobs: Job[] = [
  { ...base, id: "d1", job_no: "TRP-00031", question: "아이 둘과 묵을 때 이 객실 침구로 충분할까?", status: "review", updated_at: "2026-10-20T07:40:00+09:00",
    place: "[예시] 가족형 리조트 A", region: "강원 강릉", title: "아이 둘 가족, 이 객실 침구로 충분할까?", render_uri: "renders/TRP-00031_v1_ko.mp4", sponsored: true,
    reviewed_by: "운영 담당", blockers: ["근거 미확인 핵심 주장 1건"], next_statuses: ["approved", "held", "ready"] },
  { ...base, id: "d2", job_no: "TRP-00030", question: "해변열차 바다 쪽 창가, 어느 방향에서 타야 할까?", status: "review", updated_at: "2026-10-20T07:12:00+09:00",
    place: "[예시] 해변열차", region: "부산 해운대구", question_type: "이동·접근", title: "해변열차 창가 자리, 방향이 중요해요", render_uri: "renders/TRP-00030_v1_ko.mp4",
    reviewed_by: "운영 담당", approved_by: "제품 책임", blockers: [], next_statuses: ["approved", "held", "ready"] },
  { ...base, id: "d3", job_no: "TRP-00029", question: "한옥 숙소에 처음 묵을 때 도착 전에 무엇을 확인할까?", status: "ready", updated_at: "2026-10-19T21:30:00+09:00",
    segment: "inbound", place: "[예시] 한옥 게스트하우스 B", region: "서울 종로구", theme: "hanok_kculture", question_type: "도착 준비", title: "한옥 첫 숙박, 도착 전 체크",
    blockers: [], next_statuses: ["held", "rendering"] },
  { ...base, id: "d4", job_no: "TRP-00028", question: "바다 절벽 위 골목길, 계단은 얼마나 될까?", status: "held", updated_at: "2026-10-19T18:02:00+09:00",
    place: "[예시] 해안 골목", region: "부산 영도구", question_type: "이동·접근", theme: "couple_midlife", title: "골목 계단, 얼마나 될까",
    hold_reason: "자산 권리 revoked: 숙소 요청으로 사진 교체 대기", blockers: ["사용 불가 자산 1건 (권리 미확인/철회/만료/매체 미허용)"], next_statuses: ["material_check", "ready"] },
  { ...base, id: "d5", job_no: "TRP-00027", question: "해변 캠핑장, 아이 셋이면 사이트 크기는?", status: "published", updated_at: "2026-10-18T11:20:00+09:00",
    place: "[예시] 해변 캠핑장", region: "충남 태안", theme: "big_family", title: "아이 셋 캠핑, 사이트 크기", reviewed_by: "운영 담당", approved_by: "제품 책임",
    youtube_status: "public", youtube_url: "https://youtube.com/shorts/EXAMPLE", blockers: [], next_statuses: ["held", "ready"] },
  { ...base, id: "d6", job_no: "TRP-00026", question: "1박이면 해변 숙소일까 시내 숙소일까?", status: "material_check", updated_at: "2026-10-18T09:00:00+09:00",
    place: "[예시] 속초 해변·시내", region: "강원 속초", question_type: "숙소 비교", theme: "value", title: null, version: null,
    blockers: ["버전 없음"], next_statuses: ["held", "ready"] },
];

export const feed: FeedRow[] = [
  { id: "f1", title: "해변열차 바다 쪽 창가, 어느 방향에서 타야 할까", status: "candidate", published_at: "2026-10-18", url: "https://example.com/", platform: "ig_reels",
    creator: "@예시_도시여행자", agreement: "agreed", summary_allowed: true, summary: "진행 방향에 따라 바다 쪽 좌석이 바뀐다는 크리에이터 설명입니다.", summary_status: "draft",
    sponsored: false, disclosure: null, place_label: "해운대 해변열차", region: "부산 해운대구", theme: "family", sea_city: -35 },
  { id: "f2", title: "한강 노을에서 야경까지, 한 번에 이어지는 동선", status: "candidate", published_at: "2026-10-17", url: "https://example.com/", platform: "yt_shorts",
    creator: "@예시_서울야경", agreement: "none", summary_allowed: false, summary: null, summary_status: "none",
    sponsored: false, disclosure: null, place_label: "망원한강공원", region: "서울 마포구", theme: "youth_mood", sea_city: 70 },
  { id: "f3", title: "아이 셋 캠핑, 사이트 크기", status: "candidate", published_at: "2026-10-18", url: "https://youtube.com/shorts/EXAMPLE", platform: "yt_shorts",
    creator: "Travel.with.Jaws 쇼츠", agreement: "none", summary_allowed: true, summary: "텐트와 타프를 함께 치려면 큰 사이트가 필요했다는 경험입니다.", summary_status: "draft",
    sponsored: false, disclosure: null, place_label: "[예시] 해변 캠핑장", region: "충남 태안", theme: "big_family", sea_city: -75 },
];

export const candidates: Candidate[] = [
  { bundle_type: "question", bundle_key: "침구·객실 × family", shorts: 9, eligible_shorts: 7, has_sponsored: true, ready: false, reason: "채널 공개 쇼츠 22/30편" },
  { bundle_type: "region", bundle_key: "부산 해운대구", shorts: 7, eligible_shorts: 6, has_sponsored: false, ready: false, reason: "채널 공개 쇼츠 22/30편" },
  { bundle_type: "region", bundle_key: "강원 강릉", shorts: 4, eligible_shorts: 4, has_sponsored: false, ready: false, reason: "채널 공개 쇼츠 22/30편" },
];

export const longforms: Longform[] = [];

export const settings = { min_channel_shorts: 30, min_bundle_shorts: 8, min_age_days: 14, recheck_days: 90, rights_margin_days: 30 };

export const corrections: Correction[] = [
  { id: "c1", reason: "[TRP-00027] 캠핑장 큰 사이트 요금이 10월부터 바뀌었습니다", requester: "provider", proof_uri: "https://example.com/notice",
    status: "received", resolution: null, created_at: "2026-10-19T16:20:00+09:00" },
];
