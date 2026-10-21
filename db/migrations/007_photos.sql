-- =====================================================================
-- 실제 사진: 카드 썸네일·판단 문서 사진·히어로 사진
-- 원칙
--  - 사진도 자산(assets)이다. 권리 승인(허브 사용 허용) 상태일 때만 공개 뷰에 나간다.
--  - 출처·촬영자 표기(attribution_text)를 함께 내보내 화면에 크레딧을 붙인다.
--  - 외부 무료 사진(Unsplash 라이선스)은 원본 주소를 그대로 쓰고(복제 보관 없음), 라이선스 주소를 증빙으로 남긴다.
--  - 실제 장소 이름이 붙은 카드에는 그 장소이거나 장소를 특정하지 않는 일반 장면만 쓴다(다른 명소 사진 금지).
-- =====================================================================
set search_path = trip, public;

-- 히어로 사진 순서 (null = 히어로 아님)
alter table assets add column hero_order smallint;

-- 히어로: 권리 승인된 사진만, 순서대로
create or replace view public_hero as
select a.uri, a.attribution_text as credit, a.hero_order
  from assets a
 where a.hero_order is not null and a.kind = 'photo' and asset_usable(a, 'hub')
 order by a.hero_order;

-- 피드: 썸네일 크레딧 열 추가 (끝에 덧붙임), 판단 문서는 버전에 연결된 승인 사진을 썸네일로
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
       (s.is_demo or coalesce(p.is_demo, false)) as is_demo,
       (select a.attribution_text from assets a where a.id = i.thumbnail_asset and asset_usable(a, 'hub')) as thumbnail_credit
  from media_items i
  join media_sources s on s.id = i.source_id
  left join content_jobs j on j.id = i.job_id
  left join places p on p.id = i.place_id
 where i.status = 'approved' and s.agreement <> 'ended' and coalesce(p.is_medical, false) = false
union all
select v.id, 'hub_doc'::media_platform_t, '편집팀 판단 문서', null, '/p/' || h.job_no, h.question, h.checked_at::date,
       '판단 문서', h.lang, h.segment, h.theme, coalesce(j.sea_city, 0), '{}'::companion_t[], h.official_name, h.region,
       h.description, null, 'official', h.sponsored, h.disclosure, ph.uri, h.job_no, h.is_demo, ph.attribution_text
  from public_hub h
  join content_versions v on v.id = h.version_id
  join content_jobs j on j.id = v.job_id
  left join lateral (select a.uri, a.attribution_text from version_assets va join assets a on a.id = va.asset_id
                      where va.version_id = v.id and a.kind = 'photo' and asset_usable(a, 'hub')
                      order by a.created_at limit 1) ph on true;

-- 판단 문서 페이지 상단 사진
create or replace view public_hub_photo as
select h.job_no, ph.uri, ph.attribution_text as credit
  from public_hub h
  join lateral (select a.uri, a.attribution_text from version_assets va join assets a on a.id = va.asset_id
                 where va.version_id = h.version_id and a.kind = 'photo' and asset_usable(a, 'hub')
                 order by a.created_at limit 1) ph on true;

-- ---------- 예시 데이터에 실제 사진 붙이기 ----------
-- 사진 대응표: 키(피드 f.. / 판단 문서 DEMO-..) → Unsplash 사진 id, 촬영자
create or replace function demo_photo_map() returns jsonb language sql immutable as $j$
select $m${
 "f01":["1702741274890-5160282e53bb","Ryoo Geon Uk"],
 "f02":["1719306666621-288f743ff5c6","YMA"],
 "f03":["1720252741302-77213465eab2","Seongil Park"],
 "f04":["1597046724111-37aed16b61b1","Cheolmin Kim"],
 "f05":["1635555926145-5d26759d62ef","NK Lee"],
 "f06":["1611757947203-fcc3662af80c","Doyle Shin"],
 "f07":["1692074881533-4f95e464c110","Daniel Bae"],
 "f08":["1653818283100-115421ad43e8","Daesun Kim"],
 "f09":["1661175844328-72e460f2f8a6","Photos of Korea"],
 "f10":["1601747301682-dc7e5dcb35c0","Jul Lee"],
 "f11":["1570365473297-4a454f76ff0e","Polina Kuzovkova"],
 "f12":["1700621496615-6ee6240503ef","Jinhan Moon"],
 "f13":["1567430030982-35415d233ce9","Keiteu Ko"],
 "f14":["1633839323577-fe4bd3079fab","Finn"],
 "f15":["1618237586696-d3690dad22e3","zero take"],
 "f16":["1746240174940-cf2f3bbb1982","lee seunghyub"],
 "f17":["1720252741168-dfa56535b42a","Seongil Park"],
 "f18":["1697201193383-601d4f3b7339","rawkkim"],
 "f19":["1686232344073-f1b7dd22ca6b","Nichika Sakurai"],
 "f20":["1772869603278-2e8e01060843","yukuan zhao"],
 "f21":["1653207207881-e4e0cd4a8ee2","HANVIN CHEONG"],
 "f22":["1702040093476-2446d4ea1d50","Junseo Jang"],
 "f23":["1776876648949-63ccabf63b10","Natacha Missakian"],
 "f24":["1737969925456-ef52fbec2c55","KS KYUNG"],
 "f25":["1748787105824-ecc285d2307f","Cecelia Chang"],
 "f26":["1653230675261-fe00bde32c8e","Minku Kang"],
 "f27":["1584345015538-213f90f9ccbc","Soop kim"],
 "f28":["1702741274880-b37b5279f393","Ryoo Geon Uk"],
 "f29":["1675918443734-b234dd8c3e90","yujeong Huh"],
 "DEMO-01":["1721222203415-69033eaf3bd1","Sanju Pandita"],
 "DEMO-02":["1618237600880-fb9d72e98393","zero take"],
 "DEMO-03":["1691807989753-b74fee2abdb8","insung yoon"],
 "DEMO-04":["1777017246552-8b0e36b92d52","Arthur Charles Pratt"],
 "DEMO-05":["1611757947203-fcc3662af80c","Doyle Shin"],
 "DEMO-06":["1570365473297-4a454f76ff0e","Polina Kuzovkova"]
}$m$::jsonb
$j$;

create or replace function unsplash_uri(photo text) returns text language sql immutable as $$
  select 'https://images.unsplash.com/photo-' || photo || '?auto=format&fit=crop&q=72'
$$;

alter function load_demo() rename to load_demo_base;

create or replace function load_demo() returns text language plpgsql as $$
declare r text; k text; v jsonb; st uuid; a uuid; n int := 0;
begin
  r := load_demo_base();
  select id into st from staff where is_demo and 'editor' = any(roles) order by created_at limit 1;
  for k, v in select * from jsonb_each(demo_photo_map()) loop
    if k like 'DEMO-%' then
      -- 판단 문서: 이미 승인된 예시 자산(사진)의 주소와 크레딧을 실제 사진으로 바꾼다
      update assets a set uri = unsplash_uri(v->>0), provider_name = 'Unsplash · ' || (v->>1),
             attribution_text = 'Photo: ' || (v->>1) || ' / Unsplash', evidence_uri = 'https://unsplash.com/license'
        from content_jobs j
       where j.job_no = k and a.place_id = j.place_id and a.kind = 'photo';
    else
      insert into assets(kind, source_type, uri, provider_name, rights_status, allowed_media, third_party_checked,
                         attribution_text, revoke_contact, evidence_uri, approved_by, approved_at, note)
      values ('photo', 'provider', unsplash_uri(v->>0), 'Unsplash · ' || (v->>1), 'approved', '{hub}', true,
              'Photo: ' || (v->>1) || ' / Unsplash', 'Unsplash 라이선스 — 삭제·철회 시 교체', 'https://unsplash.com/license',
              st, now(), 'demo-photo')
      returning id into a;
      update media_items i set thumbnail_asset = a
        from media_sources s
       where s.id = i.source_id and s.is_demo and i.external_id = 'demo-' || k;
      n := n + 1;
    end if;
  end loop;
  return r || format(' · 실제 사진 %s장 연결', n + 4);
end $$;

alter function remove_demo() rename to remove_demo_base;

create or replace function remove_demo() returns text language plpgsql as $$
declare r text;
begin
  r := remove_demo_base();
  delete from assets a where a.note = 'demo-photo'
    and not exists (select 1 from media_items i where i.thumbnail_asset = a.id);
  -- 사진 승인자로 남아 있던 예시 운영자도 정리
  delete from staff s where s.is_demo
    and not exists (select 1 from job_transitions t where t.actor_id = s.id)
    and not exists (select 1 from content_versions v where s.id in (v.made_by, v.reviewed_by, v.approved_by))
    and not exists (select 1 from media_items i where i.approved_by = s.id)
    and not exists (select 1 from evidence e where e.checked_by = s.id)
    and not exists (select 1 from assets a where a.approved_by = s.id);
  return r;
end $$;

-- ---------- 히어로 사진 (예시 데이터와 별개로 유지) ----------
-- 승인자는 실제 운영자(제품 책임). 운영자가 아직 없는 DB(시험용)에서는 넣지 않는다.
do $$
declare st uuid;
begin
  select id into st from trip.staff where not is_demo and 'product' = any(roles) order by created_at limit 1;
  if st is null then return; end if;
  insert into trip.assets(kind, source_type, uri, provider_name, rights_status, allowed_media, third_party_checked,
                          attribution_text, revoke_contact, evidence_uri, approved_by, approved_at, note, hero_order)
  values
   ('photo','provider', trip.unsplash_uri('1647767444107-8f383924382d'), 'Unsplash · Yujin Seo', 'approved', '{hub}', true,
    'Photo: Yujin Seo / Unsplash', 'Unsplash 라이선스 — 삭제·철회 시 교체', 'https://unsplash.com/license', st, now(), '히어로: 해운대 바다와 도시', 1),
   ('photo','provider', trip.unsplash_uri('1633839537302-3c195a4893be'), 'Unsplash · Suyeon Jeong', 'approved', '{hub}', true,
    'Photo: Suyeon Jeong / Unsplash', 'Unsplash 라이선스 — 삭제·철회 시 교체', 'https://unsplash.com/license', st, now(), '히어로: 광안리 해변과 다리', 2),
   ('photo','provider', trip.unsplash_uri('1716945232299-4b44e5730e07'), 'Unsplash · Minku Kang', 'approved', '{hub}', true,
    'Photo: Minku Kang / Unsplash', 'Unsplash 라이선스 — 삭제·철회 시 교체', 'https://unsplash.com/license', st, now(), '히어로: 한강과 도시', 3);
end $$;

-- 이미 예시 데이터가 들어 있는 DB(운영)라면 사진까지 붙은 새 예시로 바로 바꾼다
do $$
begin
  if exists (select 1 from trip.places where is_demo) then perform trip.load_demo(); end if;
end $$;

-- 권한
grant select on trip.public_hero, trip.public_hub_photo, trip.public_feed to anon, authenticated;
revoke execute on function trip.load_demo(), trip.remove_demo(), trip.load_demo_base(), trip.remove_demo_base() from public, anon, authenticated;
grant execute on function trip.load_demo(), trip.remove_demo(), trip.load_demo_base(), trip.remove_demo_base() to service_role;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'trip'
  loop execute format('alter function %s set search_path = trip, public', f.sig); end loop;
end $$;
