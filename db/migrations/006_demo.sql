-- =====================================================================
-- 예시(데모) 데이터: 화면 완성도 확인용
-- 원칙
--  - 예시 데이터도 실제와 같은 규칙(권리·근거·승인)을 거쳐 공개된다. 우회하지 않는다.
--  - 예시 행은 is_demo 로 표시하고, 공개 뷰도 is_demo 를 내보내 화면에 '예시' 표시를 붙인다.
--  - 실제 숙소·크리에이터처럼 보이지 않게: 이름에 [예시]·예시_ 를 붙이고 링크는 example.com.
--  - load_demo() 로 넣고 remove_demo() 로 한 번에 지운다 (실제 데이터는 건드리지 않음). service_role 전용.
-- =====================================================================
set search_path = trip, public;

alter table staff         add column is_demo boolean not null default false;
alter table places        add column is_demo boolean not null default false;
alter table media_sources add column is_demo boolean not null default false;
alter table collections   add column is_demo boolean not null default false;

-- 공개 뷰에 is_demo 추가 (열은 끝에 덧붙인다)
-- 아울러 최신 버전을 함수(latest_version) 대신 뷰 안의 하위 질의로 고른다:
-- 함수는 호출자(anon) 권한으로 돌아 원본 표를 읽지 못해, 공개된 문서가 생기는 순간 공개 뷰가 권한 오류를 냈다.
create or replace view public_hub as
select j.job_no, j.question, j.segment, p.slug, p.official_name, p.local_name, p.names_i18n,
       p.region, p.theme, p.sub_questions, v.lang, v.title, v.description, v.sponsored, v.disclosure,
       v.partner_links, v.prep_card, v.approved_at as checked_at, v.id as version_id,
       (select pb.url from publications pb where pb.version_id = v.id and pb.channel = 'youtube'
          and pb.status = 'public' limit 1) as youtube_url,
       p.is_demo
  from content_jobs j
  join places p on p.id = j.place_id
  join lateral (select * from content_versions cv where cv.job_id = j.id order by cv.version desc, cv.created_at desc limit 1) v on true
 where j.status = 'published' and not p.is_medical;

create or replace view public_feed as
select i.id, s.platform, s.display_name as creator, s.url as source_url, i.url, i.title, i.published_at,
       i.duration_label, i.lang, i.segment, i.theme, i.sea_city, i.companions, i.place_label, i.region,
       case when i.summary_status = 'verified' and (s.summary_allowed or s.is_own) then i.summary end as summary,
       case when i.summary_status = 'verified' and (s.summary_allowed or s.is_own) then null
            else '자막이나 글을 제공받지 않아 요약하지 않았습니다. 원본에서 확인해 주세요.' end as summary_reason,
       case when i.summary_status = 'verified' then coalesce(i.evidence_kind::text, 'review') else 'none' end as evidence,
       i.sponsored, i.disclosure,
       (select a.uri from assets a where a.id = i.thumbnail_asset and asset_usable(a, 'hub')) as thumbnail_uri,
       j.job_no,
       (s.is_demo or coalesce(p.is_demo, false)) as is_demo
  from media_items i
  join media_sources s on s.id = i.source_id
  left join content_jobs j on j.id = i.job_id
  left join places p on p.id = i.place_id
 where i.status = 'approved' and s.agreement <> 'ended' and coalesce(p.is_medical, false) = false
union all
select v.id, 'hub_doc'::media_platform_t, '편집팀 판단 문서', null, '/p/' || h.job_no, h.question, h.checked_at::date,
       '판단 문서', h.lang, h.segment, h.theme, coalesce(j.sea_city, 0), '{}'::companion_t[], h.official_name, h.region,
       h.description, null, 'official', h.sponsored, h.disclosure, null, h.job_no, h.is_demo
  from public_hub h join content_versions v on v.id = h.version_id join content_jobs j on j.id = v.job_id;

-- ---------- 지우기: 예시 표시된 것만 ----------
create or replace function remove_demo() returns text language plpgsql as $$
declare n_items int; n_jobs int; n_places int;
begin
  delete from collections where is_demo;
  delete from media_items i
   where i.source_id in (select id from media_sources where is_demo)
      or i.place_id in (select id from places where is_demo)
      or i.job_id in (select j.id from content_jobs j join places p on p.id = j.place_id where p.is_demo);
  get diagnostics n_items = row_count;
  delete from media_sources where is_demo;
  delete from publications where version_id in
    (select v.id from content_versions v join content_jobs j on j.id = v.job_id join places p on p.id = j.place_id where p.is_demo);
  delete from content_jobs where place_id in (select id from places where is_demo);
  get diagnostics n_jobs = row_count;
  delete from corrections where place_id in (select id from places where is_demo);
  delete from claims where place_id in (select id from places where is_demo);
  delete from evidence where place_id in (select id from places where is_demo);
  delete from assets where place_id in (select id from places where is_demo);
  delete from places where is_demo;
  get diagnostics n_places = row_count;
  delete from staff s where s.is_demo
    and not exists (select 1 from job_transitions t where t.actor_id = s.id)
    and not exists (select 1 from content_versions v where s.id in (v.made_by, v.reviewed_by, v.approved_by))
    and not exists (select 1 from media_items i where i.approved_by = s.id)
    and not exists (select 1 from evidence e where e.checked_by = s.id)
    and not exists (select 1 from assets a where a.approved_by = s.id);
  return format('예시 데이터 삭제: 피드 %s건 · 판단 문서 작업 %s건 · 장소 %s곳', n_items, n_jobs, n_places);
end $$;

-- ---------- 넣기: 지운 뒤 다시 넣는다 (여러 번 실행해도 같은 결과) ----------
create or replace function load_demo() returns text language plpgsql as $$
declare
  st_ed uuid; st_pm uuid; st_op uuid;
  d jsonb; c jsonb; it jsonb; col jsonb; k text;
  pl uuid; photo uuid; sub uuid; ev uuid; cl uuid; jb uuid; vr uuid; src uuid; co uuid;
  pos int; target text; n_items int := 0; n_docs int := 0;
  docs jsonb := $j$[
   {"no":"DEMO-01","slug":"demo-family-resort","name":"[예시] 가족형 리조트 A","local":"예시 리조트 A","en":"[Sample] Family Resort A",
    "region":"강원 강릉","segment":"domestic_kr","theme":"family","sea":-40,"qtype":"침구·객실","target":"published",
    "q":"아이 둘과 묵을 때 이 객실 침구로 충분할까?","title":"아이 둘 가족, 이 객실 침구로 충분할까?",
    "desc":"공식 안내의 침구 구성과 두 방문자의 경험을 객실 유형별로 나눴습니다. 수영장 포함 여부는 아직 미확인입니다.",
    "subq":["침구 구성","공용시설 이용조건"],"spon":"자료 제공: 숙소 측 · 평가는 편집팀 판단",
    "links":[{"label":"객실 조건 확인하기","operator":"예시 예약사","url":"https://example.com/"}],
    "prep":{"before":["엑스트라 베드 신청 가능 여부와 방법","실내 수영장 이용이 요금에 포함되는지","유아 침대 가드 대여 여부"],
            "onsite":["배정된 객실이 패밀리 타입인지","수영장 운영 시간과 아동 동반 규정"],
            "official_contact":"숙소 공식 고객센터 (예약 사업자 화면의 연락처를 우선 확인)"},
    "claims":[
      {"k":"fact","b":"패밀리 객실은 더블 침대 1개와 싱글 침대 2개 구성으로 공지되어 있다.","ev":{"k":"official","a":"숙소 공식 안내 (예시)","u":"https://example.com/notice","d":"2026-10-01","r":"패밀리"}},
      {"k":"experience","b":"초등 저학년 두 명과 묵은 방문자는 싱글 침대를 붙여 쓰니 공간이 넉넉했다고 말했다.","ev":{"k":"review","a":"@예시_가족여행 (협약 자막)","u":"https://example.com/video-a","d":"2026-08-14","r":"패밀리","s":132,"e":158}},
      {"k":"experience","b":"다른 방문자는 디럭스 객실에 묵어 침대가 좁았다고 했다. 객실 유형이 달라 직접 비교는 어렵다.","ev":{"k":"review","a":"@예시_주말부부 (협약 자막)","u":"https://example.com/video-b","d":"2026-07-02","r":"디럭스","s":47,"e":61}},
      {"k":"interpretation","b":"아이가 미취학이면 침대 가드, 초등 고학년 이상이면 엑스트라 베드 가능 여부를 먼저 확인하는 편이 좋다.","ev":{"k":"editorial","a":"편집팀","d":"2026-10-10"}},
      {"k":"unverified","b":"실내 수영장 이용이 객실 요금에 포함되는지는 확인되지 않았다."}]},
   {"no":"DEMO-02","slug":"demo-hanok-guesthouse","name":"[예시] 한옥 게스트하우스 B","local":"예시 한옥 B","en":"[Sample] Hanok Guesthouse B",
    "region":"서울 종로구","segment":"inbound","theme":"hanok_kculture","sea":85,"qtype":"도착 준비","target":"published",
    "q":"한옥 숙소에 처음 묵을 때, 도착 전에 무엇을 확인해야 할까?","title":"First night in a hanok: 도착 전에 확인할 것",
    "desc":"출입 방식, 짐 이동, 바닥 침구를 도착 순서대로 정리했습니다. 영문 표기는 현지 안내판과 대조했습니다.",
    "subq":["출입 방식","바닥 침구"],
    "links":[{"label":"Check room details","operator":"예시 예약사","url":"https://example.com/"}],
    "prep":{"before":["대문 비밀번호가 언제 전달되는지","캐리어를 끌 수 있는 골목인지 (계단 여부)","바닥 요 두께를 고를 수 있는지"],
            "onsite":["신발을 벗는 위치","온돌 온도 조절 방법"],"official_contact":"숙소 공식 메시지 창구 (예시)"},
    "claims":[
      {"k":"fact","b":"체크인은 비대면이며 대문 비밀번호는 도착 당일 오후에 메시지로 전달된다고 안내되어 있다.","ev":{"k":"official","a":"숙소 공식 안내 (예시)","u":"https://example.com/hanok-notice","d":"2026-10-05","r":"전 객실"}},
      {"k":"experience","b":"한 방문자는 골목 입구부터 계단이 있어 큰 캐리어는 들고 올라가야 했다고 말했다.","ev":{"k":"review","a":"@Example_SeoulWalker (협약 자막)","u":"https://example.com/video-c","d":"2026-09-21","r":"온돌방","s":35,"e":52}},
      {"k":"interpretation","b":"바닥 침구가 처음이라면 요를 두 장 겹쳐 달라고 미리 요청하는 편이 편하다.","ev":{"k":"editorial","a":"편집팀","d":"2026-10-08"}},
      {"k":"unverified","b":"겨울철 난방비가 요금에 포함되는지는 확인되지 않았다."}]},
   {"no":"DEMO-03","slug":"demo-beach-camp","name":"[예시] 해변 캠핑장 C","local":"예시 캠핑장 C","en":"[Sample] Beach Campsite C",
    "region":"충남 태안","segment":"domestic_kr","theme":"big_family","sea":-75,"qtype":"시설·사이트","target":"published",
    "q":"아이 셋 가족, 해변 캠핑장 사이트 크기와 개수대 거리는 괜찮을까?","title":"아이 셋이면 어느 사이트를 골라야 할까",
    "desc":"사이트 규격 공지와 방문자 두 명의 경험을 비교했습니다. 온수 운영 시간은 계절마다 달라 미확인으로 남겼습니다.",
    "subq":["사이트 규격","개수대·화장실 거리"],
    "links":[],
    "prep":{"before":["대형 사이트 규격 (텐트+타프 동시 설치 가능 여부)","전기 사용 가능 여부","반려동물 동반 규정"],
            "onsite":["개수대와 가까운 사이트인지","만조 시간과 해변 산책로 통제 여부"],"official_contact":"캠핑장 공식 전화 (예시)"},
    "claims":[
      {"k":"fact","b":"대형 사이트는 가로 10m, 세로 8m로 공지되어 있다.","ev":{"k":"official","a":"캠핑장 공식 안내 (예시)","u":"https://example.com/camp-notice","d":"2026-09-28","r":"대형 사이트"}},
      {"k":"experience","b":"아이 셋과 온 방문자는 텐트와 타프를 함께 치려면 대형 사이트가 필요했다고 말했다.","ev":{"k":"review","a":"@예시_가족캠핑 (협약 자막)","u":"https://example.com/video-d","d":"2026-09-14","r":"대형 사이트","s":12,"e":40}},
      {"k":"experience","b":"다른 방문자는 개수대에서 먼 사이트라 저녁 설거지가 번거로웠다고 했다.","ev":{"k":"review","a":"@예시_차박일기 (협약 자막)","u":"https://example.com/video-e","d":"2026-08-30","r":"일반 사이트","s":88,"e":104}},
      {"k":"unverified","b":"가을철 온수 운영 시간은 확인되지 않았다."}]},
   {"no":"DEMO-04","slug":"demo-city-hotel","name":"[예시] 시티 호텔 D","local":"예시 호텔 D","en":"[Sample] City Hotel D",
    "region":"부산 해운대구","segment":"domestic_kr","theme":"value","sea":-10,"qtype":"침구·객실","target":"published",
    "q":"같은 가격이면 바다 쪽 객실과 시내 쪽 객실, 어디가 나을까?","title":"바다 쪽 vs 시내 쪽, 같은 값이면?",
    "desc":"객실 방향별 공식 안내와 두 방문자의 경험을 나눴습니다. 소음은 사람마다 달라 해석으로 표시했습니다.",
    "subq":["객실 방향","소음"],
    "links":[{"label":"객실 방향 확인하기","operator":"예시 예약사","url":"https://example.com/"}],
    "prep":{"before":["객실 방향 지정이 가능한지 (추가 요금 여부)","고층 배정 요청 가능 여부"],
            "onsite":["창문 방음 상태","주변 공사 여부"],"official_contact":"호텔 공식 고객센터 (예시)"},
    "claims":[
      {"k":"fact","b":"바다 쪽 객실은 10층 이상에만 있다고 공지되어 있다.","ev":{"k":"official","a":"호텔 공식 안내 (예시)","u":"https://example.com/hotel-notice","d":"2026-10-03","r":"오션 디럭스"}},
      {"k":"experience","b":"한 방문자는 바다 쪽 객실에서 아침 해돋이를 침대에서 봤다고 말했다.","ev":{"k":"review","a":"@예시_바다산책 (협약 자막)","u":"https://example.com/video-f","d":"2026-09-02","r":"오션 디럭스","s":5,"e":21}},
      {"k":"interpretation","b":"늦게 들어와 일찍 나가는 일정이라면 시내 쪽 객실의 가격 차이가 더 의미 있을 수 있다.","ev":{"k":"editorial","a":"편집팀","d":"2026-10-09"}},
      {"k":"unverified","b":"주말 밤 해변 쪽 소음 수준은 확인되지 않았다."}]},
   {"no":"DEMO-05","slug":"demo-jeju-pension","name":"[예시] 오션뷰 펜션 E","local":"예시 펜션 E","en":"[Sample] Ocean-view Pension E",
    "region":"제주","segment":"domestic_kr","theme":"couple_midlife","sea":-80,"qtype":"우천 대안","target":"review",
    "q":"비 오는 날 제주 동쪽 펜션, 근처에서 할 수 있는 건?","title":"비 오는 날 제주 동쪽, 펜션 근처 대안",
    "desc":"검수 중인 예시 작업입니다.","subq":["우천 대안"],"links":[],"prep":{},
    "claims":[{"k":"fact","b":"펜션에서 실내 전시관까지 차로 15분 거리로 안내되어 있다.","ev":{"k":"official","a":"공식 안내 (예시)","u":"https://example.com/jeju-notice","d":"2026-10-12"}}]},
   {"no":"DEMO-06","slug":"demo-night-market","name":"[예시] 야시장 F","local":"예시 야시장 F","en":"[Sample] Night Market F",
    "region":"서울 종로구","segment":"inbound","theme":"night_food","sea":90,"qtype":"이용 방법","target":"held",
    "hold":"후기 자막 사용 허락 회신 대기 (예시)",
    "q":"How do I order at a Korean night market?","title":"Ordering at a night market",
    "desc":"보류된 예시 작업입니다.","subq":["주문 방법"],"links":[],"prep":{},
    "claims":[{"k":"fact","b":"영업시간은 18시부터 24시까지로 공지되어 있다.","ev":{"k":"official","a":"시장 공식 안내 (예시)","u":"https://example.com/market-notice","d":"2026-10-11"}}]},
   {"no":"DEMO-07","slug":"demo-river-park","name":"[예시] 강변 공원 G","local":"예시 공원 G","en":"[Sample] Riverside Park G",
    "region":"서울 마포구","segment":"domestic_kr","theme":"youth_mood","sea":70,"qtype":"이동·접근","target":"received",
    "q":"노을 보고 야경까지, 강변 공원에서 어떻게 움직일까?","title":"노을에서 야경까지 동선",
    "desc":"접수된 예시 작업입니다.","subq":["동선"],"links":[],"prep":{},"claims":[]}
  ]$j$;
  feed jsonb := $j$[
   {"key":"f01","p":"yt_shorts","src":"@예시_바다산책","ok":true,"t":"광안리 해변, 다리가 한 화면에 다 들어오는 자리","d":"2026-10-18","dur":"0:34","pl":"광안리 해변","r":"부산 수영구","th":"couple_midlife","seg":"domestic_kr","sc":-10,"w":["couple","friends"],"s":"해변 중앙보다 남쪽 끝 쪽에서 다리 전체가 한 화면에 들어온다는 촬영자의 관찰입니다. 주말 저녁에는 자리가 빨리 찬다고 말합니다.","ev":"review"},
   {"key":"f02","p":"ig_reels","src":"@예시_도시여행자","ok":true,"t":"해변열차 바다 쪽 창가, 어느 방향에서 타야 할까","d":"2026-10-18","dur":"0:21","pl":"해운대 해변열차","r":"부산 해운대구","th":"family","seg":"domestic_kr","sc":-35,"w":["family","couple"],"s":"진행 방향에 따라 바다 쪽 좌석이 바뀐다는 크리에이터 설명입니다. 좌석 지정 방식은 공식 안내에서 다시 확인해야 합니다.","ev":"review"},
   {"key":"f03","p":"blog","src":"주말엔 바다 (예시 블로그)","ok":true,"t":"아이와 해변 카페거리 걷기, 유모차로 괜찮았을까","d":"2026-10-17","dur":"6분 읽기","pl":"안목해변 카페거리","r":"강원 강릉","th":"family","seg":"domestic_kr","sc":-60,"w":["family"],"s":"유모차로는 해변 산책로 쪽이 수월했고, 카페 계단은 건물마다 달랐다는 경험입니다. 주차는 평일 오전이 여유로웠다고 적었습니다.","ev":"review"},
   {"key":"f04","p":"official","src":"예시 관광 안내","ok":true,"t":"해수욕장 운영 기간 이후 입수 통제 구역 안내","d":"2026-10-16","dur":"공지","pl":"부산 해수욕장 일대","r":"부산","th":"nature","seg":"domestic_kr","sc":-85,"w":["family","couple","friends","solo"],"s":"운영 기간이 끝난 뒤 입수가 제한되는 구역과 안전요원 배치 여부를 안내하는 공지입니다. 세부 구역은 원문 공지를 확인하세요.","ev":"official"},
   {"key":"f05","p":"yt_shorts","src":"@예시_서울야경","ok":false,"t":"한강 노을에서 야경까지, 한 번에 이어지는 동선","d":"2026-10-17","dur":"0:42","pl":"망원한강공원","r":"서울 마포구","th":"youth_mood","seg":"domestic_kr","sc":70,"w":["couple","friends"]},
   {"key":"f06","p":"ig_reels","src":"@예시_제주바람","ok":true,"t":"동쪽 해안도로에 비가 오면, 이렇게 바꿨어요","d":"2026-10-16","dur":"0:28","pl":"제주 동부 해안도로","r":"제주","th":"nature","seg":"domestic_kr","sc":-70,"w":["solo","couple"],"s":"비가 오자 해안 카페 대신 실내 전시로 일정을 옮긴 경험입니다. 이동 시간은 차량 기준으로 말합니다.","ev":"review","spon":"자료 제공: 예시 카페"},
   {"key":"f07","p":"yt","src":"@예시_트래블로그","ok":true,"t":"1박이라면 해변 숙소일까 시내 숙소일까, 둘 다 묵어 봤습니다","d":"2026-10-15","dur":"12:40","pl":"속초 해변·시내","r":"강원 속초","th":"value","seg":"domestic_kr","sc":0,"w":["friends","couple"],"s":"해변 숙소는 아침 산책, 시내 숙소는 시장과 터미널 접근이 장점이었다는 비교입니다. 두 곳 모두 직접 묵은 경험입니다.","ev":"review"},
   {"key":"f08","p":"blog","src":"도시산책 노트 (예시 블로그)","ok":true,"t":"호수공원 수상택시, 바람 부는 날에도 탈 수 있었을까","d":"2026-10-14","dur":"5분 읽기","pl":"송도 센트럴파크","r":"인천 연수구","th":"family","seg":"domestic_kr","sc":55,"w":["family"],"s":"바람이 강한 날 운항이 멈췄던 경험과, 출발 전에 운항 안내를 확인한 방법을 적었습니다.","ev":"review"},
   {"key":"f09","p":"yt_shorts","src":"@예시_골목여행","ok":true,"t":"바다 절벽 위 골목길, 계단은 얼마나 될까","d":"2026-10-15","dur":"0:31","pl":"영도 흰여울길","r":"부산 영도구","th":"couple_midlife","seg":"domestic_kr","sc":-20,"w":["couple","solo"],"s":"골목 입구마다 계단 수가 다르고, 해안 산책로로 내려가면 다시 올라와야 한다는 설명입니다. 걷기 편한 신발을 권합니다.","ev":"review"},
   {"key":"f10","p":"official","src":"예시 축제 사무국","ok":true,"t":"강변 가을 축제 일정과 교통 통제 안내","d":"2026-10-14","dur":"공지","pl":"여의도 한강공원","r":"서울 영등포구","th":"night_food","seg":"inbound","sc":75,"w":["friends","couple","family"],"s":"축제 기간의 행사 시간과 주변 도로 통제 구간을 알리는 공지입니다. 막차 시간 변경 여부는 원문을 확인하세요.","ev":"official"},
   {"key":"f11","p":"ig_reels","src":"@Example_SeoulBites","ok":true,"t":"Night market food in Seoul, how ordering works","d":"2026-10-13","dur":"0:26","pl":"광장시장","r":"서울 종로구","th":"night_food","seg":"inbound","sc":90,"w":["friends","solo"],"s":"자리에 앉아 메뉴를 가리켜 주문하고 나갈 때 계산했다는 외국인 방문자의 경험입니다. 현금·카드 가능 여부는 가게마다 다르다고 합니다.","ev":"review"},
   {"key":"f12","p":"yt_shorts","src":"@예시_가족캠핑","ok":true,"t":"해변 캠핑장, 아이 셋이면 사이트 크기는?","d":"2026-10-12","dur":"0:38","pl":"[예시] 해변 캠핑장 C","r":"충남 태안","th":"big_family","seg":"domestic_kr","sc":-75,"w":["family"],"s":"텐트와 타프를 함께 치려면 큰 사이트가 필요했다는 경험입니다. 사이트 규격은 캠핑장 공지로 확인해야 합니다.","ev":"review"},
   {"key":"f13","p":"yt_shorts","src":"@예시_바다산책","ok":true,"t":"해운대 새벽 6시, 해돋이 보기 좋은 계단 자리","d":"2026-10-11","dur":"0:29","pl":"해운대 해수욕장","r":"부산 해운대구","th":"couple_midlife","seg":"domestic_kr","sc":-55,"w":["couple","solo"],"s":"동백섬 쪽 계단에서 해가 건물 사이가 아니라 수평선에서 뜬다는 관찰입니다. 10월 기준 일출 20분 전 도착을 권합니다.","ev":"review"},
   {"key":"f14","p":"blog","src":"한옥에서 하룻밤 (예시 블로그)","ok":true,"t":"한옥 스테이 바닥 침구, 허리가 불편하진 않았을까","d":"2026-10-10","dur":"4분 읽기","pl":"북촌 한옥마을","r":"서울 종로구","th":"hanok_kculture","seg":"inbound","sc":80,"w":["couple","family"],"s":"요를 두 장 겹쳐 달라고 요청했더니 훨씬 편했다는 경험입니다. 숙소마다 요청 가능 여부가 다르다고 적었습니다.","ev":"review"},
   {"key":"f15","p":"ig_reels","src":"@Example_KoreaFirstTime","ok":true,"t":"Hanok guesthouse check-in: shoes, keys and floor beds","d":"2026-10-10","dur":"0:33","pl":"[예시] 한옥 게스트하우스 B","r":"서울 종로구","th":"hanok_kculture","seg":"inbound","sc":85,"w":["solo","couple"],"s":"신발을 벗는 위치와 비대면 체크인 순서를 처음 방문한 외국인 시점으로 보여 줍니다.","ev":"review"},
   {"key":"f16","p":"official","src":"예시 교통 안내센터","ok":true,"t":"공항철도 심야 운행 시간 조정 안내","d":"2026-10-09","dur":"공지","pl":"인천공항 ↔ 서울역","r":"인천·서울","th":"tech_korea","seg":"inbound","sc":60,"w":["solo","friends","family","couple"],"s":"주말 심야 운행 시간이 조정된다는 공지입니다. 적용 날짜와 막차 시각은 원문에서 확인하세요.","ev":"official"},
   {"key":"f17","p":"yt","src":"@예시_트래블로그","ok":true,"t":"강릉 1박 2일, 바다 카페와 시장을 하루에 잇는 법","d":"2026-10-08","dur":"9:15","pl":"강릉 안목·중앙시장","r":"강원 강릉","th":"youth_mood","seg":"domestic_kr","sc":-30,"w":["friends","couple"],"s":"오전엔 해변 카페, 오후엔 시장으로 옮긴 동선과 버스 간격을 직접 확인한 경험입니다.","ev":"review"},
   {"key":"f18","p":"yt_shorts","src":"@예시_서울야경","ok":false,"t":"성수동 골목, 해 지고 나서 더 예쁜 길","d":"2026-10-07","dur":"0:25","pl":"성수동","r":"서울 성동구","th":"youth_mood","seg":"domestic_kr","sc":88,"w":["friends","couple"]},
   {"key":"f19","p":"ig_reels","src":"@예시_도시여행자","ok":true,"t":"부산 야경 투어버스, 2층 맨 앞자리 앉는 법","d":"2026-10-06","dur":"0:24","pl":"부산 시티투어 야경 코스","r":"부산","th":"night_food","seg":"domestic_kr","sc":40,"w":["family","couple","friends"],"s":"출발 20분 전에 줄을 서야 2층 앞자리가 가능했다는 경험입니다. 예약 방식은 공식 안내를 확인해야 합니다.","ev":"review"},
   {"key":"f20","p":"blog","src":"주말엔 바다 (예시 블로그)","ok":true,"t":"대가족 7명, 바닷가 독채 펜션에서 주방이 충분했을까","d":"2026-10-05","dur":"7분 읽기","pl":"남해 해안 마을","r":"경남 남해","th":"big_family","seg":"domestic_kr","sc":-65,"w":["family"],"s":"조리도구는 충분했지만 냉장고가 작아 아이스박스를 따로 챙겼다는 경험입니다.","ev":"review"},
   {"key":"f21","p":"yt_shorts","src":"@Example_SeoulBites","ok":true,"t":"Han river convenience store ramyeon, step by step","d":"2026-10-04","dur":"0:30","pl":"여의도 한강공원","r":"서울 영등포구","th":"night_food","seg":"inbound","sc":72,"w":["friends","solo"],"s":"편의점 즉석 라면 기계 사용 순서를 보여 주는 영상입니다. 기계 형태는 지점마다 다를 수 있다고 말합니다.","ev":"review"},
   {"key":"f22","p":"official","src":"예시 국립공원 사무소","ok":true,"t":"해안 탐방로 일부 구간 낙석 정비 통제","d":"2026-10-03","dur":"공지","pl":"해안 탐방로","r":"강원 동해","th":"nature","seg":"domestic_kr","sc":-90,"w":["solo","couple","friends","family"],"s":"낙석 정비로 일부 구간이 통제된다는 공지입니다. 우회로와 통제 기간은 원문을 확인하세요.","ev":"official"},
   {"key":"f23","p":"yt","src":"@예시_럭셔리스테이","ok":true,"t":"오션뷰 스위트 하룻밤, 가격만큼의 차이가 있었을까","d":"2026-10-02","dur":"14:02","pl":"부산 기장 해안","r":"부산 기장군","th":"premium","seg":"domestic_kr","sc":-45,"w":["couple"],"s":"객실 크기와 욕조 전망이 가장 큰 차이였고, 조식은 일반 객실과 같았다는 비교입니다.","ev":"review","spon":"숙박 제공: 예시 호텔"},
   {"key":"f24","p":"ig_reels","src":"@Example_KoreaFirstTime","ok":true,"t":"Seoul subway transfer: follow the colors","d":"2026-10-01","dur":"0:22","pl":"서울 지하철","r":"서울","th":"tech_korea","seg":"inbound","sc":95,"w":["solo","friends"],"s":"환승 통로 바닥의 노선 색을 따라가면 된다는 설명입니다. 교통카드 충전은 현금만 되는 기계가 있다고 말합니다.","ev":"review"},
   {"key":"f25","p":"blog","src":"도시산책 노트 (예시 블로그)","ok":false,"t":"가성비 비즈니스호텔 세 곳, 같은 날 비교해 봤다","d":"2026-09-30","dur":"8분 읽기","pl":"부산역 인근","r":"부산 동구","th":"value","seg":"domestic_kr","sc":65,"w":["solo","friends"]},
   {"key":"f26","p":"yt_shorts","src":"@예시_골목여행","ok":true,"t":"전주 한옥마을, 한복 입고 걷기 좋은 시간대","d":"2026-09-28","dur":"0:35","pl":"전주 한옥마을","r":"전북 전주","th":"hanok_kculture","seg":"domestic_kr","sc":50,"w":["couple","friends","family"],"s":"오전 10시 전에는 골목이 한산해 사진 찍기 좋았다는 경험입니다. 한복 대여점 영업시간은 가게마다 다르다고 말합니다.","ev":"review"},
   {"key":"f27","p":"yt","src":"@예시_가족캠핑","ok":true,"t":"아이와 첫 해변 차박, 준비물 체크리스트","d":"2026-09-25","dur":"11:20","pl":"충남 서해안","r":"충남","th":"family","seg":"domestic_kr","sc":-80,"w":["family"],"s":"바람막이와 모래 털이 솔이 가장 유용했다는 경험입니다. 차박 허용 구역은 지자체 공지로 확인해야 합니다.","ev":"review"},
   {"key":"f28","p":"official","src":"예시 관광 안내","ok":true,"t":"가을 해변 야간 산책로 조명 운영 시간 안내","d":"2026-09-22","dur":"공지","pl":"광안리 해변","r":"부산 수영구","th":"couple_midlife","seg":"domestic_kr","sc":-15,"w":["couple","family","friends","solo"],"s":"해변 산책로 조명 운영 시간과 드론쇼 일정 안내입니다. 기상에 따라 취소될 수 있어 원문 확인이 필요합니다.","ev":"official"},
   {"key":"f29","p":"ig_reels","src":"@예시_주말부부","ok":true,"t":"하루 숙박비를 아끼고 저녁 한 끼에 쓴 날","d":"2026-09-20","dur":"0:27","pl":"여수 낭만포차 거리","r":"전남 여수","th":"worth","seg":"domestic_kr","sc":20,"w":["couple"],"s":"숙소는 시내 쪽으로 낮추고 바다 앞 저녁 식사에 예산을 옮겼더니 만족도가 높았다는 경험입니다. 주말 대기 시간은 30분 정도였다고 말합니다.","ev":"review"}
  ]$j$;
  cols jsonb := $j$[
   {"slug":"demo-busan-48h","t":"바다에서 시작해 야경으로 끝나는 부산 48시간","s":"해변 산책, 해안 골목, 다리 야경까지 이어지는 이야기","m":"mix","seg":"domestic_kr","items":["f13","f01","f09","DEMO-04","f19","f28","f04"]},
   {"slug":"demo-kids-sea","t":"아이와 바다, 비 오는 날의 대안까지","s":"가족 여행자가 실제로 막혔던 지점을 모았습니다","m":"sea","seg":"domestic_kr","items":["DEMO-01","f03","f06","DEMO-03","f12","f27","f08"]},
   {"slug":"demo-first-korea","t":"First time in Korea: 한옥에서 한강까지","s":"도착 준비부터 밤 산책까지, 방한 여행자를 위한 모음","m":"city","seg":"inbound","items":["DEMO-02","f15","f14","f24","f16","f11","f21","f10"]},
   {"slug":"demo-sea-or-city-stay","t":"해변 숙소냐 시내 숙소냐","s":"같은 도시에서 둘 다 묵어 본 사람들의 비교","m":"mix","seg":"domestic_kr","items":["DEMO-04","f07","f23","f25","f20"]},
   {"slug":"demo-city-night","t":"해 지고 나서 더 좋은 도시","s":"노을, 골목, 야시장까지 저녁 이후의 이야기","m":"city","seg":"domestic_kr","items":["f05","f18","f19","f29","f10","f11"]}
  ]$j$;
begin
  perform remove_demo();

  insert into staff(name, roles, is_demo) values ('[예시] 편집 담당', '{editor}', true) returning id into st_ed;
  insert into staff(name, roles, is_demo) values ('[예시] 제품 책임', '{product}', true) returning id into st_pm;
  insert into staff(name, roles, is_demo) values ('[예시] 운영 담당', '{ops}', true) returning id into st_op;

  -- ---------- 판단 문서: 실제와 같은 절차 (자산 승인 → 근거 확인 → 제작·검수·승인 → 공개) ----------
  for d in select * from jsonb_array_elements(docs) loop
    insert into places(slug, official_name, local_name, names_i18n, region, segment, theme, sub_questions, is_demo)
    values (d->>'slug', d->>'name', d->>'local', jsonb_build_object('en', d->>'en'), d->>'region',
            (d->>'segment')::segment_t, d->>'theme', array(select jsonb_array_elements_text(d->'subq')), true)
    returning id into pl;

    insert into assets(place_id, kind, source_type, uri, provider_name, rights_status, allowed_media, allow_edit,
                       third_party_checked, revoke_contact, evidence_uri, approved_by, approved_at, note)
    values (pl, 'photo', 'provider', 'demo/' || (d->>'slug') || '/room.jpg', d->>'name', 'approved', '{youtube,hub}', true,
            true, '예시 데이터 — 실제 계약 아님', 'demo/contracts/' || (d->>'slug') || '.pdf', st_ed, now(), '예시 자산')
    returning id into photo;
    insert into assets(place_id, kind, source_type, uri, provider_name, rights_status, allowed_media, allow_edit, allow_summary,
                       third_party_checked, revoke_contact, evidence_uri, approved_by, approved_at, note)
    values (pl, 'subtitle', 'creator', 'demo/' || (d->>'slug') || '/subtitles.vtt', '예시 크리에이터', 'approved', '{youtube,hub}', true, true,
            true, '예시 데이터 — 실제 협약 아님', 'demo/agreements/' || (d->>'slug') || '.pdf', st_ed, now(), '예시 협약 자막')
    returning id into sub;

    insert into content_jobs(job_no, place_id, question, segment, question_type, sea_city, owner_id)
    values (d->>'no', pl, d->>'q', (d->>'segment')::segment_t, d->>'qtype', (d->>'sea')::smallint, st_ed)
    returning id into jb;

    if d->>'target' = 'received' then continue; end if;

    insert into content_versions(job_id, version, lang, title, script, description, sponsored, disclosure, partner_links, prep_card, made_by)
    values (jb, 1, case when d->>'segment' = 'inbound' and d->>'no' = 'DEMO-06' then 'en' else 'ko' end, d->>'title', '[]', d->>'desc',
            d ? 'spon', d->>'spon', coalesce(d->'links', '[]'), coalesce(d->'prep', '{}'), st_ed)
    returning id into vr;
    insert into version_assets values (vr, photo);

    for c in select * from jsonb_array_elements(d->'claims') loop
      insert into claims(place_id, kind, body) values (pl, (c->>'k')::claim_kind_t, c->>'b') returning id into cl;
      insert into version_claims values (vr, cl);
      if c ? 'ev' then
        insert into evidence(place_id, kind, source_url, author, observed_at, room_type, segment_start, segment_end, subtitle_asset,
                             status, checked_by, checked_at)
        values (pl, (c->'ev'->>'k')::evidence_kind_t, c->'ev'->>'u', c->'ev'->>'a', (c->'ev'->>'d')::date, c->'ev'->>'r',
                (c->'ev'->>'s')::int, (c->'ev'->>'e')::int, case when c->'ev'->>'k' = 'review' then sub end,
                'verified', st_op, now())
        returning id into ev;
        insert into claim_evidence values (cl, ev);
      end if;
    end loop;

    -- 상태 전이: 트리거가 단계마다 권리·합성·검수·승인 조건을 다시 확인한다
    update content_jobs set status = 'material_check' where id = jb;
    if d->>'target' = 'held' then
      update content_jobs set status = 'held', hold_reason = d->>'hold' where id = jb;
      continue;
    end if;
    update content_jobs set status = 'ready' where id = jb;
    update content_jobs set status = 'rendering' where id = jb;
    update content_versions set render_uri = 'demo/renders/' || (d->>'no') || '_v1.mp4', reviewed_by = st_op where id = vr;
    update content_jobs set status = 'review' where id = jb;
    if d->>'target' = 'review' then continue; end if;
    update content_versions set approved_by = st_pm, approved_at = now() - interval '2 days' where id = vr;
    update content_jobs set status = 'approved' where id = jb;
    update content_jobs set status = 'published' where id = jb;
    n_docs := n_docs + 1;
  end loop;

  -- ---------- 매체 피드: 협약 출처는 요약까지, 협약 없는 출처는 제목만 ----------
  for it in select * from jsonb_array_elements(feed) loop
    select id into src from media_sources where platform = (it->>'p')::media_platform_t and handle = 'demo:' || (it->>'src') and is_demo;
    if src is null then
      insert into media_sources(platform, handle, display_name, url, agreement, summary_allowed, agreement_uri, revoke_contact, note, is_demo)
      values ((it->>'p')::media_platform_t, 'demo:' || (it->>'src'), it->>'src', 'https://example.com/',
              case when (it->>'ok')::boolean then 'agreed' else 'none' end::agreement_t, (it->>'ok')::boolean,
              case when (it->>'ok')::boolean then 'demo/agreements/source.pdf' end,
              case when (it->>'ok')::boolean then '예시 데이터 — 실제 협약 아님' end, '예시 출처', true)
      returning id into src;
    end if;
    insert into media_items(source_id, external_id, url, title, published_at, duration_label, lang, segment, theme, sea_city, companions,
                            place_label, region, summary, summary_status, evidence_kind, sponsored, disclosure, status, approved_by, approved_at,
                            place_id)
    values (src, 'demo-' || (it->>'key'), 'https://example.com/' || (it->>'key'), it->>'t', (it->>'d')::date, it->>'dur',
            case when it->>'t' ~ '^[A-Za-z]' then 'en' else 'ko' end, (it->>'seg')::segment_t, it->>'th', (it->>'sc')::smallint,
            array(select jsonb_array_elements_text(it->'w'))::companion_t[], it->>'pl', it->>'r', it->>'s',
            case when it ? 's' then 'verified' else 'none' end::summary_status_t, (it->>'ev')::evidence_kind_t,
            it ? 'spon', it->>'spon', 'approved', st_ed, now(),
            (select id from places where official_name = it->>'pl' and is_demo));
    n_items := n_items + 1;
  end loop;

  -- ---------- 컬렉션 ----------
  for col in select * from jsonb_array_elements(cols) loop
    insert into collections(slug, title, subtitle, segment, mood, status, editor_id, published_at, is_demo)
    values (col->>'slug', col->>'t', col->>'s', (col->>'seg')::segment_t, col->>'m', 'published', st_ed, now(), true)
    returning id into co;
    pos := 0;
    for k in select jsonb_array_elements_text(col->'items') loop
      pos := pos + 1;
      if k like 'DEMO-%' then
        select v.id into target from content_jobs j join lateral (select * from latest_version(j.id)) v on true where j.job_no = k;
        insert into collection_docs(collection_id, version_id, position) values (co, target::uuid, pos);
      else
        insert into collection_items(collection_id, item_id, position)
        select co, i.id, pos from media_items i join media_sources s on s.id = i.source_id
         where s.is_demo and i.external_id = 'demo-' || k;
      end if;
    end loop;
  end loop;

  return format('예시 데이터 넣음: 판단 문서 %s건 공개 · 진행 중 작업 3건 · 매체 피드 %s건 · 컬렉션 %s개',
                n_docs, n_items, jsonb_array_length(cols));
end $$;

-- collection_items.item_id 는 media_items 를 참조하므로, 판단 문서(공개 버전)는 별도 표로 컬렉션에 담는다
create table collection_docs (
  collection_id uuid references collections(id) on delete cascade,
  version_id    uuid references content_versions(id) on delete cascade,
  position      smallint not null default 0,
  primary key (collection_id, version_id)
);
grant all on trip.collection_docs to service_role;

-- 공개 컬렉션: 매체 아이템 + 판단 문서를 순서대로 (공개된 것만)
create or replace view public_collections as
select c.slug, c.title, c.subtitle, c.segment, c.mood, c.published_at,
       coalesce((select array_agg(x.id order by x.position) from (
           select ci.item_id as id, ci.position from collection_items ci join public_feed f on f.id = ci.item_id where ci.collection_id = c.id
           union all
           select cd.version_id, cd.position from collection_docs cd join public_feed f on f.id = cd.version_id where cd.collection_id = c.id
         ) x), '{}') as item_ids,
       c.is_demo
  from collections c
 where c.status = 'published';

-- 권한: 넣기·지우기는 service_role 만
revoke execute on function trip.load_demo(), trip.remove_demo() from public, anon, authenticated;
grant execute on function trip.load_demo(), trip.remove_demo() to service_role;
grant select on trip.public_hub, trip.public_cards, trip.public_feed, trip.public_collections to anon, authenticated;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'trip'
  loop execute format('alter function %s set search_path = trip, public', f.sig); end loop;
end $$;
