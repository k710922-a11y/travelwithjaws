-- 포털 규칙 검증 (test_rules.sql 실행 직후, 같은 DB에서 실행)
set search_path = trip, public;

create or replace function pg_temp.expect_error(sql text, label text) returns void language plpgsql as $$
begin execute sql; raise notice 'FAIL  % (통과해 버림)', label;
exception when others then raise notice 'OK    % → %', label, sqlerrm; end $$;
create or replace function pg_temp.expect_ok(sql text, label text) returns void language plpgsql as $$
begin execute sql; raise notice 'OK    %', label;
exception when others then raise notice 'FAIL  % → %', label, sqlerrm; end $$;

select pg_temp.expect_error($$insert into trip.media_sources(platform, handle, display_name, summary_allowed)
  values ('blog','no-deal','협약 없는 블로그', true)$$, '협약 없이 요약 허락 불가');
select pg_temp.expect_error($$insert into trip.media_sources(platform, handle, display_name, agreement)
  values ('blog','no-proof','증빙 없는 협약', 'agreed')$$, '협약서·철회창구 없이 협약 상태 불가');

insert into media_sources(id, platform, handle, display_name, agreement, summary_allowed, agreement_uri, revoke_contact) values
 ('70000000-0000-0000-0000-000000000001','ig_reels','@예시_도시여행자','@예시_도시여행자','agreed',true,'agreements/ig-001.pdf','DM 및 이메일 창구'),
 ('70000000-0000-0000-0000-000000000002','yt_shorts','@예시_서울야경','@예시_서울야경','none',false,null,null);
insert into media_sources(id, platform, handle, display_name, is_own) values
 ('70000000-0000-0000-0000-000000000009','yt_shorts','@our_channel','자사 쇼츠 채널',true);

insert into media_items(id, source_id, external_id, url, title, published_at, segment, theme, sea_city, summary, summary_status, evidence_kind)
values ('80000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','r1','https://example.com/r1',
        '해변열차 창가 자리', '2026-10-18','domestic_kr','family',-35,'진행 방향에 따라 바다 쪽 좌석이 바뀐다는 설명','verified','review');

select pg_temp.expect_error($$insert into trip.media_items(source_id, external_id, url, title, published_at, segment, theme, summary, summary_status)
  values ('70000000-0000-0000-0000-000000000002','s1','https://example.com/s1','한강 노을','2026-10-17','domestic_kr','youth_mood','요약 시도','verified')$$,
  '요약 허락 없는 출처의 요약 확인완료 불가');
insert into media_items(id, source_id, external_id, url, title, published_at, segment, theme, sea_city)
values ('80000000-0000-0000-0000-000000000002','70000000-0000-0000-0000-000000000002','s1','https://example.com/s1','한강 노을','2026-10-17','domestic_kr','youth_mood',70);

select pg_temp.expect_error($$update trip.media_items set status='approved' where id='80000000-0000-0000-0000-000000000001'$$, '승인자 없이 승인 불가');
update media_items set status='approved', approved_by='00000000-0000-0000-0000-000000000002', approved_at=now();

select pg_temp.expect_error($$update trip.media_items set thumbnail_asset='20000000-0000-0000-0000-000000000002' where id='80000000-0000-0000-0000-000000000001'$$,
  '권리 미확인 썸네일 연결 불가');
select pg_temp.expect_error($$update trip.media_items set sponsored=true where id='80000000-0000-0000-0000-000000000001'$$, '제휴 표시 문구 없이 협찬 불가');

do $$ declare s text; r text; begin
  select summary, summary_reason into s, r from trip.public_feed where id='80000000-0000-0000-0000-000000000002';
  if s is null and r is not null then raise notice 'OK    요약 미허락 콘텐츠는 제목만, 요약 미제공 사유 노출'; else raise notice 'FAIL  요약 노출됨'; end if;
  select summary into s from trip.public_feed where id='80000000-0000-0000-0000-000000000001';
  if s is not null then raise notice 'OK    협약 출처의 확인된 요약 노출'; else raise notice 'FAIL  요약 누락'; end if;
end $$;

insert into collections(id, slug, title, mood, status) values ('90000000-0000-0000-0000-000000000001','busan-48h','부산 48시간','mix','published');
insert into collection_items values ('90000000-0000-0000-0000-000000000001','80000000-0000-0000-0000-000000000001',1,null),
                                    ('90000000-0000-0000-0000-000000000001','80000000-0000-0000-0000-000000000002',2,null);

-- 요약 허락 철회 → 요약 즉시 내려감
update media_sources set summary_allowed=false where id='70000000-0000-0000-0000-000000000001';
do $$ declare s text; begin
  select summary into s from trip.public_feed where id='80000000-0000-0000-0000-000000000001';
  if s is null then raise notice 'OK    요약 허락 철회 → 피드 요약 즉시 제외'; else raise notice 'FAIL  철회 후에도 요약 노출'; end if;
end $$;

-- 협약 종료 → 아이템 숨김, 컬렉션에서도 빠짐
update media_sources set agreement='ended' where id='70000000-0000-0000-0000-000000000001';
do $$ declare n int; begin
  select cardinality(item_ids) into n from trip.public_collections where slug='busan-48h';
  if n = 1 then raise notice 'OK    협약 종료 → 피드·컬렉션에서 제외 (남은 1개)'; else raise notice 'FAIL  컬렉션 개수=%', n; end if;
end $$;

-- 의료 장소 차단
update places set is_medical=true where id='10000000-0000-0000-0000-000000000001';
select pg_temp.expect_error($$insert into trip.media_items(source_id, external_id, url, title, published_at, segment, theme, place_id, status, approved_by, approved_at)
  values ('70000000-0000-0000-0000-000000000002','med1','https://example.com/m','시술 후기','2026-10-10','inbound','beauty',
          '10000000-0000-0000-0000-000000000001','approved','00000000-0000-0000-0000-000000000002',now())$$, '의료 관련 장소 콘텐츠 승인 차단');
update places set is_medical=false where id='10000000-0000-0000-0000-000000000001';

-- 자사 쇼츠 공개 → 피드 후보 자동 등록
do $$ declare n int; v uuid; begin
  -- test_rules 이후 작업은 보류 상태 → 새 버전으로 다시 승인·공개 흐름을 태운다
  update trip.assets set rights_status='approved', note=null where id='20000000-0000-0000-0000-000000000001';
  insert into trip.content_versions(id, job_id, version, title, script, made_by, reviewed_by, approved_by, approved_at, render_uri, description)
  values ('60000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000001',2,'아이 둘 가족 침구 (v2)','[]',
          '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002',now(),'r.mp4','침구 구성 정리');
  insert into trip.version_assets values ('60000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001');
  insert into trip.version_claims values ('60000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000001');
  update trip.content_jobs set status='ready', hold_reason=null where id='50000000-0000-0000-0000-000000000001';
  update trip.content_jobs set status='rendering' where id='50000000-0000-0000-0000-000000000001';
  update trip.content_jobs set status='review' where id='50000000-0000-0000-0000-000000000001';
  update trip.content_jobs set status='approved' where id='50000000-0000-0000-0000-000000000001';
  insert into trip.publications(version_id, channel, status, external_id) values ('60000000-0000-0000-0000-000000000002','youtube','uploaded_private','ytNEW1');
  update trip.publications set status='public', verified_by='00000000-0000-0000-0000-000000000003', verified_at=now()
   where version_id='60000000-0000-0000-0000-000000000002';
  select count(*) into n from trip.media_items where external_id='ytNEW1' and status='candidate';
  if n = 1 then raise notice 'OK    자사 쇼츠 공개 → 피드 후보 자동 등록 (편집 승인 대기)'; else raise notice 'FAIL  자동 등록 %건', n; end if;
end $$;
