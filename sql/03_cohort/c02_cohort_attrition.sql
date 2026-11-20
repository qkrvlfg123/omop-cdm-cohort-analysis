-- =============================================================================
-- [코호트 2] 탈락 흐름표 (Attrition table / CONSORT 흐름도의 숫자)
-- -----------------------------------------------------------------------------
-- 목적 : 선정기준을 "순서대로" 적용했을 때 단계마다 몇 명이 남고 몇 명이 빠지는지 보여 준다.
-- 기법 : 조건부 집계(SUM(CASE WHEN ...)), UNION ALL, LAG() 윈도우 함수
--
-- 중요한 이유 : RWE 연구 보고서의 Figure 1 은 거의 항상 이 흐름도다.
--   "최종 N명"만 말하면 선택 편향을 평가할 수 없다. 어느 기준에서 얼마나 빠졌는지가
--   코호트의 대표성을 판단하는 근거가 된다.
--
-- 순차 적용 : 3단계 인원 = 기준 A,B 를 "모두" 통과한 사람 (누적 AND).
--   그래서 각 SUM 안의 조건이 단계마다 하나씩 늘어난다.
-- =============================================================================
WITH steps AS (
    SELECT 0 AS step, '0. celecoxib/diclofenac 첫 처방 환자 (시작 모집단)' AS criterion,
           COUNT(*) AS n_remaining
    FROM work.nsaid_candidates
    UNION ALL
    SELECT 1, '1. 지표일이 관찰기간 내',
           SUM(CASE WHEN in_observation = 1 THEN 1 ELSE 0 END)
    FROM work.nsaid_candidates
    UNION ALL
    SELECT 2, '2. 지표일 이전 관찰 365일 이상',
           SUM(CASE WHEN in_observation = 1 AND has_365d_prior_obs = 1 THEN 1 ELSE 0 END)
    FROM work.nsaid_candidates
    UNION ALL
    SELECT 3, '3. 지표일 기준 18세 이상',
           SUM(CASE WHEN in_observation = 1 AND has_365d_prior_obs = 1 AND is_adult = 1 THEN 1 ELSE 0 END)
    FROM work.nsaid_candidates
    UNION ALL
    SELECT 4, '4. 지표일 이전(당일 포함) 골관절염 진단',
           SUM(CASE WHEN in_observation = 1 AND has_365d_prior_obs = 1 AND is_adult = 1
                     AND has_oa_dx = 1 THEN 1 ELSE 0 END)
    FROM work.nsaid_candidates
    UNION ALL
    SELECT 5, '5. 지표일 이전 위장관 출혈 이력 없음 (최종 코호트)',
           SUM(CASE WHEN in_observation = 1 AND has_365d_prior_obs = 1 AND is_adult = 1
                     AND has_oa_dx = 1 AND no_prior_gi_bleed = 1 THEN 1 ELSE 0 END)
    FROM work.nsaid_candidates
)
SELECT
    step,
    criterion,
    n_remaining,
    -- LAG(): 바로 "이전 행"의 값을 가져온다 → 이전 단계 인원 - 현재 인원 = 이 단계 탈락자
    COALESCE(LAG(n_remaining) OVER (ORDER BY step) - n_remaining, 0) AS n_excluded_at_step,
    -- FIRST_VALUE(): 첫 행(시작 모집단) 대비 잔존율
    ROUND(100.0 * n_remaining / FIRST_VALUE(n_remaining) OVER (ORDER BY step), 1) AS pct_of_start
FROM steps
ORDER BY step;
