-- =============================================================================
-- [패턴 4] Gaps & Islands — 끊어진 처방 기록을 "연속 복용 기간(era)"으로 묶기
-- -----------------------------------------------------------------------------
-- 언제 쓰나 : 약처방 분석의 핵심. 처방은 7일분, 14일분씩 따로 기록되는데
--             분석에 필요한 것은 "언제부터 언제까지 계속 복용했나"이다.
--             복약 지속성(persistence), 치료 중단, 약물 노출 기간 계산의 기초.
-- 기법      : LAG / MAX() OVER 로 이전 행 참조 → 새 구간 시작 표시(0/1) →
--             누적합(SUM OVER)으로 구간 번호 부여 → 구간별 GROUP BY
--
-- 규칙 (OMOP drug_era 표준과 동일)
--   이전 처방 종료일로부터 30일 이내에 다음 처방이 시작되면 "같은 복용 기간"으로 본다.
--   30일(허용 간격, persistence window)은 약을 조금 늦게 타러 와도 중단으로 보지 않기 위한 여유.
--
-- 단계별 원리 (환자 4749 의 amoxicillin 예)
--   처방 시작     종료        이전까지의 최대 종료일   간격    새 구간?  구간번호(누적합)
--   1979-11-14  1979-11-28   (없음)                  -       1         1
--   1979-11-23  1979-12-14   1979-11-28              -5일    0         1   ← 겹침: 같은 구간
--   1994-04-08  1994-04-22   1979-12-14              14년    1         2   ← 새 구간
--
-- 검증 : CDM 에는 ETL 이 미리 계산해 둔 drug_era 테이블이 있다.
--        내가 짠 로직의 era 개수가 그 테이블과 일치하는지 마지막에 비교한다.
--        (정답지가 있는 문제로 내 SQL 을 검증)
-- =============================================================================
WITH exposures AS (
    -- amoxicillin 성분(1713332)이 들어간 모든 처방 (복합제 포함)
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS start_date,
        de.drug_exposure_end_date   AS end_date
    FROM drug_exposure de
    JOIN concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
    WHERE ca.ancestor_concept_id = 1713332
),
flagged AS (
    SELECT
        person_id, start_date, end_date,
        -- "이 행 이전까지의 종료일 중 가장 늦은 날".
        -- 단순 LAG(end_date) 가 아니라 누적 MAX 를 쓰는 이유: 긴 처방 안에 짧은 처방이
        -- 포함된 경우, 바로 앞 행의 종료일이 최댓값이 아닐 수 있기 때문.
        MAX(end_date) OVER (
            PARTITION BY person_id
            ORDER BY start_date, end_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_max_end
    FROM exposures
),
islands AS (
    SELECT
        person_id, start_date, end_date,
        -- 새 구간 시작이면 1. 누적합을 하면 같은 구간의 행들이 같은 번호를 갖게 된다.
        SUM(CASE WHEN prev_max_end IS NULL                               -- 첫 처방
                   OR DATEDIFF('day', prev_max_end, start_date) > 30     -- 30일 넘게 끊김
                 THEN 1 ELSE 0 END)
            OVER (PARTITION BY person_id ORDER BY start_date, end_date
                  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS era_no
    FROM flagged
),
my_era AS (
    SELECT
        person_id,
        era_no,
        MIN(start_date) AS era_start_date,
        MAX(end_date)   AS era_end_date,
        COUNT(*)        AS n_exposures
    FROM islands
    GROUP BY person_id, era_no
)
-- 내 결과와 CDM 의 drug_era 테이블을 나란히 비교
SELECT '직접 계산 (gaps & islands)' AS source,
       COUNT(*)                                            AS n_eras,
       COUNT(DISTINCT person_id)                           AS n_persons,
       SUM(CASE WHEN n_exposures > 1 THEN 1 ELSE 0 END)    AS n_eras_merged,   -- 2건 이상이 합쳐진 era
       ROUND(AVG(DATEDIFF('day', era_start_date, era_end_date)), 2) AS mean_era_days
FROM my_era
UNION ALL
SELECT 'CDM drug_era 테이블 (정답지)',
       COUNT(*),
       COUNT(DISTINCT person_id),
       SUM(CASE WHEN drug_exposure_count > 1 THEN 1 ELSE 0 END),
       ROUND(AVG(DATEDIFF('day', drug_era_start_date, drug_era_end_date)), 2)
FROM drug_era
WHERE drug_concept_id = 1713332;
