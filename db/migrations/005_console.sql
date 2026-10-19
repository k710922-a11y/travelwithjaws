-- =====================================================================
-- 편집 콘솔 (내부용): 읽기 뷰 + 행동 함수
-- 콘솔은 서버에서 service_role 로만 접속한다. 모든 행동은 누가 했는지 기록한다.
-- =====================================================================
set search_path = trip, public;

-- 상태 전이 기록에 행동한 사람을 남긴다 (콘솔 함수가 trip.actor 를 설정)
create or replace function current_actor() returns uuid language sql stable as $$
  select nullif(current_setting('trip.actor', true), '')::uuid;
$$;

create or replace function trg_job_transition_actor() returns trigger language plpgsql as $$
begin
  update job_transitions set actor_id = current_actor()
   where id = (select max(id) from job_transitions where job_id = new.id) and actor_id is null;
  return new;
end $$;
create trigger job_transition_actor after update of status on content_jobs
for each row when (old.status is distinct from new.status) execute function trg_job_transition_actor();

-- 콘솔 행동 기록 (피드 승인·숨김, 설정 변경 등 상태 전이 밖의 행동)
create table console_audit (
  id         bigserial primary key,
  actor_id   uuid references staff(id),
  action     text not null,
  target     text not null,
  detail     jsonb not null default '{}',
  at         timestamptz not null default now()
);

-- ---------- 읽기 뷰 ----------
create or replace view console_jobs as
select j.id, j.job_no, j.question, j.segment, j.status, j.hold_reason, j.question_type, j.updated_at,
       p.official_name as place, p.region, p.theme,
       v.id as version_id, v.version, v.title, v.render_uri, v.sponsored,
       mk.name as made_by, rv.name as reviewed_by, ap.name as approved_by,
       case when v.id is null then array['버전 없음'] else version_blockers(v.id) end as blockers,
       (select pb.status::text from publications pb where pb.version_id = v.id and pb.channel = 'youtube') as youtube_status,
       (select pb.url from publications pb where pb.version_id = v.id and pb.channel = 'youtube') as youtube_url,
       array(select a.to_s::text from allowed_transitions a where a.from_s = j.status order by a.to_s) as next_statuses
  from content_jobs j
  join places p on p.id = j.place_id
  left join lateral (select * from latest_version(j.id)) v on v.id is not null
  left join staff mk on mk.id = v.made_by
  left join staff rv on rv.id = v.reviewed_by
  left join staff ap on ap.id = v.approved_by;

create or replace view console_feed_queue as
select i.id, i.title, i.status, i.published_at, i.url, s.platform, s.display_name as creator, s.agreement,
       s.summary_allowed or s.is_own as summary_allowed, i.summary, i.summary_status, i.sponsored, i.disclosure,
       i.place_label, i.region, i.theme, i.sea_city, i.created_at
  from media_items i join media_sources s on s.id = i.source_id
 where i.status in ('candidate', 'approved', 'hidden');

create or replace view console_longform as
select lp.id, lp.code, lp.title, lp.format, lp.bundle_type, lp.bundle_key, lp.status, lp.hold_reason, lp.youtube_id,
       (select count(*) from longform_chapters c where c.project_id = lp.id) as chapters,
       longform_blockers(lp.id) as blockers, lp.created_at
  from longform_projects lp;

create or replace view console_summary as
select
  (select count(*) from content_jobs) as jobs,
  (select count(*) from content_jobs where status = 'review') as in_review,
  (select count(*) from content_jobs where status = 'held') as held,
  (select count(*) from content_jobs where status = 'published') as published,
  (select count(*) from media_items where status = 'candidate') as feed_candidates,
  (select count(*) from corrections where status in ('received', 'investigating')) as open_corrections,
  (select count(*) from shorts_pool) as public_shorts,
  (select min_channel_shorts from longform_settings) as longform_threshold,
  (select count(*) from longform_candidates where ready) as longform_ready;

-- ---------- 행동 함수 ----------
create or replace function console_set_job_status(p_job_no text, p_to text, p_actor uuid, p_reason text default null)
returns text language plpgsql as $$
begin
  if p_actor is null then raise exception '행동한 사람(staff)이 필요합니다'; end if;
  perform set_config('trip.actor', p_actor::text, true);
  update content_jobs set status = p_to::job_status_t,
         hold_reason = case when p_to = 'held' then p_reason else hold_reason end
   where job_no = p_job_no;
  if not found then raise exception '작업 % 없음', p_job_no; end if;
  return p_to;
end $$;

create or replace function console_feed_action(p_item uuid, p_action text, p_actor uuid)
returns text language plpgsql as $$
begin
  if p_actor is null then raise exception '행동한 사람(staff)이 필요합니다'; end if;
  if p_action = 'approve' then
    update media_items set status = 'approved', approved_by = p_actor, approved_at = now() where id = p_item;
  elsif p_action = 'hide' then
    update media_items set status = 'hidden' where id = p_item;
  elsif p_action = 'verify_summary' then
    update media_items set summary_status = 'verified' where id = p_item;
  else
    raise exception '알 수 없는 행동 %', p_action;
  end if;
  if not found then raise exception '아이템 없음'; end if;
  insert into console_audit(actor_id, action, target) values (p_actor, 'feed_' || p_action, p_item::text);
  return p_action;
end $$;

create or replace function console_close_correction(p_id uuid, p_status text, p_resolution text, p_actor uuid)
returns text language plpgsql as $$
begin
  if p_status not in ('investigating', 'fixed', 'rejected') then raise exception '상태 % 불가', p_status; end if;
  update corrections set status = p_status::correction_t, resolution = p_resolution, handled_by = p_actor,
         closed_at = case when p_status in ('fixed', 'rejected') then now() end
   where id = p_id;
  insert into console_audit(actor_id, action, target, detail) values (p_actor, 'correction_' || p_status, p_id::text, jsonb_build_object('resolution', p_resolution));
  return p_status;
end $$;

-- 권한: 콘솔 뷰와 함수는 service_role 만
revoke all on trip.console_jobs, trip.console_feed_queue, trip.console_longform, trip.console_summary, trip.console_audit from anon, authenticated;
grant select on trip.console_jobs, trip.console_feed_queue, trip.console_longform, trip.console_summary, trip.longform_candidates, trip.corrections, trip.staff, trip.longform_settings to service_role;
grant all on trip.console_audit to service_role;
grant usage on sequence trip.console_audit_id_seq to service_role;
revoke execute on function trip.console_set_job_status(text, text, uuid, text), trip.console_feed_action(uuid, text, uuid),
  trip.console_close_correction(uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function trip.console_set_job_status(text, text, uuid, text), trip.console_feed_action(uuid, text, uuid),
  trip.console_close_correction(uuid, text, text, uuid) to service_role;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'trip'
  loop execute format('alter function %s set search_path = trip, public', f.sig); end loop;
end $$;
