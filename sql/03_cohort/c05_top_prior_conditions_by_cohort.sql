-- =============================================================================
-- [코호트 5] 코호트별 과거 진단 상위 10개 (그룹 내 순위 매기기)
-- -----------------------------------------------------------------------------
-- 목적 : c04 는 내가 "미리 고른" 질환만 봤다. 여기서는 선입견 없이 코호트별로
--        지표일 이전에 가장 흔했던 진단을 데이터가 말해 주는 대로 뽑는다.
-- 기법 : CTE, COUNT(DISTINCT), RANK() OVER (PARTITION BY ...) = "그룹별 Top-N" 패턴
--
-- RANK vs ROW_NUMBER vs DENSE_RANK
--   ROW_NUMBER : 동점이어도 1,2,3,4 (임의로 순서를 가름)
--   RANK       : 동점이면 같은 순위, 다음 순위는 건너뜀 1,2,2,4
--   DENSE_RANK : 동점이면 같은 순위, 건너뛰지 않음     1,2,2,3
--   → "상위 10위"를 공정하게 뽑으려면 동점을 자르지 않는 RANK 가 적절하다.
-- =============================================================================
WITH cohort_size AS (
    SELECT cohort_definition_id, COUNT(*) AS n_cohort
    FROM work.cohort
    GROUP BY cohort_definition_id
),
prior_dx AS (
    SELECT
        c.cohort_definition_id,
        co.condition_concept_id,
        COUNT(DISTINCT c.subject_id) AS n_persons     -- 환자 수 기준 (기록 건수 아님)
    FROM work.cohort c
    JOIN condition_occurrence co
      ON co.person_id = c.subject_id
     AND co.condition_start_date < c.cohort_start_date
    GROUP BY c.cohort_definition_id, co.condition_concept_id
),
ranked AS (
    SELECT
        d.*,
        RANK() OVER (PARTITION BY d.cohort_definition_id
                     ORDER BY d.n_persons DESC) AS rank_in_cohort
    FROM prior_dx d
)
SELECT
    CASE r.cohort_definition_id WHEN 1 THEN 'celecoxib' ELSE 'diclofenac' END AS cohort_name,
    r.rank_in_cohort,
    cn.concept_name                                  AS condition_name,
    r.n_persons,
    ROUND(100.0 * r.n_persons / s.n_cohort, 1)       AS pct_of_cohort
FROM ranked r
JOIN cohort_size s ON s.cohort_definition_id = r.cohort_definition_id
JOIN concept cn    ON cn.concept_id = r.condition_concept_id
WHERE r.rank_in_cohort <= 10
ORDER BY r.cohort_definition_id, r.rank_in_cohort;
