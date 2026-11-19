-- =============================================================================
-- [코호트 1] NSAID 신규 사용자 후보 테이블 (환자당 1행 + 선정기준 플래그)
-- -----------------------------------------------------------------------------
-- 연구 질문(예제):
--   "골관절염 환자 중 celecoxib 또는 diclofenac 을 '처음' 시작한 사람은 누구이며,
--    두 집단의 특성과 시작 후 위장관 출혈 발생은 어떻게 다른가?"
--
-- 설계 : 신규 사용자 코호트(New-User Cohort Design)
--   - 지표일(index date) = 해당 약을 생애 처음 처방받은 날
--   - 왜 "신규" 사용자만? 이미 오래 복용 중인 사람(prevalent user)은 부작용을 겪고도
--     버틴 "생존자"라서, 포함하면 약이 실제보다 안전해 보이는 편향이 생긴다.
--     약물역학(pharmacoepidemiology)의 표준 설계다.
--
-- 이 파일이 하는 일 : 탈락시키지 않고 "기준 충족 여부 플래그"만 붙인다.
--   → c02 에서 단계별 탈락 인원(attrition)을 세고, c03 에서 최종 코호트를 확정한다.
--   플래그 방식의 장점: 어떤 기준에서 몇 명이 빠졌는지 추적 가능하고,
--   기준을 바꿔 보는 민감도 분석이 쉽다.
--
-- 기법 : 다단계 CTE, concept_ancestor JOIN, ROW_NUMBER() 윈도우 함수,
--        EXISTS / NOT EXISTS 상관 서브쿼리, 날짜 연산
-- =============================================================================
CREATE OR REPLACE TABLE work.nsaid_candidates AS

WITH target_exposure AS (
    -- 1) 두 성분(및 그 하위 제품 전체)의 모든 처방 기록을 가져온다.
    --    concept_ancestor 를 쓰면 성분 concept 2개만으로 용량·제형이 다른 제품이 모두 잡힌다.
    SELECT
        de.person_id,
        ca.ancestor_concept_id          AS ingredient_concept_id,
        de.drug_exposure_start_date
    FROM drug_exposure de
    JOIN concept_ancestor ca
      ON ca.descendant_concept_id = de.drug_concept_id
    WHERE ca.ancestor_concept_id IN (1118084,   -- celecoxib  (선택적 COX-2 억제제)
                                     1124300)   -- diclofenac (비선택적 NSAID)
),

first_exposure AS (
    -- 2) 환자별 "생애 첫" 처방 1건만 남긴다 = 지표일(index date) 결정.
    --    ROW_NUMBER() : 환자(PARTITION BY)별로 날짜순(ORDER BY) 번호를 매긴다. 1번 = 최초.
    --    MIN() + GROUP BY 대신 ROW_NUMBER 를 쓰는 이유:
    --    "그 최초 처방이 어떤 성분이었는지"까지 같은 행에서 가져와야 하기 때문.
    --    (동점 처리: 같은 날 두 약이 있으면 ingredient_concept_id 순 → 결과가 실행마다 같도록)
    SELECT person_id, ingredient_concept_id, index_date
    FROM (
        SELECT
            person_id,
            ingredient_concept_id,
            drug_exposure_start_date AS index_date,
            ROW_NUMBER() OVER (
                PARTITION BY person_id
                ORDER BY drug_exposure_start_date, ingredient_concept_id
            ) AS rn
        FROM target_exposure
    ) ranked
    WHERE rn = 1
)

SELECT
    fe.person_id,
    fe.ingredient_concept_id,
    CASE fe.ingredient_concept_id
        WHEN 1118084 THEN 'celecoxib'
        WHEN 1124300 THEN 'diclofenac'
    END                                                    AS index_drug,
    fe.index_date,
    EXTRACT(YEAR FROM fe.index_date) - p.year_of_birth     AS age_at_index,
    p.gender_concept_id,
    op.observation_period_start_date,
    op.observation_period_end_date,

    -- ---------------- 선정기준 플래그 (1 = 충족) ----------------

    -- [기준 A] 지표일이 관찰기간 안에 있다.
    --   관찰기간 밖의 사건은 "기록이 온전한지" 보장할 수 없어서 쓰지 않는다.
    --   LEFT JOIN 이므로 관찰기간이 매칭 안 되면 NULL → 0.
    CASE WHEN op.person_id IS NOT NULL THEN 1 ELSE 0 END   AS in_observation,

    -- [기준 B] 지표일 이전 관찰기간이 365일 이상이다 (washout / lookback).
    --   이유 1: "신규" 사용자임을 확인하려면 과거 1년간 처방 이력이 없음을 볼 수 있어야 한다.
    --   이유 2: 기저 동반질환을 파악할 최소한의 과거 기록이 필요하다.
    CASE WHEN DATEDIFF('day', op.observation_period_start_date, fe.index_date) >= 365
         THEN 1 ELSE 0 END                                 AS has_365d_prior_obs,

    -- [기준 C] 지표일 기준 18세 이상 성인.
    CASE WHEN EXTRACT(YEAR FROM fe.index_date) - p.year_of_birth >= 18
         THEN 1 ELSE 0 END                                 AS is_adult,

    -- [기준 D] 지표일 또는 그 이전에 골관절염(80180) 진단이 있다 = 적응증 확인.
    --   EXISTS: "조건에 맞는 행이 하나라도 있는가"만 본다. JOIN 과 달리 행이 불어나지 않는다.
    CASE WHEN EXISTS (
            SELECT 1 FROM condition_occurrence co
            WHERE co.person_id = fe.person_id
              AND co.condition_concept_id = 80180          -- Osteoarthritis
              AND co.condition_start_date <= fe.index_date
         ) THEN 1 ELSE 0 END                               AS has_oa_dx,

    -- [기준 E] 지표일 "이전"에 위장관 출혈(192671) 이력이 없다.
    --   결과(outcome)를 이미 겪은 사람을 빼야 "새로 발생한" 출혈(발생률)을 셀 수 있다.
    CASE WHEN NOT EXISTS (
            SELECT 1 FROM condition_occurrence co
            WHERE co.person_id = fe.person_id
              AND co.condition_concept_id = 192671         -- Gastrointestinal hemorrhage
              AND co.condition_start_date < fe.index_date
         ) THEN 1 ELSE 0 END                               AS no_prior_gi_bleed

FROM first_exposure fe
JOIN person p
  ON p.person_id = fe.person_id
LEFT JOIN observation_period op
  ON op.person_id = fe.person_id
 AND fe.index_date BETWEEN op.observation_period_start_date
                       AND op.observation_period_end_date;
