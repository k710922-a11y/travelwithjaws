-- =====================================================================
-- 여행 쇼츠·메타리뷰 플랫폼 — 핵심 스키마 (계획서 35~38쪽 기준)
-- 원칙: 정보 / 근거 / 권리를 따로 저장하고, 승인 기록 없이는 공개되지 않는다.
-- 대상: Postgres 15+ (셀프호스팅 Supabase 호환)
-- =====================================================================
create extension if not exists pgcrypto;
create schema if not exists trip;
set search_path = trip, public;

-- ---------- 열거형 ----------
create type segment_t      as enum ('domestic_kr', 'inbound');           -- 국문 / 방한
create type rights_t       as enum ('unverified', 'pending', 'approved', 'revoked', 'expired');
create type asset_kind_t   as enum ('photo', 'video', 'subtitle', 'audio', 'music', 'font', 'voice');
create type asset_src_t    as enum ('provider', 'public_kogl', 'creator', 'own_shoot', 'generated');
create type evidence_kind_t as enum ('official', 'review', 'editorial');   -- 공식안내 / 후기관찰 / 편집해석
create type verify_t       as enum ('verified', 'needs_check', 'held');    -- 확인완료 / 추가확인 / 공개보류
create type claim_kind_t   as enum ('fact', 'experience', 'interpretation', 'unverified');
create type job_status_t   as enum (
  'received',        -- 접수
  'material_check',  -- 자료 확인
  'ready',           -- 제작 대기
  'rendering',       -- 합성
  'review',          -- 검수
  'approved',        -- 승인
  'published',       -- 공개
  'held'             -- 보류
);
create type pub_status_t   as enum ('queued', 'uploaded_private', 'public', 'failed', 'needs_fix', 'withdrawn');
create type channel_t      as enum ('youtube', 'instagram', 'hub');
create type correction_t   as enum ('received', 'investigating', 'fixed', 'rejected');

-- ---------- 사람/역할 (계획서 41쪽: 제작·검수·승인 기록 분리) ----------
create table staff (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  roles       text[] not null default '{}',   -- product, editor, tech, partner, ops
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ---------- 장소 ----------
create table places (
  id            uuid primary key default gen_random_uuid(),
  slug          text unique not null,
  official_name text not null,                -- 공식 명칭
  local_name    text,                         -- 현지(한국어) 표기
  names_i18n    jsonb not null default '{}',  -- {"en":"..","ja":".."}  공식 표기 대응표
  region        text,
  address_ko    text,
  segment       segment_t not null,
  theme         text not null,                -- 국내 8테마 / 방한 4테마 키
  sub_questions text[] not null default '{}', -- 보조 질문
  is_medical    boolean not null default false, -- 의료 관련 → 공개 차단 (44쪽)
  created_at    timestamptz not null default now()
);

-- ---------- 자산과 권리 (19쪽, 37쪽) ----------
create table assets (
  id                 uuid primary key default gen_random_uuid(),
  place_id           uuid references places(id),
  kind               asset_kind_t not null,
  source_type        asset_src_t not null,
  uri                text not null,                 -- 원본 위치 (스토리지 경로)
  captured_at        date,                          -- 촬영 시점
  room_type          text,                          -- 실제 제공 객실 유형
  provider_name      text,                          -- 제공 주체
  rights_status      rights_t not null default 'unverified',
  allowed_media      channel_t[] not null default '{}',
  allow_edit         boolean not null default false, -- 확대/재편집 허용
  allow_translate    boolean not null default false,
  allow_summary      boolean not null default false, -- 자막 요약 허용 (후기 자막)
  kogl_type          smallint,                       -- 공공누리 유형 (1~4)
  third_party_checked boolean not null default false,-- 인물·상표·작품 등 제삼자 권리 점검
  attribution_text   text,
  revoke_contact     text,                           -- 철회 연락 경로
  evidence_uri       text,                           -- 승인 화면·계약서 보관 위치
  approved_by        uuid references staff(id),
  approved_at        timestamptz,
  expires_at         timestamptz,
  note               text,
  created_at         timestamptz not null default now(),
  -- 승인 상태라면 승인자·증빙·철회경로·제삼자 점검이 반드시 있어야 한다
  constraint approved_needs_proof check (
    rights_status <> 'approved' or (
      approved_by is not null and approved_at is not null
      and evidence_uri is not null and revoke_contact is not null
      and third_party_checked
    )
  ),
  constraint kogl_needs_attribution check (
    kogl_type is null or attribution_text is not null
  )
);

-- 지금 이 순간 사용 가능한 자산인가 (만료 반영)
create or replace function asset_usable(a assets, ch channel_t default null)
returns boolean language sql stable as $$
  select a.rights_status = 'approved'
     and (a.expires_at is null or a.expires_at > now())
     and (ch is null or ch = any(a.allowed_media));
$$;

-- ---------- 근거 (17쪽) ----------
create table evidence (
  id             uuid primary key default gen_random_uuid(),
  place_id       uuid not null references places(id),
  kind           evidence_kind_t not null,
  source_url     text,                 -- 공식 안내 URL 또는 원문 영상 URL
  author         text,                 -- 발언 주체 (원작자)
  observed_at    date,                 -- 방문/공지 시점
  room_type      text,                 -- 해당 객실/이용 대상
  segment_start  integer,              -- 원문 구간(초)
  segment_end    integer,
  subtitle_asset uuid references assets(id),   -- 후기 근거라면 제공 자막
  excerpt        text,                 -- 대조용 메모 (원문 전재 금지, 내부용)
  status         verify_t not null default 'needs_check',
  checked_by     uuid references staff(id),
  checked_at     timestamptz,
  created_at     timestamptz not null default now(),
  -- 후기 근거는 사용 허락된 자막과 구간이 있어야 확인완료가 될 수 있다 (16쪽)
  constraint review_needs_subtitle check (
    kind <> 'review' or status <> 'verified' or (
      subtitle_asset is not null and segment_start is not null and author is not null
    )
  ),
  constraint verified_needs_checker check (
    status <> 'verified' or (checked_by is not null and checked_at is not null)
  )
);

-- ---------- 주장 ----------
create table claims (
  id          uuid primary key default gen_random_uuid(),
  place_id    uuid not null references places(id),
  lang        text not null default 'ko',
  kind        claim_kind_t not null,
  body        text not null,
  is_core     boolean not null default true,   -- 핵심 주장 → 근거 충족률 대상
  created_at  timestamptz not null default now()
);

create table claim_evidence (
  claim_id    uuid references claims(id) on delete cascade,
  evidence_id uuid references evidence(id),
  primary key (claim_id, evidence_id)
);

-- 주장이 공개 가능한가: 미확인 표시이거나, 확인완료 근거가 하나 이상
create or replace function claim_supported(c_id uuid)
returns boolean language sql stable as $$
  select c.kind = 'unverified' or exists (
    select 1 from claim_evidence ce join evidence e on e.id = ce.evidence_id
    where ce.claim_id = c.id and e.status = 'verified'
  ) from claims c where c.id = c_id;
$$;

-- ---------- 콘텐츠 작업 / 버전 (35~36쪽) ----------
create sequence job_no_seq start 1;
create table content_jobs (
  id           uuid primary key default gen_random_uuid(),
  job_no       text unique not null default ('TRP-' || lpad(nextval('trip.job_no_seq')::text, 5, '0')),
  place_id     uuid not null references places(id),
  question     text not null,             -- 이 콘텐츠가 답하는 고객 질문
  segment      segment_t not null,
  status       job_status_t not null default 'received',
  hold_reason  text,
  owner_id     uuid references staff(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table content_versions (
  id            uuid primary key default gen_random_uuid(),
  job_id        uuid not null references content_jobs(id) on delete cascade,
  version       integer not null,
  lang          text not null default 'ko',
  title         text not null,
  script        jsonb not null,               -- 장면표 [{scene, asset_id, narration, caption, claim_ids}]
  description   text,                         -- 설명문(질문·확인일·제휴여부·허브경로)
  sponsored     boolean not null default false,
  disclosure    text,                         -- 제휴/협찬 고지 문구
  partner_links jsonb not null default '[]',  -- [{label, operator, url}] 외부 예약 이동 (사업자 명시)
  prep_card     jsonb not null default '{}',  -- {before:[..], onsite:[..], official_contact:".."} 준비카드
  render_uri    text,
  render_sha256 text,
  made_by       uuid references staff(id),
  reviewed_by   uuid references staff(id),
  approved_by   uuid references staff(id),
  approved_at   timestamptz,
  created_at    timestamptz not null default now(),
  unique (job_id, version, lang),
  constraint sponsor_needs_disclosure check (not sponsored or disclosure is not null),
  -- 제작자와 승인자는 달라야 한다 (겸임 시 다른 확인자 지정, 41쪽)
  constraint maker_not_approver check (approved_by is null or made_by is null or approved_by <> made_by)
);

create table version_assets (
  version_id uuid references content_versions(id) on delete cascade,
  asset_id   uuid references assets(id),
  primary key (version_id, asset_id)
);
create table version_claims (
  version_id uuid references content_versions(id) on delete cascade,
  claim_id   uuid references claims(id),
  primary key (version_id, claim_id)
);

-- ---------- 상태 전이 (38쪽) ----------
create table job_transitions (
  id         bigserial primary key,
  job_id     uuid not null references content_jobs(id) on delete cascade,
  from_s     job_status_t,
  to_s       job_status_t not null,
  actor_id   uuid references staff(id),
  reason     text,
  at         timestamptz not null default now()
);

create table allowed_transitions (
  from_s job_status_t, to_s job_status_t, primary key (from_s, to_s)
);
insert into allowed_transitions values
  ('received','material_check'),
  ('material_check','ready'), ('material_check','held'),
  ('ready','rendering'), ('ready','held'),
  ('rendering','review'), ('rendering','ready'), ('rendering','held'),  -- 합성 실패 → 제작대기 복귀
  ('review','approved'), ('review','ready'), ('review','held'),          -- 반려 → 수정
  ('approved','published'), ('approved','held'), ('approved','ready'),
  ('published','held'), ('published','ready'),                           -- 정정 → 새 버전
  ('held','material_check'), ('held','ready');

-- 최신 버전
create or replace function latest_version(j uuid)
returns content_versions language sql stable as $$
  select * from content_versions where job_id = j order by version desc, created_at desc limit 1;
$$;

-- 공개 차단 사유를 모두 돌려준다 (빈 배열이면 통과)
create or replace function version_blockers(v_id uuid, ch channel_t default null)
returns text[] language plpgsql stable as $$
declare
  r text[] := '{}';
  v content_versions;
  p places;
  n int;
begin
  select * into v from content_versions where id = v_id;
  if v.id is null then return array['버전 없음']; end if;
  select p2.* into p from places p2 join content_jobs j on j.place_id = p2.id where j.id = v.job_id;

  if p.is_medical then r := r || '의료 관련 장소: 별도 검토 전 공개 금지'; end if;

  select count(*) into n from version_assets va join assets a on a.id = va.asset_id
   where va.version_id = v_id and not asset_usable(a, ch);
  if n > 0 then r := r || format('사용 불가 자산 %s건 (권리 미확인/철회/만료/매체 미허용)', n); end if;

  select count(*) into n from version_assets va where va.version_id = v_id;
  if n = 0 then r := r || '연결된 자산 없음'; end if;

  select count(*) into n from version_claims vc join claims c on c.id = vc.claim_id
   where vc.version_id = v_id and c.is_core and not claim_supported(c.id);
  if n > 0 then r := r || format('근거 미확인 핵심 주장 %s건', n); end if;

  select count(*) into n from version_claims vc where vc.version_id = v_id;
  if n = 0 then r := r || '연결된 주장(근거 카드) 없음'; end if;

  if v.sponsored and v.disclosure is null then r := r || '제휴 고지 누락'; end if;
  return r;
end $$;

-- 전이 검증 트리거
create or replace function trg_job_transition() returns trigger language plpgsql as $$
declare
  v content_versions;
  b text[];
begin
  if new.status = old.status then return new; end if;

  if not exists (select 1 from allowed_transitions where from_s = old.status and to_s = new.status) then
    raise exception '허용되지 않은 상태 전이: % → %', old.status, new.status;
  end if;

  if new.status = 'held' and coalesce(new.hold_reason, '') = '' then
    raise exception '보류에는 사유가 필요합니다';
  end if;

  if new.status in ('ready', 'review', 'approved', 'published') then
    v := latest_version(new.id);
  end if;

  -- 제작 대기 진입: 권리 확인된 자산이 있어야 함
  if new.status = 'ready' and v.id is not null then
    if exists (select 1 from version_assets va join assets a on a.id = va.asset_id
               where va.version_id = v.id and not asset_usable(a)) then
      raise exception '권리 미확인 자산이 있어 제작 대기로 넘길 수 없습니다';
    end if;
  end if;

  if new.status = 'review' and (v.id is null or v.render_uri is null) then
    raise exception '합성 결과(render_uri) 없이 검수로 넘길 수 없습니다';
  end if;

  if new.status = 'approved' then
    if v.id is null or v.approved_by is null or v.reviewed_by is null then
      raise exception '검수자·승인자 기록 없이 승인할 수 없습니다';
    end if;
    b := version_blockers(v.id);
    if array_length(b, 1) > 0 then
      raise exception '승인 차단: %', array_to_string(b, ' / ');
    end if;
  end if;

  if new.status = 'published' then
    b := version_blockers(v.id);
    if array_length(b, 1) > 0 then
      raise exception '공개 차단: %', array_to_string(b, ' / ');
    end if;
  end if;

  new.updated_at := now();
  insert into job_transitions(job_id, from_s, to_s, reason)
  values (new.id, old.status, new.status, new.hold_reason);
  return new;
end $$;

create trigger job_transition before update of status on content_jobs
for each row execute function trg_job_transition();

-- ---------- 공개 이력 (24쪽, 36쪽) ----------
create table publications (
  id           uuid primary key default gen_random_uuid(),
  version_id   uuid not null references content_versions(id),
  channel      channel_t not null,
  status       pub_status_t not null default 'queued',
  external_id  text,          -- 플랫폼 게시 식별자 (예: YouTube videoId)
  url          text,
  attempts     integer not null default 0,
  last_error   text,
  verified_by  uuid references staff(id),   -- 사람이 실제 공개 상태를 확인
  verified_at  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (version_id, channel)              -- 같은 버전의 같은 채널 중복 게시 방지
);

create or replace function trg_publication_guard() returns trigger language plpgsql as $$
declare
  j content_jobs; b text[];
begin
  -- 내리는 방향(수정필요·철회·실패 기록)은 언제나 허용
  if tg_op = 'UPDATE' and new.status in ('needs_fix', 'withdrawn', 'failed') then
    new.updated_at := now();
    return new;
  end if;
  select cj.* into j from content_jobs cj join content_versions v on v.job_id = cj.id where v.id = new.version_id;
  if j.status not in ('approved', 'published') then
    raise exception '승인되지 않은 작업(%: %)은 배포 대기에 넣을 수 없습니다', j.job_no, j.status;
  end if;
  b := version_blockers(new.version_id, new.channel);
  if array_length(b, 1) > 0 then
    raise exception '% 배포 차단: %', new.channel, array_to_string(b, ' / ');
  end if;
  if new.status = 'public' and (new.verified_by is null) then
    raise exception '실제 재생·링크 확인자(verified_by) 없이 public 처리할 수 없습니다';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger publication_guard before insert or update on publications
for each row execute function trg_publication_guard();

-- ---------- 정정·철회 (17쪽, 37쪽) ----------
create table corrections (
  id            uuid primary key default gen_random_uuid(),
  place_id      uuid references places(id),
  claim_id      uuid references claims(id),
  evidence_id   uuid references evidence(id),
  asset_id      uuid references assets(id),
  requester     text,               -- 원작자/숙소/이용자 (개인 연락처는 저장하지 않음)
  reason        text not null,
  proof_uri     text,
  status        correction_t not null default 'received',
  resolution    text,
  handled_by    uuid references staff(id),
  created_at    timestamptz not null default now(),
  closed_at     timestamptz
);

-- 근거·자산 변경의 영향 범위: 연결된 모든 작업/버전/게시물
create or replace view impact_map as
select 'asset'::text as source_type, a.id as source_id, j.job_no, j.id as job_id, v.id as version_id, v.lang, j.status
  from assets a join version_assets va on va.asset_id = a.id
  join content_versions v on v.id = va.version_id join content_jobs j on j.id = v.job_id
union all
select 'evidence', e.id, j.job_no, j.id, v.id, v.lang, j.status
  from evidence e join claim_evidence ce on ce.evidence_id = e.id
  join version_claims vc on vc.claim_id = ce.claim_id
  join content_versions v on v.id = vc.version_id join content_jobs j on j.id = v.job_id
union all
select 'claim', c.id, j.job_no, j.id, v.id, v.lang, j.status
  from claims c join version_claims vc on vc.claim_id = c.id
  join content_versions v on v.id = vc.version_id join content_jobs j on j.id = v.job_id;

-- 자산 철회·만료, 근거 보류 → 연결 작업 자동 보류 (빈 값을 승인으로 보정하지 않음)
create or replace function hold_impacted(src text, src_id uuid, why text) returns integer
language plpgsql as $$
declare n int := 0; r record;
begin
  for r in select distinct job_id from impact_map
           where source_type = src and source_id = src_id
             and status not in ('held', 'received', 'material_check')
  loop
    update content_jobs set status = 'held', hold_reason = why where id = r.job_id;
    update publications set status = 'needs_fix'
      where version_id in (select id from content_versions where job_id = r.job_id)
        and status in ('public', 'uploaded_private');
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function trg_asset_revoke() returns trigger language plpgsql as $$
begin
  if new.rights_status in ('revoked', 'expired') and old.rights_status = 'approved' then
    perform hold_impacted('asset', new.id, '자산 권리 ' || new.rights_status::text || ': ' || coalesce(new.note, ''));
  end if;
  return new;
end $$;
create trigger asset_revoke after update of rights_status on assets
for each row execute function trg_asset_revoke();

create or replace function trg_evidence_hold() returns trigger language plpgsql as $$
begin
  if new.status <> 'verified' and old.status = 'verified' then
    perform hold_impacted('evidence', new.id, '근거 상태 변경: ' || new.status::text);
  end if;
  return new;
end $$;
create trigger evidence_hold after update of status on evidence
for each row execute function trg_evidence_hold();

-- ---------- 이용 이벤트 (45쪽 지표용, 개인 식별정보 없음) ----------
create table hub_events (
  id          bigserial primary key,
  session_id  text not null,          -- 임시 식별자 (30분 비활동 시 새 세션)
  job_no      text,
  event       text not null check (event in ('hub_arrive','source_open','partner_click','card_save','share')),
  ref         text,                   -- 유입 경로 (yt/ig/search/direct)
  is_test     boolean not null default false,
  at          timestamptz not null default now()
);

-- ---------- 지표 뷰 (분모를 함께 노출) ----------
create or replace view metric_evidence_coverage as
select count(*) filter (where cardinality(version_blockers(v.id)) = 0) as numerator,
       count(*) as denominator
  from content_jobs j join lateral (select * from latest_version(j.id)) v on true
 where j.status = 'published';

create or replace view metric_source_open_rate as
with s as (
  select session_id, bool_or(event = 'source_open') as opened
    from hub_events where not is_test group by session_id
)
select count(*) filter (where opened) as numerator, count(*) as denominator from s;

-- ---------- 공개 허브용 읽기 뷰: 승인·공개된 것만 ----------
create or replace view public_hub as
select j.job_no, j.question, j.segment, p.slug, p.official_name, p.local_name, p.names_i18n,
       p.region, p.theme, p.sub_questions, v.lang, v.title, v.description, v.sponsored, v.disclosure,
       v.partner_links, v.prep_card, v.approved_at as checked_at, v.id as version_id,
       (select pb.url from publications pb where pb.version_id = v.id and pb.channel = 'youtube'
          and pb.status = 'public' limit 1) as youtube_url
  from content_jobs j
  join places p on p.id = j.place_id
  join lateral (select * from latest_version(j.id)) v on true
 where j.status = 'published' and not p.is_medical;

create or replace view public_cards as
select v.id as version_id, c.id as claim_id, c.kind as claim_kind, c.body,
       e.kind as evidence_kind, e.source_url, e.author, e.observed_at, e.room_type,
       e.segment_start, e.segment_end, e.status as evidence_status
  from public_hub h
  join content_versions v on v.id = h.version_id
  join version_claims vc on vc.version_id = v.id
  join claims c on c.id = vc.claim_id
  left join claim_evidence ce on ce.claim_id = c.id
  left join evidence e on e.id = ce.evidence_id and e.status = 'verified';

-- ---------- 모든 함수의 search_path 고정 (외부 클라이언트·PostgREST에서 호출해도 안전) ----------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'trip'
  loop
    execute format('alter function %s set search_path = trip, public', f.sig);
  end loop;
end $$;
