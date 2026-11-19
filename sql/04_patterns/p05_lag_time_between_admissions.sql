-- =============================================================================
-- [패턴 5] LAG 로 "직전 사건과의 간격" 구하기 — 재입원 분석
-- -----------------------------------------------------------------------------
-- 언제 쓰나 : 30일 재입원율(병원 질 지표), 재처방 간격, 재발까지 기간 등
--             "같은 환자의 연속된 두 사건 사이 시간"이 필요한 모든 경우.
-- 기법      : LAG() OVER (PARTITION BY 환자 ORDER BY 날짜), CASE 구간화, 윈도우 비율
--
-- LAG 가 없던 시절에는 같은 테이블을 자기 자신과 조인(self-join)했다.
--   환자당 방문이 n건이면 n×n 조합이 생겨 대용량에서 매우 느리다.
--   LAG 는 정렬 한 번으로 끝나므로 훨씬 효율적이다.
--
-- 재입원 간격의 정의 : 이번 입원 "시작일" - 직전 입원 "퇴원일"
--   (직전 입원 시작일이 아니라 퇴원일 기준이라는 점이 실수하기 쉬운 부분)
--
-- 이 데이터의 결과 해석 : 합성 데이터라 30일 내 재입원이 0건으로 나온다.
--   실제 병원 데이터에서는 보통 10~20% 수준. 여기서는 "쿼리 패턴"이 목적이다.
-- =============================================================================
WITH admissions AS (
    SELECT
        person_id,
        visit_occurrence_id,
        visit_start_date,
        visit_end_date,
        -- 같은 환자의 직전 입원 퇴원일. 첫 입원이면 NULL.
        LAG(visit_end_date) OVER (PARTITION BY person_id
                                  ORDER BY visit_start_date, visit_occurrence_id) AS prev_discharge_date,
        ROW_NUMBER() OVER (PARTITION BY person_id
                           ORDER BY visit_start_date, visit_occurrence_id)        AS admission_seq
    FROM visit_occurrence
    WHERE visit_concept_id = 9201      -- 입원만
),
gaps AS (
    SELECT
        *,
        DATEDIFF('day', prev_discharge_date, visit_start_date) AS days_since_discharge
    FROM admissions
)
SELECT
    CASE
        WHEN admission_seq = 1            THEN '0) 첫 입원 (직전 입원 없음)'
        WHEN days_since_discharge <= 30   THEN '1) 30일 이내 재입원'
        WHEN days_since_discharge <= 365  THEN '2) 31~365일 재입원'
        ELSE                                   '3) 1년 초과 후 재입원'
    END                                               AS readmission_category,
    COUNT(*)                                          AS n_admissions,
    COUNT(DISTINCT person_id)                         AS n_persons,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_admissions,
    ROUND(AVG(days_since_discharge), 0)               AS mean_days_since_discharge,
    MIN(days_since_discharge)                         AS min_days_since_discharge
FROM gaps
GROUP BY readmission_category
ORDER BY readmission_category;
