# Travel.with.Jaws 작업 규칙

- 서비스: https://travel.jawsweb.site (미니PC Coolify, `main` 푸시 시 자동 배포). 설명·커밋 메시지는 한국어.
- 핵심 원칙: 권리·근거·승인 기록이 없으면 공개되지 않는다. 이 규칙은 화면이 아니라 DB(트리거·제약·뷰)에서 강제한다.
- DB 변경은 `db/migrations/` 에 **새 번호 파일**로만 추가한다. 적용된 파일은 수정하지 않는다 (`migrate.sh` 가 체크섬으로 막음).
- 새 규칙에는 `db/seed/test_*.sql` 시나리오를 함께 추가하고 `db/run_tests.sh` 의 최소 통과 수를 올린다.
- 커밋 전 확인: `PGURL=... ./db/run_tests.sh`, `cd hub && npm run build`.
- 공개 화면(anon)은 `public_*` 뷰만 읽는다. 콘솔은 서버에서 service_role 로 `console_*` 뷰·함수만 쓴다.
- 데모 데이터(`hub/lib/*Demo*`)는 예시임을 화면에 표시한다. 실제 숙소·크리에이터처럼 보이게 만들지 않는다.
- 업로드는 항상 비공개 → 사람 확인 → 공개. 자동 공개 기능을 만들지 않는다.
