-- 규칙 검증 시나리오: 실패해야 할 것은 실패하고, 통과해야 할 것은 통과하는지 확인
-- 실행: psql -v ON_ERROR_STOP=0 -f test_rules.sql   (각 블록이 OK/FAIL을 출력)
set search_path = trip, public;
\set QUIET on

create or replace function pg_temp.expect_error(sql text, label text) returns void language plpgsql as $$
begin
  execute sql;
  raise notice 'FAIL  % (오류가 나야 하는데 통과함)', label;
exception when others then
  raise notice 'OK    % → %', label, sqlerrm;
end $$;

create or replace function pg_temp.expect_ok(sql text, label text) returns void language plpgsql as $$
begin
  execute sql;
  raise notice 'OK    %', label;
exception when others then
  raise notice 'FAIL  % → %', label, sqlerrm;
end $$;

-- 고정 ID로 데모 데이터
insert into staff(id, name, roles) values
 ('00000000-0000-0000-0000-000000000001','편집 담당','{editor}'),
 ('00000000-0000-0000-0000-000000000002','제품 책임','{product}'),
 ('00000000-0000-0000-0000-000000000003','운영 담당','{ops}');

insert into places(id, slug, official_name, local_name, names_i18n, region, segment, theme, sub_questions)
values ('10000000-0000-0000-0000-000000000001','demo-family-stay','[예시] 가족형 리조트 A','예시 리조트 A',
        '{"en":"[Sample] Family Resort A"}','강원','domestic_kr','family','{침구 구성,공용시설 이용조건}');

-- 사진 2장: 하나는 승인, 하나는 미확인
insert into assets(id, place_id, kind, source_type, uri, rights_status)
values ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','photo','provider','demo/a1.jpg','unverified');

select pg_temp.expect_error($$update trip.assets set rights_status='approved' where id='20000000-0000-0000-0000-000000000001'$$,
  '증빙·철회경로 없이 자산 승인 불가');

update assets set rights_status='approved', approved_by='00000000-0000-0000-0000-000000000001', approved_at=now(),
  evidence_uri='contracts/demo-a.pdf', revoke_contact='숙소 마케팅 담당 창구', third_party_checked=true,
  allowed_media='{youtube,hub}', allow_edit=true
 where id='20000000-0000-0000-0000-000000000001';

insert into assets(id, place_id, kind, source_type, uri, rights_status)
values ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','photo','provider','demo/a2.jpg','unverified');

-- 근거
insert into evidence(id, place_id, kind, source_url, observed_at, status)
values ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','official','https://example.com/notice','2026-10-01','needs_check');

select pg_temp.expect_error($$insert into trip.evidence(place_id, kind, author, status, checked_by, checked_at)
  values ('10000000-0000-0000-0000-000000000001','review','리뷰어X','verified','00000000-0000-0000-0000-000000000001',now())$$,
  '자막·구간 없는 후기 근거는 확인완료 불가');

insert into claims(id, place_id, kind, body) values
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','fact','패밀리 객실은 더블 1 + 싱글 2 구성으로 공지되어 있다'),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','unverified','실내 수영장 이용이 객실 요금에 포함되는지는 확인되지 않았다');
insert into claim_evidence values ('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001');

-- 작업과 버전
insert into content_jobs(id, place_id, question, segment)
values ('50000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
        '아이 둘과 묵을 때 침구가 충분한가?','domestic_kr');

insert into content_versions(id, job_id, version, title, script, made_by)
values ('60000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001',1,
        '아이 둘 가족, 이 객실 침구로 충분할까?','[]','00000000-0000-0000-0000-000000000001');
insert into version_assets values ('60000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001'),
                                  ('60000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002');
insert into version_claims values ('60000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001'),
                                  ('60000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002');

select pg_temp.expect_error($$update trip.content_jobs set status='approved' where id='50000000-0000-0000-0000-000000000001'$$,
  '접수 → 승인 직행 불가');
select pg_temp.expect_ok($$update trip.content_jobs set status='material_check' where id='50000000-0000-0000-0000-000000000001'$$,
  '접수 → 자료 확인');
select pg_temp.expect_error($$update trip.content_jobs set status='ready' where id='50000000-0000-0000-0000-000000000001'$$,
  '권리 미확인 사진이 섞이면 제작 대기 불가');

-- 미확인 사진 제거 후 진행
delete from version_assets where asset_id='20000000-0000-0000-0000-000000000002';
select pg_temp.expect_ok($$update trip.content_jobs set status='ready' where id='50000000-0000-0000-0000-000000000001'$$,
  '승인 자산만 남기면 제작 대기');
select pg_temp.expect_ok($$update trip.content_jobs set status='rendering' where id='50000000-0000-0000-0000-000000000001'$$, '합성 시작');
select pg_temp.expect_error($$update trip.content_jobs set status='review' where id='50000000-0000-0000-0000-000000000001'$$,
  '합성 파일 없이 검수 불가');
update content_versions set render_uri='renders/TRP-00001_v1.mp4', reviewed_by='00000000-0000-0000-0000-000000000003'
 where id='60000000-0000-0000-0000-000000000001';
select pg_temp.expect_ok($$update trip.content_jobs set status='review' where id='50000000-0000-0000-0000-000000000001'$$, '검수 진입');

select pg_temp.expect_error($$update trip.content_versions set approved_by='00000000-0000-0000-0000-000000000001', approved_at=now()
  where id='60000000-0000-0000-0000-000000000001'$$, '제작자 본인 승인 불가');
update content_versions set approved_by='00000000-0000-0000-0000-000000000002', approved_at=now()
 where id='60000000-0000-0000-0000-000000000001';

select pg_temp.expect_error($$update trip.content_jobs set status='approved' where id='50000000-0000-0000-0000-000000000001'$$,
  '근거가 확인 전(needs_check)이면 승인 차단');
update evidence set status='verified', checked_by='00000000-0000-0000-0000-000000000001', checked_at=now()
 where id='30000000-0000-0000-0000-000000000001';
select pg_temp.expect_ok($$update trip.content_jobs set status='approved' where id='50000000-0000-0000-0000-000000000001'$$,
  '근거 확인 후 승인');

select pg_temp.expect_error($$insert into trip.publications(version_id, channel) values ('60000000-0000-0000-0000-000000000001','instagram')$$,
  '허용 매체가 아닌 채널(instagram) 배포 차단');
select pg_temp.expect_ok($$insert into trip.publications(version_id, channel) values ('60000000-0000-0000-0000-000000000001','youtube')$$,
  '유튜브 배포 대기 등록');
select pg_temp.expect_error($$insert into trip.publications(version_id, channel) values ('60000000-0000-0000-0000-000000000001','youtube')$$,
  '같은 버전 중복 게시 차단');
select pg_temp.expect_error($$update trip.publications set status='public' where version_id='60000000-0000-0000-0000-000000000001'$$,
  '사람 확인 없이 public 처리 불가');
select pg_temp.expect_ok($$update trip.content_jobs set status='published' where id='50000000-0000-0000-0000-000000000001'$$, '공개');

select pg_temp.expect_ok($$select 1 from trip.public_hub where job_no='TRP-00001'$$, '공개 허브 뷰 노출');

update publications set status='uploaded_private', external_id='demoVideoId'
 where version_id='60000000-0000-0000-0000-000000000001';
-- 철회 시 자동 보류
update assets set rights_status='revoked', note='숙소 요청으로 철회' where id='20000000-0000-0000-0000-000000000001';
do $$ declare s text; begin
  select status into s from trip.content_jobs where id='50000000-0000-0000-0000-000000000001';
  if s='held' then raise notice 'OK    자산 철회 → 연결 작업 자동 보류'; else raise notice 'FAIL  철회 후 상태=%', s; end if;
  if exists(select 1 from trip.public_hub where job_no='TRP-00001') then raise notice 'FAIL  보류 후에도 허브에 노출';
  else raise notice 'OK    보류 즉시 공개 허브에서 제외'; end if;
  select status into s from trip.publications where version_id='60000000-0000-0000-0000-000000000001';
  if s='needs_fix' then raise notice 'OK    업로드된 게시물 → 수정 필요 표시'; else raise notice 'FAIL  게시물 상태=%', s; end if;
end $$;

select 'transitions' as log, from_s, to_s, reason from job_transitions order by id;
