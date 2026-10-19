-- 롱폼 묶음 기준 검증 (001~004 적용된 빈 DB에서 단독 실행)
set search_path = trip, public;

create or replace function pg_temp.expect_error(sql text, label text) returns void language plpgsql as $$
begin execute sql; raise notice 'FAIL  % (통과해 버림)', label;
exception when others then raise notice 'OK    % → %', label, left(sqlerrm, 120); end $$;
create or replace function pg_temp.expect_ok(sql text, label text) returns void language plpgsql as $$
begin execute sql; raise notice 'OK    %', label;
exception when others then raise notice 'FAIL  % → %', label, sqlerrm; end $$;

insert into staff(id, name) values ('a0000000-0000-0000-0000-000000000001','편집'),('a0000000-0000-0000-0000-000000000002','승인');

-- 공개 쇼츠 32편 생성: 부산 수영구 12편(그중 2편은 공개 5일차), 강릉 8편, 나머지 12편
do $$
declare i int; pid uuid; aid uuid; eid uuid; cid uuid; jid uuid; vid uuid; region text; age int;
begin
  for i in 1..32 loop
    region := case when i <= 12 then '부산 수영구' when i <= 20 then '강원 강릉' else '서울 마포구' end;
    age := case when i in (11, 12) then 5 else 20 end;
    insert into places(slug, official_name, region, segment, theme) values ('p'||i, '[예시] 장소 '||i, region, 'domestic_kr', 'family') returning id into pid;
    insert into assets(place_id, kind, source_type, uri, rights_status, approved_by, approved_at, evidence_uri, revoke_contact,
                       third_party_checked, allowed_media, allow_edit)
      values (pid, 'photo', 'provider', 'a'||i||'.jpg', 'approved', 'a0000000-0000-0000-0000-000000000001', now(), 'c.pdf', '담당 창구', true, '{youtube,hub}', true)
      returning id into aid;
    insert into evidence(place_id, kind, status, checked_by, checked_at) values (pid, 'official', 'verified', 'a0000000-0000-0000-0000-000000000001', now() - interval '10 days') returning id into eid;
    insert into claims(place_id, kind, body) values (pid, 'fact', '예시 주장 '||i) returning id into cid;
    insert into claim_evidence values (cid, eid);
    insert into content_jobs(place_id, question, segment, question_type) values (pid, '예시 질문 '||i, 'domestic_kr', case when i % 2 = 0 then '침구·객실' else '이동·접근' end) returning id into jid;
    insert into content_versions(job_id, version, title, script, made_by, reviewed_by, approved_by, approved_at, render_uri)
      values (jid, 1, '쇼츠 '||i, '[]', 'a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', now(), 's'||i||'.mp4')
      returning id into vid;
    insert into version_assets values (vid, aid);
    insert into version_claims values (vid, cid);
    update content_jobs set status='material_check' where id=jid;
    update content_jobs set status='ready' where id=jid;
    update content_jobs set status='rendering' where id=jid;
    update content_jobs set status='review' where id=jid;
    update content_jobs set status='approved' where id=jid;
    insert into publications(version_id, channel, status, external_id) values (vid, 'youtube', 'uploaded_private', 'yt'||i);
    update publications set status='public', verified_by='a0000000-0000-0000-0000-000000000002', verified_at = now() - make_interval(days => age) where version_id = vid;
    update content_jobs set status='published' where id=jid;
  end loop;
end $$;

do $$ declare r record; begin
  select * into r from trip.longform_candidates where bundle_type='region' and bundle_key='부산 수영구';
  if r.ready and r.shorts = 12 and r.eligible_shorts = 10 then raise notice 'OK    부산 수영구 묶음: 12편 중 관측기간 지난 10편 통과 → 롱폼 착수 가능';
  else raise notice 'FAIL  부산 묶음 %', row_to_json(r); end if;
  select * into r from trip.longform_candidates where bundle_type='region' and bundle_key='강원 강릉';
  if r.ready then raise notice 'OK    강릉 묶음 8편 → 착수 가능'; else raise notice 'FAIL  강릉 %', row_to_json(r); end if;
end $$;

-- 채널 누적 기준: 설정을 40편으로 올리면 모든 묶음이 대기
update longform_settings set min_channel_shorts = 40;
do $$ declare n int; begin
  select count(*) into n from trip.longform_candidates where ready;
  if n = 0 then raise notice 'OK    채널 누적 40편 미만이면 어떤 묶음도 착수 불가'; else raise notice 'FAIL  ready %', n; end if;
end $$;
update longform_settings set min_channel_shorts = 30;

-- 롱폼 프로젝트: 부산 묶음
insert into longform_projects(id, title, format, bundle_type, bundle_key, made_by)
values ('b0000000-0000-0000-0000-000000000001','바다에서 시작해 야경으로 끝나는 부산 48시간','route','region','부산 수영구','a0000000-0000-0000-0000-000000000001');

-- 관측 5일차 쇼츠 포함 8편 → 차단
insert into longform_chapters(project_id, job_id, position, chapter_title, new_commentary)
select 'b0000000-0000-0000-0000-000000000001', j.id, row_number() over (order by j.job_no), '챕터 '||j.job_no, '새 비교 해설'
  from content_jobs j join places p on p.id = j.place_id where p.slug in ('p5','p6','p7','p8','p9','p10','p11','p12');
update longform_projects set render_uri='lf1.mp4', intro_script='도입', approved_by='a0000000-0000-0000-0000-000000000002' where code='LF-0001';
select pg_temp.expect_error($$update trip.longform_projects set status='approved' where code='LF-0001'$$, '관측 14일 안 지난 쇼츠 포함 시 승인 차단');

-- 기준 통과 쇼츠로 교체, 그러나 롱폼 권리 재확인 전
delete from longform_chapters where project_id='b0000000-0000-0000-0000-000000000001';
insert into longform_chapters(project_id, job_id, position, chapter_title, new_commentary)
select 'b0000000-0000-0000-0000-000000000001', j.id, row_number() over (order by j.job_no), '챕터 '||j.job_no,
       case when p.slug = 'p3' then null else '새 비교 해설' end
  from content_jobs j join places p on p.id = j.place_id where p.slug in ('p1','p2','p3','p4','p5','p6','p7','p8');
select pg_temp.expect_error($$update trip.longform_projects set status='approved' where code='LF-0001'$$, '롱폼 사용 범위 재확인 없으면 차단');

insert into longform_rights(project_id, asset_id, reconfirmed_by, evidence_uri)
select 'b0000000-0000-0000-0000-000000000001', va.asset_id, 'a0000000-0000-0000-0000-000000000001', 'lf-rights.pdf'
  from longform_chapters c join content_versions v on v.job_id = c.job_id join version_assets va on va.version_id = v.id
 where c.project_id='b0000000-0000-0000-0000-000000000001';
select pg_temp.expect_error($$update trip.longform_projects set status='approved' where code='LF-0001'$$, '새 해설 없는 챕터가 있으면 차단 (단순 이어붙이기 금지)');
update longform_chapters set new_commentary='우천 시 대안 비교' where new_commentary is null;

-- 다른 지역 쇼츠 끼워 넣기 → 차단
insert into longform_chapters(project_id, job_id, position, chapter_title, new_commentary)
select 'b0000000-0000-0000-0000-000000000001', j.id, 9, '강릉 끼워넣기', '해설' from content_jobs j join places p on p.id=j.place_id where p.slug='p13';
select pg_temp.expect_error($$update trip.longform_projects set status='approved' where code='LF-0001'$$, '묶음 키와 다른 지역 쇼츠 포함 시 차단');
delete from longform_chapters where position = 9;

-- 정정 요청이 열린 쇼츠
insert into corrections(id, place_id, reason) select 'c0000000-0000-0000-0000-000000000001', id, '운영 시간 변경 제보' from places where slug='p2';
select pg_temp.expect_error($$update trip.longform_projects set status='approved' where code='LF-0001'$$, '미해결 정정 요청 있으면 차단');
update corrections set status='fixed', closed_at=now() where id='c0000000-0000-0000-0000-000000000001';

select pg_temp.expect_error($$update trip.longform_projects set approved_by='a0000000-0000-0000-0000-000000000001' where code='LF-0001'$$, '제작자 본인 승인 불가');
select pg_temp.expect_ok($$update trip.longform_projects set status='approved' where code='LF-0001'$$, '모든 기준 통과 → 롱폼 승인');

-- 승인 후 챕터 자산 철회 → 롱폼 자동 보류
update assets set rights_status='revoked' where uri='a4.jpg';
do $$ declare s text; begin
  select status into s from trip.longform_projects where code='LF-0001';
  if s='held' then raise notice 'OK    챕터 자산 철회 → 롱폼 자동 보류'; else raise notice 'FAIL  상태 %', s; end if;
end $$;
