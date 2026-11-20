-- =============================================================================
-- [패턴 2] 조건부 집계로 "세로 데이터 → 가로 요약" (피벗)
-- -----------------------------------------------------------------------------
-- 쓰는 경우 : 연도별·그룹별 지표를 한 표로 만들 때, 분자/분모를 한 번의 스캔으로 구할 때.
-- 기법      : COUNT(DISTINCT CASE WHEN ...), SUM(CASE WHEN ...), 비율 계산 시 NULLIF
--
-- 핵심 아이디어 : WHERE 로 거르면 그 조건의 행만 남아 다른 지표를 같이 못 구한다.
--   조건을 집계 함수 "안"에 넣으면(CASE WHEN) 한 쿼리에서 여러 조건의 집계를 나란히 낼 수 있다.
--   테이블을 조건마다 따로 읽지 않으므로 대용량 테이블에서 훨씬 빠르다.
--
-- 예제 : 진단 연대(10년 단위)별 주요 질환군 환자 수와 비중
-- =============================================================================
SELECT
    CAST(FLOOR(EXTRACT(YEAR FROM co.condition_start_date) / 10.0) * 10 AS INTEGER) AS decade,
    COUNT(DISTINCT co.person_id)                                                   AS n_patients_any_dx,
    -- COUNT(DISTINCT CASE WHEN 조건 THEN person_id END): 조건에 안 맞으면 NULL → DISTINCT 집계에서 제외
    COUNT(DISTINCT CASE WHEN co.condition_concept_id = 80180   THEN co.person_id END) AS n_osteoarthritis,
    COUNT(DISTINCT CASE WHEN co.condition_concept_id = 192671  THEN co.person_id END) AS n_gi_hemorrhage,
    COUNT(DISTINCT CASE WHEN co.condition_concept_id = 4027663 THEN co.person_id END) AS n_peptic_ulcer,
    COUNT(DISTINCT CASE WHEN co.condition_concept_id IN (40481087, 4112343, 260139)
                        THEN co.person_id END)                                        AS n_acute_respiratory,
    -- 건수 기준 집계는 SUM(CASE ...)
    SUM(CASE WHEN co.condition_concept_id = 192671 THEN 1 ELSE 0 END)                 AS gi_hemorrhage_records,
    -- 비율: 분모가 0 이면 0 으로 나누기 오류 → NULLIF(분모, 0) 으로 NULL 처리하는 습관
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN co.condition_concept_id = 192671 THEN co.person_id END)
          / NULLIF(COUNT(DISTINCT co.person_id), 0), 2)                               AS pct_gi_hemorrhage
FROM condition_occurrence co
GROUP BY CAST(FLOOR(EXTRACT(YEAR FROM co.condition_start_date) / 10.0) * 10 AS INTEGER)
ORDER BY decade;
