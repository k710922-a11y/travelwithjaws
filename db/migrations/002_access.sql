-- 공개 허브 접근 권한 (셀프호스팅 Supabase의 anon / authenticated / service_role 기준)
-- 원칙: 익명 사용자는 '공개 뷰'만 읽고, 이용 이벤트만 기록할 수 있다.
set search_path = trip, public;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;

revoke all on all tables in schema trip from anon, authenticated;
grant usage on schema trip to anon, authenticated, service_role;

-- 익명: 공개 뷰 읽기 + 이벤트 기록
grant select on trip.public_hub, trip.public_cards to anon, authenticated;
grant insert on trip.hub_events to anon, authenticated;
grant usage on sequence trip.hub_events_id_seq to anon, authenticated;

-- 내부 운영(서비스 키): 전체
grant all on all tables in schema trip to service_role;
grant all on all sequences in schema trip to service_role;
grant execute on all functions in schema trip to service_role;

-- 행 단위 보안: 원본 테이블은 anon에 노출되지 않음 (뷰는 소유자 권한으로 승인분만 노출)
alter table trip.hub_events enable row level security;
create policy hub_events_insert on trip.hub_events for insert to anon, authenticated
  with check (event in ('hub_arrive','source_open','partner_click','card_save','share') and not is_test);
create policy hub_events_service on trip.hub_events for all to service_role using (true) with check (true);

-- PostgREST에 trip 스키마 노출: Supabase Studio > Settings > API > Exposed schemas 에 'trip' 추가
-- (셀프호스팅 docker-compose 의 PGRST_DB_SCHEMAS 에 trip 추가)
