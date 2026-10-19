-- =====================================================================
-- 롱폼 = 공개된 쇼츠 묶음 + 새 해설 (서비스기획서 5장)
-- 수치 기준(누적 30편, 묶음 8편, 관측 14일, 확인일 90일)은 운영 제안 — longform_settings 에서 조정
-- =====================================================================
set search_path = trip, public;

-- 쇼츠 작업에 묶음 태그 (질문 유형, 바다↔도시 지수). 지역·테마는 places 에서 읽는다
alter table content_jobs add column question_type text;      -- 침구·객실 / 이동·접근 / 우천 대안 / 도착 준비 …
alter table content_jobs add column sea_city smallint not null default 0 check (sea_city between -100 and 100);

create table longform_settings (
  id                 boolean primary key default true check (id),
  min_channel_shorts integer not null default 30,   -- 채널 전체 공개 쇼츠 누적
  min_bundle_shorts  integer not null default 8,    -- 묶음당 쇼츠 수
  min_age_days       integer not null default 14,   -- 공개 후 관측 기간
  recheck_days       integer not null default 90,   -- 근거 확인일이 이보다 오래되면 재확인
  rights_margin_days integer not null default 30    -- 자산 사용 기한이 롱폼 공개 후 최소 이만큼 남아야 함
);
insert into longform_settings default values;

-- 공개된 쇼츠 풀: 롱폼 재료로 쓸 수 있는지 항목별로 판정
create or replace view shorts_pool as
with s as (select * from longform_settings),
pub as (
  select distinct on (v.job_id) v.job_id, v.id as version_id, pb.external_id, pb.verified_at as public_since
    from publications pb join content_versions v on v.id = pb.version_id
   where pb.channel = 'youtube' and pb.status = 'public'
   order by v.job_id, v.version desc
)
select j.id as job_id, j.job_no, pub.version_id, pub.external_id, pub.public_since,
       p.region, p.theme, j.question_type, j.sea_city, j.segment, v.sponsored, v.disclosure,
       (pub.public_since <= now() - make_interval(days => s.min_age_days)) as age_ok,
       not exists (select 1 from version_assets va join assets a on a.id = va.asset_id
                   where va.version_id = pub.version_id
                     and not (asset_usable(a, 'youtube') and a.allow_edit
                              and (a.expires_at is null or a.expires_at > now() + make_interval(days => s.rights_margin_days)))) as rights_ok,
       cardinality(version_blockers(pub.version_id, 'youtube')) = 0 as evidence_ok,
       not exists (select 1 from corrections c
                   where c.status in ('received', 'investigating')
                     and (c.place_id = j.place_id
                          or c.claim_id in (select claim_id from version_claims where version_id = pub.version_id))) as corrections_ok,
       not exists (select 1 from version_claims vc join claim_evidence ce on ce.claim_id = vc.claim_id
                   join evidence e on e.id = ce.evidence_id
                   where vc.version_id = pub.version_id and e.checked_at < now() - make_interval(days => s.recheck_days)) as fresh
  from pub
  join content_jobs j on j.id = pub.job_id
  join content_versions v on v.id = pub.version_id
  join places p on p.id = j.place_id
  cross join s
 where j.status = 'published' and not p.is_medical;

create or replace view shorts_pool_eligible as
select *, (age_ok and rights_ok and evidence_ok and corrections_ok and fresh) as eligible from shorts_pool;

-- 롱폼 후보 묶음: 지역 / 질문 유형 × 테마
create or replace view longform_candidates as
with s as (select * from longform_settings),
total as (select count(*) as n from shorts_pool),
b as (
  select 'region'::text as bundle_type, region as bundle_key, job_id, eligible, sponsored from shorts_pool_eligible where region is not null
  union all
  select 'question', question_type || ' × ' || theme, job_id, eligible, sponsored from shorts_pool_eligible where question_type is not null
)
select b.bundle_type, b.bundle_key, count(*) as shorts, count(*) filter (where b.eligible) as eligible_shorts,
       bool_or(b.sponsored) as has_sponsored, total.n as channel_shorts,
       (total.n >= s.min_channel_shorts and count(*) filter (where b.eligible) >= s.min_bundle_shorts) as ready,
       case when total.n < s.min_channel_shorts then format('채널 공개 쇼츠 %s/%s편', total.n, s.min_channel_shorts)
            when count(*) filter (where b.eligible) < s.min_bundle_shorts then format('묶음 조건 통과 쇼츠 %s/%s편', count(*) filter (where b.eligible), s.min_bundle_shorts)
            else '롱폼 착수 가능' end as reason
  from b cross join s cross join total
 group by b.bundle_type, b.bundle_key, total.n, s.min_channel_shorts, s.min_bundle_shorts
 order by ready desc, eligible_shorts desc;

-- ---------- 롱폼 프로젝트 ----------
create type longform_status_t as enum ('planning', 'rights_check', 'editing', 'review', 'approved', 'published', 'held');
create type longform_format_t as enum ('route', 'compare', 'viewer_qa', 'inbound_prep');  -- 지역 동선형 / 같은 질문 비교형 / 시청자 질문 답변형 / 방한 준비형

create sequence longform_no_seq start 1;
create table longform_projects (
  id            uuid primary key default gen_random_uuid(),
  code          text unique not null default ('LF-' || lpad(nextval('trip.longform_no_seq')::text, 4, '0')),
  title         text not null,
  format        longform_format_t not null,
  bundle_type   text not null check (bundle_type in ('region', 'question')),
  bundle_key    text not null,
  intro_script  text,              -- 새로 쓰는 도입 해설
  update_notes  text,              -- 쇼츠 공개 이후 바뀐 정보
  disclosure    text,              -- 묶음에 협찬 쇼츠가 있으면 필수
  status        longform_status_t not null default 'planning',
  hold_reason   text,
  render_uri    text,
  made_by       uuid references staff(id),
  approved_by   uuid references staff(id),
  approved_at   timestamptz,
  youtube_id    text,
  created_at    timestamptz not null default now(),
  constraint lf_maker_not_approver check (approved_by is null or made_by is null or approved_by <> made_by)
);

create table longform_chapters (
  project_id      uuid references longform_projects(id) on delete cascade,
  job_id          uuid references content_jobs(id),
  position        smallint not null,
  chapter_title   text not null,
  new_commentary  text,            -- 이 챕터에 새로 붙이는 비교·해설 (빈 칸이면 승인 불가)
  primary key (project_id, job_id)
);

-- 롱폼 재편집 사용 범위 재확인 기록 (쇼츠 승인이 롱폼까지 자동으로 넓어지지 않음)
create table longform_rights (
  project_id      uuid references longform_projects(id) on delete cascade,
  asset_id        uuid references assets(id),
  reconfirmed_by  uuid not null references staff(id),
  reconfirmed_at  timestamptz not null default now(),
  evidence_uri    text not null,
  primary key (project_id, asset_id)
);

create or replace function longform_blockers(p_id uuid) returns text[] language plpgsql stable as $$
declare r text[] := '{}'; lp longform_projects; s longform_settings; n int; total int;
begin
  select * into lp from longform_projects where id = p_id;
  select * into s from longform_settings;
  select count(*) into total from shorts_pool;
  if total < s.min_channel_shorts then r := r || format('채널 공개 쇼츠 %s/%s편', total, s.min_channel_shorts); end if;

  select count(*) into n from longform_chapters where project_id = p_id;
  if n < s.min_bundle_shorts then r := r || format('챕터(쇼츠) %s/%s편', n, s.min_bundle_shorts); end if;

  select count(*) into n from longform_chapters c left join shorts_pool_eligible e on e.job_id = c.job_id
   where c.project_id = p_id and coalesce(e.eligible, false) = false;
  if n > 0 then r := r || format('묶음 기준 미달 쇼츠 %s편 (관측기간·권리·근거·정정·확인일)', n); end if;

  select count(*) into n from longform_chapters c join shorts_pool e on e.job_id = c.job_id
   where c.project_id = p_id and not (case lp.bundle_type when 'region' then e.region = lp.bundle_key
                                       else e.question_type || ' × ' || e.theme = lp.bundle_key end);
  if n > 0 then r := r || format('묶음 키와 다른 쇼츠 %s편', n); end if;

  select count(*) into n from longform_chapters c join shorts_pool e on e.job_id = c.job_id
    join version_assets va on va.version_id = e.version_id
   where c.project_id = p_id and not exists (select 1 from longform_rights lr where lr.project_id = p_id and lr.asset_id = va.asset_id);
  if n > 0 then r := r || format('롱폼 사용 범위 재확인 안 된 자산 %s건', n); end if;

  if coalesce(trim(lp.intro_script), '') = '' then r := r || '새 도입 해설 없음'; end if;
  select count(*) into n from longform_chapters where project_id = p_id and coalesce(trim(new_commentary), '') = '';
  if n > 0 then r := r || format('새 해설 없는 챕터 %s개 (단순 이어붙이기 금지)', n); end if;

  if exists (select 1 from longform_chapters c join shorts_pool e on e.job_id = c.job_id where c.project_id = p_id and e.sponsored)
     and lp.disclosure is null then r := r || '협찬 쇼츠 포함 — 롱폼 제휴 표시 필요'; end if;
  return r;
end $$;

create or replace function trg_longform_status() returns trigger language plpgsql as $$
declare b text[];
begin
  if new.status = old.status then return new; end if;
  if new.status = 'held' and coalesce(new.hold_reason, '') = '' then raise exception '보류에는 사유가 필요합니다'; end if;
  if new.status in ('review', 'approved', 'published') and new.render_uri is null then
    raise exception '편집 파일(render_uri) 없이 % 상태로 넘길 수 없습니다', new.status;
  end if;
  if new.status in ('approved', 'published') then
    if new.approved_by is null then raise exception '승인자 기록 없이 승인할 수 없습니다'; end if;
    b := longform_blockers(new.id);
    if cardinality(b) > 0 then raise exception '롱폼 승인 차단: %', array_to_string(b, ' / '); end if;
  end if;
  return new;
end $$;
create trigger longform_status before update of status on longform_projects
for each row execute function trg_longform_status();

-- 챕터의 쇼츠 자산이 철회되면 롱폼도 보류
create or replace function trg_longform_asset_revoke() returns trigger language plpgsql as $$
begin
  if new.rights_status in ('revoked', 'expired') and old.rights_status = 'approved' then
    update longform_projects lp set status = 'held', hold_reason = '챕터 자산 권리 ' || new.rights_status::text
     where lp.status not in ('held', 'planning')
       and exists (select 1 from longform_chapters c join content_versions v on v.job_id = c.job_id
                   join version_assets va on va.version_id = v.id
                   where c.project_id = lp.id and va.asset_id = new.id);
  end if;
  return new;
end $$;
create trigger longform_asset_revoke after update of rights_status on assets
for each row execute function trg_longform_asset_revoke();

grant all on trip.longform_settings, trip.longform_projects, trip.longform_chapters, trip.longform_rights to service_role;
grant select on trip.shorts_pool, trip.shorts_pool_eligible, trip.longform_candidates to service_role;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'trip'
  loop execute format('alter function %s set search_path = trip, public', f.sig); end loop;
end $$;
