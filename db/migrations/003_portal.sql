-- =====================================================================
-- 미니 포털: 여러 매체의 콘텐츠를 모아 요약해 보여 주는 계층
-- 원칙
--  - 외부 콘텐츠는 '링크 + 편집 요약'만 노출한다. 원문·영상은 복제하지 않는다.
--  - 요약은 출처가 요약을 허락했거나(협약) 자사 채널일 때만 공개한다. 아니면 제목만.
--  - 썸네일은 권리 승인된 자산만. 없으면 화면에서 일러스트 포스터를 그린다.
--  - 자사 채널에 공개된 쇼츠는 자동으로 피드에 들어온다.
-- =====================================================================
set search_path = trip, public;

create type media_platform_t as enum ('yt_shorts', 'yt', 'ig_reels', 'ig_post', 'tiktok', 'blog', 'official', 'news', 'hub_doc');
create type item_status_t    as enum ('candidate', 'approved', 'hidden', 'withdrawn');
create type summary_status_t as enum ('none', 'draft', 'verified');
create type agreement_t      as enum ('none', 'negotiating', 'agreed', 'ended');
create type companion_t      as enum ('family', 'couple', 'friends', 'solo');

-- ---------- 출처(채널·블로그·기관) ----------
create table media_sources (
  id               uuid primary key default gen_random_uuid(),
  platform         media_platform_t not null,
  handle           text not null,                 -- @채널명, 블로그 주소, 기관명
  display_name     text not null,
  url              text,
  is_own           boolean not null default false, -- 자사 채널
  agreement        agreement_t not null default 'none',
  summary_allowed  boolean not null default false, -- 요약 허락 (협약서 기준)
  thumbnail_allowed boolean not null default false,
  agreement_uri    text,                           -- 협약서·동의 기록 위치
  revoke_contact   text,
  note             text,
  created_at       timestamptz not null default now(),
  unique (platform, handle),
  constraint agreed_needs_proof check (agreement <> 'agreed' or (agreement_uri is not null and revoke_contact is not null)),
  constraint summary_needs_agreement check (not summary_allowed or is_own or agreement = 'agreed')
);

-- ---------- 콘텐츠 아이템 ----------
create table media_items (
  id               uuid primary key default gen_random_uuid(),
  source_id        uuid not null references media_sources(id),
  external_id      text not null,                  -- 영상 ID, 글 주소 등
  url              text not null,                  -- 원본 링크 (항상 원본으로 보냄)
  title            text not null,
  published_at     date not null,
  duration_label   text,                           -- 0:34, 6분 읽기, 공지
  lang             text not null default 'ko',
  segment          segment_t not null,
  theme            text not null,
  sea_city         smallint not null default 0 check (sea_city between -100 and 100), -- -100 바다 … +100 도시
  companions       companion_t[] not null default '{}',
  place_id         uuid references places(id),
  place_label      text,
  region           text,
  summary          text,                           -- 편집팀이 쓴 요약 (원문 문장 복제 금지)
  summary_status   summary_status_t not null default 'none',
  summary_evidence uuid references evidence(id),   -- 요약 근거 (협약 자막 등)
  evidence_kind    evidence_kind_t,                -- official / review / editorial
  thumbnail_asset  uuid references assets(id),
  sponsored        boolean not null default false,
  disclosure       text,
  job_id           uuid references content_jobs(id), -- 판단 문서와 연결 (hub_doc 또는 관련 문서)
  status           item_status_t not null default 'candidate',
  approved_by      uuid references staff(id),
  approved_at      timestamptz,
  created_at       timestamptz not null default now(),
  unique (source_id, external_id),
  constraint sponsor_disclosed check (not sponsored or disclosure is not null),
  constraint approved_has_approver check (status <> 'approved' or (approved_by is not null and approved_at is not null)),
  constraint verified_summary_has_text check (summary_status <> 'verified' or summary is not null)
);
create index media_items_feed on media_items (status, published_at desc);
create index media_items_place on media_items (place_id);

-- 요약 '확인완료'는 출처가 요약을 허락했을 때만
create or replace function trg_item_guard() returns trigger language plpgsql as $$
declare s media_sources; p places;
begin
  select * into s from media_sources where id = new.source_id;
  if new.summary_status = 'verified' and not (s.summary_allowed or s.is_own) then
    raise exception '요약 허락이 없는 출처(%)의 요약은 확인완료로 둘 수 없습니다', s.display_name;
  end if;
  if new.thumbnail_asset is not null and not exists (
       select 1 from assets a where a.id = new.thumbnail_asset and asset_usable(a, 'hub')) then
    raise exception '썸네일 자산이 허브 사용 승인 상태가 아닙니다';
  end if;
  if new.status = 'approved' then
    if s.agreement = 'ended' then raise exception '협약이 끝난 출처의 콘텐츠는 승인할 수 없습니다'; end if;
    if new.place_id is not null then
      select * into p from places where id = new.place_id;
      if p.is_medical then raise exception '의료 관련 장소 콘텐츠는 별도 검토 전 승인할 수 없습니다'; end if;
    end if;
  end if;
  return new;
end $$;
create trigger item_guard before insert or update on media_items
for each row execute function trg_item_guard();

-- 출처 협약 종료·요약 허락 철회 → 요약 내리고, 협약 종료면 아이템 숨김
create or replace function trg_source_change() returns trigger language plpgsql as $$
begin
  if old.summary_allowed and not new.summary_allowed and not new.is_own then
    update media_items set summary_status = 'none' where source_id = new.id and summary_status <> 'none';
  end if;
  if new.agreement = 'ended' and old.agreement <> 'ended' then
    update media_items set status = 'hidden' where source_id = new.id and status = 'approved';
  end if;
  return new;
end $$;
create trigger source_change after update on media_sources
for each row execute function trg_source_change();

-- 썸네일 자산 철회 → 썸네일만 떼어 냄 (아이템은 일러스트 포스터로 계속 노출)
create or replace function trg_thumb_revoke() returns trigger language plpgsql as $$
begin
  if new.rights_status in ('revoked', 'expired') and old.rights_status = 'approved' then
    update media_items set thumbnail_asset = null where thumbnail_asset = new.id;
  end if;
  return new;
end $$;
create trigger thumb_revoke after update of rights_status on assets
for each row execute function trg_thumb_revoke();

-- 자사 유튜브 쇼츠가 실제 공개되면 피드 후보로 자동 등록 (편집팀이 승인하면 노출)
create or replace function trg_publication_to_feed() returns trigger language plpgsql as $$
declare v content_versions; j content_jobs; p places; src uuid;
begin
  if new.channel <> 'youtube' or new.status <> 'public' or old.status = 'public' then return new; end if;
  select id into src from media_sources where is_own and platform = 'yt_shorts' order by created_at limit 1;
  if src is null then return new; end if;
  select * into v from content_versions where id = new.version_id;
  select * into j from content_jobs where id = v.job_id;
  select * into p from places where id = j.place_id;
  insert into media_items (source_id, external_id, url, title, published_at, duration_label, lang, segment, theme,
                           place_id, place_label, region, summary, summary_status, evidence_kind, sponsored, disclosure, job_id)
  values (src, new.external_id, coalesce(new.url, 'https://youtube.com/shorts/' || new.external_id), v.title, current_date, '쇼츠',
          v.lang, j.segment, p.theme, p.id, p.official_name, p.region, v.description,
          case when v.description is null then 'none'::summary_status_t else 'draft'::summary_status_t end,
          'editorial', v.sponsored, v.disclosure, j.id)
  on conflict (source_id, external_id) do nothing;
  return new;
end $$;
create trigger publication_to_feed after update of status on publications
for each row execute function trg_publication_to_feed();

-- ---------- 컬렉션 (편집팀 묶음) ----------
create table collections (
  id           uuid primary key default gen_random_uuid(),
  slug         text unique not null,
  title        text not null,
  subtitle     text,
  segment      segment_t,
  mood         text not null default 'mix' check (mood in ('sea', 'mix', 'city')),
  status       text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  editor_id    uuid references staff(id),
  published_at timestamptz,
  created_at   timestamptz not null default now()
);
create table collection_items (
  collection_id uuid references collections(id) on delete cascade,
  item_id       uuid references media_items(id) on delete cascade,
  position      smallint not null default 0,
  note          text,                       -- 편집 한 줄 (왜 이 묶음에 넣었는지)
  primary key (collection_id, item_id)
);

-- ---------- 공개 뷰 ----------
create or replace view public_feed as
select i.id, s.platform, s.display_name as creator, s.url as source_url, i.url, i.title, i.published_at,
       i.duration_label, i.lang, i.segment, i.theme, i.sea_city, i.companions, i.place_label, i.region,
       case when i.summary_status = 'verified' and (s.summary_allowed or s.is_own) then i.summary end as summary,
       case when i.summary_status = 'verified' and (s.summary_allowed or s.is_own) then null
            else '자막이나 글을 제공받지 않아 요약하지 않았습니다. 원본에서 확인해 주세요.' end as summary_reason,
       case when i.summary_status = 'verified' then coalesce(i.evidence_kind::text, 'review') else 'none' end as evidence,
       i.sponsored, i.disclosure,
       (select a.uri from assets a where a.id = i.thumbnail_asset and asset_usable(a, 'hub')) as thumbnail_uri,
       j.job_no
  from media_items i
  join media_sources s on s.id = i.source_id
  left join content_jobs j on j.id = i.job_id
  left join places p on p.id = i.place_id
 where i.status = 'approved' and s.agreement <> 'ended' and coalesce(p.is_medical, false) = false
union all
-- 공개된 판단 문서도 피드 아이템으로 노출
select v.id, 'hub_doc'::media_platform_t, '편집팀 판단 문서', null, '/p/' || h.job_no, h.question, h.checked_at::date,
       '판단 문서', h.lang, h.segment, h.theme, 0, '{}'::companion_t[], h.official_name, h.region,
       h.description, null, 'official', h.sponsored, h.disclosure, null, h.job_no
  from public_hub h join content_versions v on v.id = h.version_id;

create or replace view public_collections as
select c.slug, c.title, c.subtitle, c.segment, c.mood, c.published_at,
       coalesce(array_agg(ci.item_id order by ci.position) filter (where f.id is not null), '{}') as item_ids
  from collections c
  left join collection_items ci on ci.collection_id = c.id
  left join public_feed f on f.id = ci.item_id
 where c.status = 'published'
 group by c.id;

-- 매체별 노출 집계 (지표용: 분모 포함)
create or replace view metric_feed_mix as
select f.platform, count(*) as items,
       count(*) filter (where f.summary is not null) as summarized
  from public_feed f group by f.platform;


-- ---------- 포털 이벤트: 매체 원본 이동·컬렉션 열람도 기록 (개인 식별정보 없음) ----------
alter table hub_events add column item_id uuid;
alter table hub_events drop constraint hub_events_event_check;
alter table hub_events add constraint hub_events_event_check
  check (event in ('hub_arrive','source_open','partner_click','card_save','share','media_open','collection_open','feed_filter'));
drop policy hub_events_insert on hub_events;
create policy hub_events_insert on hub_events for insert to anon, authenticated
  with check (event in ('hub_arrive','source_open','partner_click','card_save','share','media_open','collection_open','feed_filter') and not is_test);

-- 매체별 원본 이동률: 분모 = 해당 매체 아이템 상세를 연 세션, 분자 = 원본으로 이동한 세션
create or replace view metric_media_open as
select f.platform, count(distinct e.session_id) as sessions_opened
  from hub_events e join public_feed f on f.id = e.item_id
 where e.event = 'media_open' and not e.is_test group by f.platform;

-- 권한
grant select on trip.public_feed, trip.public_collections to anon, authenticated;
grant all on trip.media_sources, trip.media_items, trip.collections, trip.collection_items to service_role;

-- 함수 search_path 고정 (001과 동일 원칙)
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'trip'
  loop execute format('alter function %s set search_path = trip, public', f.sig); end loop;
end $$;
