-- =============================================================================
-- [코호트 4] 기저 특성표 (논문의 "Table 1") — 환자당 1행 공변량 테이블
-- -----------------------------------------------------------------------------
-- 목적 : 코호트 환자 각각에 대해 지표일 "이전" 정보만으로 특성 변수를 만든다.
--        결과는 환자당 1행(wide format) → Python 에서 그룹별 요약·SMD·시각화에 사용.
-- 기법 : CTE, 지표일 기준 날짜 윈도우 JOIN, 조건부 집계(MAX(CASE WHEN)), LEFT JOIN + COALESCE
--
-- 가장 중요한 원칙 — "공변량은 반드시 지표일 이전 정보로만 만든다"
--   지표일 이후 정보를 특성에 넣으면 미래 정보가 섞인다(시간 순서 위반).
--   머신러닝의 data leakage 와 같은 문제다. 그래서 모든 JOIN 조건에
--   `사건일 < cohort_start_date` (또는 <=) 가 들어 있다.
--
-- 날짜 윈도우를 변수마다 다르게 잡은 이유
--   - 동반질환(만성) : 지표일 이전 "전체 과거" → 궤양·대장염 같은 병력은 오래돼도 위험요인
--   - 병용 약물      : 지표일 이전 "365일"     → 약은 최근 복용 여부가 의미 있음
--   - 입원           : 지표일 이전 "365일"     → 최근 의료 이용 강도(건강 상태의 대리 지표)
-- =============================================================================
WITH prior_conditions AS (
    -- 위장관 출혈의 알려진 위험요인을 0/1 변수로 만든다 (조건부 집계로 세로 → 가로 피벗)
    -- MAX(CASE WHEN ... THEN 1 ELSE 0 END): 해당 진단이 한 건이라도 있으면 1
    SELECT
        c.subject_id,
        MAX(CASE WHEN co.condition_concept_id = 4027663 THEN 1 ELSE 0 END) AS prior_peptic_ulcer,
        MAX(CASE WHEN co.condition_concept_id = 81893   THEN 1 ELSE 0 END) AS prior_ulcerative_colitis,
        MAX(CASE WHEN co.condition_concept_id = 30753   THEN 1 ELSE 0 END) AS prior_esophagitis,
        MAX(CASE WHEN co.condition_concept_id = 4266809 THEN 1 ELSE 0 END) AS prior_diverticular_disease,
        MAX(CASE WHEN co.condition_concept_id = 4310024 THEN 1 ELSE 0 END) AS prior_angiodysplasia_stomach,
        MAX(CASE WHEN co.condition_concept_id = 4285898 THEN 1 ELSE 0 END) AS prior_colon_polyp,
        COUNT(DISTINCT co.condition_concept_id)                            AS n_distinct_prior_conditions
    FROM work.cohort c
    JOIN condition_occurrence co
      ON co.person_id = c.subject_id
     AND co.condition_start_date < c.cohort_start_date        -- 지표일 "이전"만 (당일 제외)
    GROUP BY c.subject_id
),
prior_drugs AS (
    -- 지표일 이전 365일 내 병용 약물 (성분 단위로 롤업)
    SELECT
        c.subject_id,
        MAX(CASE WHEN ca.ancestor_concept_id = 1112807 THEN 1 ELSE 0 END) AS prior_aspirin,
        MAX(CASE WHEN ca.ancestor_concept_id = 1177480 THEN 1 ELSE 0 END) AS prior_ibuprofen,
        MAX(CASE WHEN ca.ancestor_concept_id = 1115008 THEN 1 ELSE 0 END) AS prior_naproxen,
        MAX(CASE WHEN ca.ancestor_concept_id = 1125315 THEN 1 ELSE 0 END) AS prior_acetaminophen
    FROM work.cohort c
    JOIN drug_exposure de
      ON de.person_id = c.subject_id
     AND de.drug_exposure_start_date <  c.cohort_start_date
     AND de.drug_exposure_start_date >= c.cohort_start_date - INTERVAL 365 DAY   -- lookback 365일
    JOIN concept_ancestor ca
      ON ca.descendant_concept_id = de.drug_concept_id
    WHERE ca.ancestor_concept_id IN (1112807, 1177480, 1115008, 1125315)
    GROUP BY c.subject_id
),
prior_visits AS (
    SELECT
        c.subject_id,
        COUNT(*) AS n_inpatient_visits_365d
    FROM work.cohort c
    JOIN visit_occurrence v
      ON v.person_id = c.subject_id
     AND v.visit_concept_id = 9201
     AND v.visit_start_date <  c.cohort_start_date
     AND v.visit_start_date >= c.cohort_start_date - INTERVAL 365 DAY
    GROUP BY c.subject_id
)
SELECT
    c.cohort_definition_id,
    CASE c.cohort_definition_id WHEN 1 THEN 'celecoxib' ELSE 'diclofenac' END AS cohort_name,
    c.subject_id,
    c.cohort_start_date,
    EXTRACT(YEAR FROM c.cohort_start_date)                    AS index_year,
    EXTRACT(YEAR FROM c.cohort_start_date) - p.year_of_birth  AS age_at_index,
    CASE p.gender_concept_id WHEN 8532 THEN 1 ELSE 0 END      AS is_female,
    CASE p.race_concept_id                                    -- 인종 concept 는 이 축소판 concept 테이블에
        WHEN 8527 THEN 'White'                                -- 이름이 없어서 OMOP 표준 ID를 직접 매핑
        WHEN 8516 THEN 'Black'
        WHEN 8515 THEN 'Asian'
        ELSE 'Unknown'
    END                                                       AS race,
    DATEDIFF('day', op.observation_period_start_date, c.cohort_start_date) AS prior_obs_days,
    -- LEFT JOIN 에서 매칭이 없으면(=해당 이력 없음) NULL → 0
    COALESCE(pc.prior_peptic_ulcer, 0)           AS prior_peptic_ulcer,
    COALESCE(pc.prior_ulcerative_colitis, 0)     AS prior_ulcerative_colitis,
    COALESCE(pc.prior_esophagitis, 0)            AS prior_esophagitis,
    COALESCE(pc.prior_diverticular_disease, 0)   AS prior_diverticular_disease,
    COALESCE(pc.prior_angiodysplasia_stomach, 0) AS prior_angiodysplasia_stomach,
    COALESCE(pc.prior_colon_polyp, 0)            AS prior_colon_polyp,
    COALESCE(pc.n_distinct_prior_conditions, 0)  AS n_distinct_prior_conditions,
    COALESCE(pd.prior_aspirin, 0)                AS prior_aspirin,
    COALESCE(pd.prior_ibuprofen, 0)              AS prior_ibuprofen,
    COALESCE(pd.prior_naproxen, 0)               AS prior_naproxen,
    COALESCE(pd.prior_acetaminophen, 0)          AS prior_acetaminophen,
    COALESCE(pv.n_inpatient_visits_365d, 0)      AS n_inpatient_visits_365d
FROM work.cohort c
JOIN person p              ON p.person_id = c.subject_id
JOIN observation_period op ON op.person_id = c.subject_id
                          AND c.cohort_start_date BETWEEN op.observation_period_start_date
                                                      AND op.observation_period_end_date
LEFT JOIN prior_conditions pc ON pc.subject_id = c.subject_id
LEFT JOIN prior_drugs pd      ON pd.subject_id = c.subject_id
LEFT JOIN prior_visits pv     ON pv.subject_id = c.subject_id
ORDER BY c.cohort_definition_id, c.subject_id;
