-- =============================================================================
-- [패턴 3] 지표일(index date) 기준 날짜 윈도우 필터
-- -----------------------------------------------------------------------------
-- 언제 쓰나 : 코호트 연구의 거의 모든 변수. "지표일 전 1년 내 OO 이력", "지표일 후 30일 내 XX 발생".
-- 기법      : 범위 조건이 들어간 JOIN, 구간별 조건부 집계, FILTER 절
--
-- 시간 축을 구간으로 나누는 관례 (지표일 = day 0)
--   [-365, -1]  기저 기간(baseline)  → 공변량·제외기준 평가
--   [0]         지표일 당일           → 포함 여부는 연구마다 다름. 반드시 명시해야 함
--   [+1, +30]   단기 추적
--   [+31, +365] 장기 추적
--   경계(<, <=)를 하루만 잘못 써도 사건이 이중 집계되거나 누락된다. 구간은 겹치지 않게.
--
-- 예제 : NSAID 코호트 환자의 지표일 전후 구간별 '급성 호흡기 감염' 진단 건수
--        (work.cohort 는 sql/03_cohort/c03 에서 생성)
-- =============================================================================
WITH events AS (
    SELECT
        c.cohort_definition_id,
        c.subject_id,
        -- 지표일 기준 상대 일수: 음수 = 지표일 이전, 양수 = 이후
        DATEDIFF('day', c.cohort_start_date, co.condition_start_date) AS day_from_index
    FROM work.cohort c
    JOIN condition_occurrence co
      ON co.person_id = c.subject_id
     AND co.condition_concept_id IN (40481087, 4112343, 260139)   -- 바이러스성 부비동염/인두염, 급성 기관지염
     -- 필요한 범위만 JOIN 단계에서 잘라 낸다(±365일). 전체를 조인한 뒤 거르는 것보다 효율적.
     AND co.condition_start_date BETWEEN c.cohort_start_date - INTERVAL 365 DAY
                                     AND c.cohort_start_date + INTERVAL 365 DAY
)
SELECT
    CASE cohort_definition_id WHEN 1 THEN 'celecoxib' ELSE 'diclofenac' END AS cohort_name,
    -- FILTER (WHERE ...) : SUM(CASE WHEN ...) 과 같은 일을 하는 표준 SQL 문법 (PostgreSQL/DuckDB 지원)
    COUNT(*) FILTER (WHERE day_from_index BETWEEN -365 AND -1)   AS n_baseline_365d,
    COUNT(*) FILTER (WHERE day_from_index = 0)                   AS n_on_index_day,
    COUNT(*) FILTER (WHERE day_from_index BETWEEN 1 AND 30)      AS n_followup_1_30d,
    COUNT(*) FILTER (WHERE day_from_index BETWEEN 31 AND 365)    AS n_followup_31_365d,
    -- 기저 기간에 한 번이라도 진단받은 "환자 수"
    COUNT(DISTINCT subject_id) FILTER (WHERE day_from_index BETWEEN -365 AND -1) AS n_persons_baseline
FROM events
GROUP BY cohort_definition_id
ORDER BY cohort_definition_id;
