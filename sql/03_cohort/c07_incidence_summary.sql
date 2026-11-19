-- =============================================================================
-- [코호트 7] 코호트별 위장관 출혈 발생 요약: 누적 발생률(risk)과 발생 밀도(rate)
-- -----------------------------------------------------------------------------
-- 목적 : c06 의 로직을 CTE 로 재사용해서 그룹별 요약 통계를 SQL 만으로 계산한다.
-- 기법 : CTE 체이닝, 집계 함수, 인년(person-years) 계산, 분위수(QUANTILE_CONT)
--
-- 두 가지 지표를 모두 내는 이유
--   누적 발생률(%)        = 사건 수 / 환자 수          → 직관적이지만 추적 기간 차이를 무시
--   발생 밀도(/1000인년)  = 사건 수 / 총 추적 인년      → 추적 기간이 다른 집단끼리 공정 비교
--   RWD 는 환자마다 추적 기간이 제각각(중도절단)이라 인년 기준 지표가 표준이다.
--
-- ※ 해석 주의 : 이 데이터는 합성(Synthea) 데이터이고 교란 보정도 하지 않았다.
--   아래 숫자는 "분석 절차의 시연"이지 celecoxib/diclofenac 의 실제 안전성 근거가 아니다.
-- =============================================================================
WITH first_outcome AS (
    SELECT c.subject_id, MIN(co.condition_start_date) AS outcome_date
    FROM work.cohort c
    JOIN condition_occurrence co
      ON co.person_id = c.subject_id
     AND co.condition_concept_id = 192671
     AND co.condition_start_date >  c.cohort_start_date
     AND co.condition_start_date <= c.cohort_end_date
    GROUP BY c.subject_id
),
tte AS (
    SELECT
        c.cohort_definition_id,
        CASE WHEN fo.outcome_date IS NOT NULL THEN 1 ELSE 0 END AS event,
        DATEDIFF('day', c.cohort_start_date,
                 COALESCE(fo.outcome_date, c.cohort_end_date))  AS time_days
    FROM work.cohort c
    LEFT JOIN first_outcome fo ON fo.subject_id = c.subject_id
)
SELECT
    CASE cohort_definition_id WHEN 1 THEN 'celecoxib' ELSE 'diclofenac' END AS cohort_name,
    COUNT(*)                                             AS n_persons,
    SUM(event)                                           AS n_events,
    ROUND(100.0 * SUM(event) / COUNT(*), 2)              AS cumulative_incidence_pct,
    ROUND(SUM(time_days) / 365.25, 1)                    AS person_years,
    ROUND(1000.0 * SUM(event) / (SUM(time_days) / 365.25), 1) AS rate_per_1000_py,
    -- 사건이 발생한 사람들만의 발생까지 걸린 일수 (FILTER 로 조건부 집계)
    QUANTILE_CONT(time_days, 0.5) FILTER (WHERE event = 1) AS median_days_to_event,
    MIN(time_days) FILTER (WHERE event = 1)                AS min_days_to_event,
    MAX(time_days) FILTER (WHERE event = 1)                AS max_days_to_event
FROM tte
GROUP BY cohort_definition_id
ORDER BY cohort_definition_id;
