-- =============================================================================
-- [중급 2] 환자별 요약 테이블 만들기 — "조인 뻥튀기(fan-out)" 피하기
-- -----------------------------------------------------------------------------
-- 목적 : 환자 1명당 1행으로 진단 수 / 처방 수 / 입원 수 / 관찰 기간을 요약한다.
-- 기법 : CTE(WITH), "먼저 집계하고 나중에 조인", LEFT JOIN + COALESCE
--
-- 의료데이터 SQL에서 가장 흔한 실수 — 1:N 테이블 두 개를 한꺼번에 조인하기
--   틀린 예)
--     SELECT p.person_id, COUNT(co.condition_occurrence_id), COUNT(de.drug_exposure_id)
--     FROM person p
--     JOIN condition_occurrence co ON co.person_id = p.person_id
--     JOIN drug_exposure de        ON de.person_id = p.person_id
--     GROUP BY p.person_id;
--   진단 24건 × 처방 25건인 환자는 600행으로 불어나서 두 COUNT 가 모두 600이 된다.
--   에러 없이 "그럴듯한 틀린 숫자"가 나오기 때문에 위험하다.
--
-- 올바른 방법 — 테이블별로 먼저 환자당 1행으로 집계(CTE)한 뒤 조인한다.
--   그러면 모든 조인이 1:1 이 되어 행이 불어나지 않는다.
--
-- 검증 방법 : 결과 행 수 = person 행 수(2,694) 여야 한다. (run_analysis.py 에서 확인)
-- =============================================================================
WITH cond AS (
    SELECT person_id,
           COUNT(*)                             AS n_conditions,
           COUNT(DISTINCT condition_concept_id) AS n_distinct_conditions
    FROM condition_occurrence
    GROUP BY person_id
),
drug AS (
    SELECT person_id,
           COUNT(*)                        AS n_drug_records,
           COUNT(DISTINCT drug_concept_id) AS n_distinct_drugs
    FROM drug_exposure
    GROUP BY person_id
),
visit AS (
    SELECT person_id,
           COUNT(*) AS n_inpatient_visits
    FROM visit_occurrence
    WHERE visit_concept_id = 9201          -- 9201 = Inpatient Visit(입원)
    GROUP BY person_id
)
SELECT
    p.person_id,
    g.concept_name                                   AS gender,
    p.year_of_birth,
    op.observation_period_start_date,
    op.observation_period_end_date,
    ROUND(DATEDIFF('day', op.observation_period_start_date,
                          op.observation_period_end_date) / 365.25, 1) AS observation_years,
    -- 기록이 아예 없는 환자는 LEFT JOIN 결과가 NULL → 0 으로 바꿔 준다
    COALESCE(cond.n_conditions, 0)          AS n_conditions,
    COALESCE(cond.n_distinct_conditions, 0) AS n_distinct_conditions,
    COALESCE(drug.n_drug_records, 0)        AS n_drug_records,
    COALESCE(drug.n_distinct_drugs, 0)      AS n_distinct_drugs,
    COALESCE(visit.n_inpatient_visits, 0)   AS n_inpatient_visits
FROM person p
JOIN observation_period op ON op.person_id = p.person_id   -- 이 데이터는 환자당 관찰기간 1개(확인함)
LEFT JOIN concept g        ON g.concept_id = p.gender_concept_id
LEFT JOIN cond             ON cond.person_id  = p.person_id
LEFT JOIN drug             ON drug.person_id  = p.person_id
LEFT JOIN visit            ON visit.person_id = p.person_id
ORDER BY p.person_id;
