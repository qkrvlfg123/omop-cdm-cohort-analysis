-- =============================================================================
-- [중급 1] 데이터 품질 점검 (분석 전에 반드시 하는 일)
-- -----------------------------------------------------------------------------
-- 목적 : "이 데이터로 무엇을 할 수 있고 무엇을 하면 안 되는지"를 숫자로 확인한다.
-- 기법 : NOT EXISTS(안티 조인), LEFT JOIN + IS NULL, 조건부 집계, UNION ALL
--
-- 왜 하는가 : 실제 RWD(Real-World Data)는 연구용으로 수집된 게 아니라서 구멍이 많다.
--   품질 점검 없이 분석하면 "데이터가 없는 것"을 "사건이 없는 것"으로 착각하게 된다.
--   OHDSI 에서는 이 작업을 ACHILLES / DataQualityDashboard 가 자동으로 해 주는데,
--   여기서는 원리를 이해하려고 대표 항목을 직접 SQL로 짰다.
--
-- 이 데이터(Eunomia GiBleed)에서 실제로 발견한 문제는 README '데이터 품질' 절에 정리.
-- =============================================================================

-- (1) 고아 레코드: person 에 없는 환자의 observation_period
--     NOT EXISTS = "짝이 없는 행 찾기"의 표준 패턴 (NOT IN 은 NULL 이 섞이면 결과가 비어 위험)
SELECT '1. person에 없는 환자의 observation_period 행'    AS check_name,
       COUNT(*)                                            AS n_problem,
       (SELECT COUNT(*) FROM observation_period)           AS n_total
FROM observation_period op
WHERE NOT EXISTS (SELECT 1 FROM person p WHERE p.person_id = op.person_id)

UNION ALL
-- (2) 끊어진 외래키: drug_exposure.visit_occurrence_id 가 실제 방문과 연결되지 않음
--     LEFT JOIN 후 오른쪽이 NULL 인 행 = 연결 실패
SELECT '2. 방문(visit)과 연결되지 않는 drug_exposure 행',
       COUNT(*) FILTER (WHERE v.visit_occurrence_id IS NULL),
       COUNT(*)
FROM drug_exposure de
LEFT JOIN visit_occurrence v ON v.visit_occurrence_id = de.visit_occurrence_id

UNION ALL
-- (3) 검사 결과값 결측: measurement.value_as_number 가 비어 있음
SELECT '3. 수치 결과가 없는 measurement 행',
       COUNT(*) FILTER (WHERE value_as_number IS NULL),
       COUNT(*)
FROM measurement

UNION ALL
-- (4) 표준 개념 매핑 실패: concept_id = 0 은 OMOP 에서 "매핑 못 함"을 뜻하는 약속된 값
SELECT '4. 인종(race) 미매핑 환자 (concept_id = 0)',
       COUNT(*) FILTER (WHERE race_concept_id = 0),
       COUNT(*)
FROM person

UNION ALL
-- (5) 처방 일수 정보 없음: days_supply = 0 이면 "얼마나 오래 복용했는지" 계산 불가
SELECT '5. days_supply 가 0 또는 NULL 인 drug_exposure 행',
       COUNT(*) FILTER (WHERE COALESCE(days_supply, 0) = 0),
       COUNT(*)
FROM drug_exposure

UNION ALL
-- (6) 날짜 논리 오류: 종료일이 시작일보다 빠른 처방
SELECT '6. 종료일 < 시작일 인 drug_exposure 행',
       COUNT(*) FILTER (WHERE drug_exposure_end_date < drug_exposure_start_date),
       COUNT(*)
FROM drug_exposure

UNION ALL
-- (7) 관찰기간 밖의 사건: 환자의 observation_period 밖에 기록된 진단
--     관찰기간 = "이 환자의 기록이 빠짐없이 수집된다고 믿을 수 있는 기간".
--     그 밖의 사건은 코호트 분석에서 쓰지 않는 것이 원칙이다.
SELECT '7. 관찰기간 밖에 기록된 condition_occurrence 행',
       COUNT(*) FILTER (WHERE op.person_id IS NULL),
       COUNT(*)
FROM condition_occurrence co
LEFT JOIN observation_period op
       ON op.person_id = co.person_id
      AND co.condition_start_date BETWEEN op.observation_period_start_date
                                      AND op.observation_period_end_date

UNION ALL
-- (8) 사망 정보 유무: death 테이블이 비어 있으면 사망을 결과변수로 쓸 수 없다
SELECT '8. death 테이블 행 수 (0이면 사망 분석 불가)',
       (SELECT COUNT(*) FROM death),
       (SELECT COUNT(*) FROM person)
ORDER BY check_name;
