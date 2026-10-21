-- 예시 데이터 규칙 검증 (test_rules → test_portal → test_console 다음, 같은 DB에서 실행)
-- 예시도 실제 규칙을 거쳐 공개되고, 공개 뷰에 is_demo 표시가 붙으며, 지울 때 실제 데이터는 남는지
set search_path = trip, public;

create or replace function pg_temp.expect_ok(sql text, label text) returns void language plpgsql as $$
begin execute sql; raise notice 'OK    %', label;
exception when others then raise notice 'FAIL  % → %', label, sqlerrm; end $$;

create temp table before_real as
select (select count(*) from places where not is_demo) as places,
       (select count(*) from media_items i join media_sources s on s.id = i.source_id where not s.is_demo) as items,
       (select count(*) from content_jobs j join places p on p.id = j.place_id where not p.is_demo) as jobs,
       (select count(*) from staff where not is_demo) as staff;

select pg_temp.expect_ok($$select trip.load_demo()$$, '예시 데이터 넣기 (실제 절차로 승인·공개)');

do $$ declare n int; m int; begin
  select count(*), count(*) filter (where is_demo) into n, m from trip.public_feed where creator <> '편집팀 판단 문서' and id in
    (select i.id from trip.media_items i join trip.media_sources s on s.id = i.source_id where s.is_demo);
  if n >= 25 and n = m then raise notice 'OK    예시 피드 %건 공개, 모두 is_demo 표시', n; else raise notice 'FAIL  예시 피드 %건 / 표시 %건', n, m; end if;

  select count(*) into n from trip.public_hub where job_no like 'DEMO-%' and is_demo;
  if n = 4 then raise notice 'OK    예시 판단 문서 4건 공개, is_demo 표시'; else raise notice 'FAIL  예시 판단 문서 %건', n; end if;

  select count(*) into n from trip.public_feed where is_demo and summary is null and summary_reason is not null;
  if n >= 3 then raise notice 'OK    협약 없는 예시 출처는 제목만 (요약 미제공 사유 %건)', n; else raise notice 'FAIL  요약 미제공 %건', n; end if;

  select count(*) into n from trip.console_jobs where job_no in ('DEMO-05','DEMO-06','DEMO-07') and status in ('review','held','received');
  if n = 3 then raise notice 'OK    진행 중 예시 작업 3건 (검수·보류·접수) 콘솔에 표시'; else raise notice 'FAIL  진행 중 작업 %건', n; end if;

  select count(*) into n from trip.public_collections where is_demo and cardinality(item_ids) >= 5;
  if n = 5 then raise notice 'OK    예시 컬렉션 5개 (판단 문서 포함)'; else raise notice 'FAIL  예시 컬렉션 %개', n; end if;

  select count(*) into n from trip.public_feed where not is_demo;
  if n >= 1 then raise notice 'OK    실제 데이터는 is_demo=false 로 함께 노출'; else raise notice 'FAIL  실제 데이터 표시 %건', n; end if;
end $$;

-- 익명 사용자(anon)로 공개 뷰를 읽을 수 있는지 (공개 문서가 있을 때)
do $$ declare a int; b int; c int; begin
  set local role anon;
  select count(*) into a from trip.public_hub;
  select count(*) into b from trip.public_feed;
  select count(*) into c from trip.public_cards;
  perform 1 from trip.public_hero; perform 1 from trip.public_hub_photo;
  reset role;
  if a >= 4 and b >= 30 and c >= 10 then raise notice 'OK    익명 사용자로 공개 뷰 읽기 (문서 %·피드 %·카드 %)', a, b, c;
  else raise notice 'FAIL  익명 읽기 결과 % / % / %', a, b, c; end if;
exception when others then raise notice 'FAIL  익명 사용자 공개 뷰 읽기 → %', sqlerrm;
end $$;

-- 실제 사진: 예시 피드·판단 문서 모두 승인된 사진 + 크레딧
do $$ declare n int; d int; c int; begin
  select count(*) filter (where thumbnail_uri like 'https://images.unsplash.com/%' and platform <> 'hub_doc'),
         count(*) filter (where thumbnail_uri is not null and platform = 'hub_doc'),
         count(*) filter (where thumbnail_uri is not null and thumbnail_credit like 'Photo: %')
    into n, d, c from trip.public_feed where is_demo;
  if n >= 29 and d = 4 and c = n + d then raise notice 'OK    예시 카드 사진 %장·판단 문서 사진 %장, 모두 크레딧 표시', n, d;
  else raise notice 'FAIL  사진 피드 % / 문서 % / 크레딧 %', n, d, c; end if;
end $$;
do $$ declare aid uuid; s text; begin
  select i.thumbnail_asset into aid from trip.media_items i join trip.media_sources s on s.id = i.source_id
   where s.is_demo and i.thumbnail_asset is not null limit 1;
  update trip.assets set rights_status = 'revoked' where trip.assets.id = aid;
  select i.thumbnail_asset::text into s from trip.media_items i where i.thumbnail_asset = aid;
  if s is null then raise notice 'OK    사진 권리 철회 → 카드에서 사진만 내려감 (일러스트로 대체)'; else raise notice 'FAIL  철회된 사진이 카드에 남음'; end if;
end $$;

-- 두 번 넣어도 같은 결과
do $$ declare a int; b int; begin
  select count(*) into a from trip.public_feed where is_demo;
  perform trip.load_demo();
  select count(*) into b from trip.public_feed where is_demo;
  if a = b then raise notice 'OK    다시 넣어도 중복 없음 (%건)', b; else raise notice 'FAIL  % → %건', a, b; end if;
end $$;

-- 지우기: 예시만 사라지고 실제 데이터는 그대로
select pg_temp.expect_ok($$select trip.remove_demo()$$, '예시 데이터 지우기');
do $$ declare r record; n int; begin
  select count(*) into n from (
    select 1 from trip.places where is_demo union all select 1 from trip.media_sources where is_demo
    union all select 1 from trip.collections where is_demo union all select 1 from trip.staff where is_demo
    union all select 1 from trip.public_feed where is_demo) x;
  select n + count(*) into n from trip.assets where note = 'demo-photo';
  if n = 0 then raise notice 'OK    예시 데이터 모두 삭제'; else raise notice 'FAIL  예시 %건 남음', n; end if;
  select b.* into r from before_real b;
  if r.places = (select count(*) from trip.places) and r.staff = (select count(*) from trip.staff)
     and r.jobs = (select count(*) from trip.content_jobs)
     and r.items = (select count(*) from trip.media_items) then raise notice 'OK    실제 데이터는 그대로';
  else raise notice 'FAIL  실제 데이터가 바뀜'; end if;
end $$;

do $$ begin
  if not has_function_privilege('anon', 'trip.load_demo()', 'execute') and not has_function_privilege('anon', 'trip.remove_demo()', 'execute')
     and has_function_privilege('service_role', 'trip.load_demo()', 'execute') then
    raise notice 'OK    예시 넣기·지우기는 service_role 전용';
  else raise notice 'FAIL  익명 사용자가 예시 넣기·지우기 가능'; end if;
end $$;
