-- =============================================================================
-- [기초 1] 핵심 임상 테이블별 행 수 / 환자 수
-- -----------------------------------------------------------------------------
-- 목적 : 새 DB를 받으면 제일 먼저 하는 일. "어느 테이블에 데이터가 얼마나 있나"를 본다.
-- 기법 : UNION ALL 로 테이블별 집계를 세로로 쌓기, COUNT(DISTINCT)
-- 이유 : 행 수(n_rows)와 환자 수(n_persons)를 같이 봐야 "환자당 기록이 몇 건인지"
--        감이 온다. 예) drug_exposure 가 67,707건 / 2,694명 → 1인당 약 25건.
-- =============================================================================
SELECT 'person'               AS table_name, COUNT(*) AS n_rows, COUNT(DISTINCT person_id) AS n_persons FROM person
UNION ALL
SELECT 'observation_period',   COUNT(*), COUNT(DISTINCT person_id) FROM observation_period
UNION ALL
SELECT 'visit_occurrence',     COUNT(*), COUNT(DISTINCT person_id) FROM visit_occurrence
UNION ALL
SELECT 'condition_occurrence', COUNT(*), COUNT(DISTINCT person_id) FROM condition_occurrence
UNION ALL
SELECT 'drug_exposure',        COUNT(*), COUNT(DISTINCT person_id) FROM drug_exposure
UNION ALL
SELECT 'procedure_occurrence', COUNT(*), COUNT(DISTINCT person_id) FROM procedure_occurrence
UNION ALL
SELECT 'measurement',          COUNT(*), COUNT(DISTINCT person_id) FROM measurement
UNION ALL
SELECT 'observation',          COUNT(*), COUNT(DISTINCT person_id) FROM observation
UNION ALL
SELECT 'death',                COUNT(*), COUNT(DISTINCT person_id) FROM death
ORDER BY n_rows DESC;
