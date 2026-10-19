-- 편집 콘솔 함수 검증 (test_rules → test_portal 다음, 같은 DB)
set search_path = trip, public;

create or replace function pg_temp.expect_error(sql text, label text) returns void language plpgsql as $$
begin execute sql; raise notice 'FAIL  % (통과해 버림)', label;
exception when others then raise notice 'OK    % → %', label, left(sqlerrm, 100); end $$;
create or replace function pg_temp.expect_ok(sql text, label text) returns void language plpgsql as $$
begin execute sql; raise notice 'OK    %', label;
exception when others then raise notice 'FAIL  % → %', label, sqlerrm; end $$;

select pg_temp.expect_error($$select trip.console_set_job_status('TRP-00001','material_check', null)$$, '콘솔: 행동한 사람 없이 상태 변경 불가');
select pg_temp.expect_error($$select trip.console_set_job_status('TRP-00001','review','00000000-0000-0000-0000-000000000002')$$, '콘솔: 허용되지 않은 전이는 DB가 거부');

-- test_portal 끝에서 TRP-00001 은 v2 승인(approved) 상태. 보류로 내리고 사유·행동자 기록 확인
select pg_temp.expect_ok($$select trip.console_set_job_status('TRP-00001','held','00000000-0000-0000-0000-000000000003','숙소 요청으로 사진 교체 대기')$$, '콘솔: 공개 작업 보류');
do $$ declare a uuid; r text; begin
  select actor_id, reason into a, r from trip.job_transitions order by id desc limit 1;
  if a = '00000000-0000-0000-0000-000000000003' and r like '숙소 요청%' then raise notice 'OK    콘솔: 상태 전이에 행동자·사유 기록';
  else raise notice 'FAIL  actor=% reason=%', a, r; end if;
end $$;

do $$ declare n int; b text[]; begin
  select count(*), max(blockers) into n, b from trip.console_jobs where job_no='TRP-00001' and status='held';
  if n = 1 then raise notice 'OK    콘솔 작업 목록: 상태·다음 가능 상태·차단 사유 계산'; else raise notice 'FAIL  console_jobs %', n; end if;
end $$;

-- 피드 승인 대기 (test_portal 의 자동 등록 후보 ytNEW1)
do $$ declare i uuid; s text; begin
  select id into i from trip.media_items where external_id='ytNEW1';
  perform trip.console_feed_action(i, 'approve', '00000000-0000-0000-0000-000000000002');
  select status into s from trip.media_items where id=i;
  if s='approved' and exists(select 1 from trip.console_audit where action='feed_approve' and target=i::text)
  then raise notice 'OK    콘솔: 피드 후보 승인 + 행동 기록'; else raise notice 'FAIL  피드 승인 %', s; end if;
end $$;

do $$ declare n int; begin
  select jobs into n from trip.console_summary;
  if n >= 1 then raise notice 'OK    콘솔 요약 집계'; else raise notice 'FAIL  요약'; end if;
end $$;

-- 익명 사용자는 콘솔 뷰를 읽을 수 없어야 함
set role anon;
select pg_temp.expect_error($$select * from trip.console_jobs$$, '익명 사용자는 콘솔 작업 목록 접근 불가');
select pg_temp.expect_error($$select trip.console_feed_action(gen_random_uuid(),'approve','00000000-0000-0000-0000-000000000002')$$, '익명 사용자는 콘솔 행동 함수 실행 불가');
reset role;
