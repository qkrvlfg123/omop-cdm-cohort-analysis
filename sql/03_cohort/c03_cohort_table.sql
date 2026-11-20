-- =============================================================================
-- [코호트 3] 최종 코호트 테이블 확정 (OMOP 표준 cohort 테이블 형식)
-- -----------------------------------------------------------------------------
-- 목적 : 모든 선정기준을 통과한 환자를 OMOP CDM 의 cohort 테이블 규격으로 저장한다.
--
-- OMOP cohort 테이블 규격 (4개 컬럼이 전부)
--   cohort_definition_id : 코호트 종류 번호 (여기서는 1 = celecoxib, 2 = diclofenac)
--   subject_id           : 환자 (= person_id)
--   cohort_start_date    : 코호트 진입일 (= 지표일)
--   cohort_end_date      : 코호트 종료일 (= 추적 종료일)
--
-- 표준 형식으로 저장하는 이유 : OHDSI 분석 도구(ATLAS, CohortMethod, FeatureExtraction 등)는
--   전부 이 4컬럼 테이블을 입력으로 받는다. 형식만 맞추면 내가 SQL로 만든 코호트를
--   표준 도구에 그대로 넘길 수 있다. "코호트 = (누가, 언제부터, 언제까지)" 라는 정의 자체다.
--
-- 추적 종료일(cohort_end_date) 규칙 — 둘 중 빠른 날 (LEAST)
--   (a) 지표일 + 365일          : 위험 노출 기간(time-at-risk)을 1년으로 고정
--   (b) 관찰기간 종료일          : 그 이후는 기록이 없으므로 "중도절단(censoring)"
--   ※ 원래는 "약을 끊은 날"도 종료 조건이지만, 이 데이터는 days_supply 가 전부 0 이라
--     복용 지속 기간을 알 수 없다. 그래서 '치료 의도(intention-to-treat)' 방식,
--     즉 시작한 약 기준으로 1년을 추적하는 방식을 택했다. (한계로 README 에 명시)
-- =============================================================================
CREATE OR REPLACE TABLE work.cohort AS
SELECT
    CASE index_drug WHEN 'celecoxib' THEN 1 WHEN 'diclofenac' THEN 2 END AS cohort_definition_id,
    person_id                                           AS subject_id,
    index_date                                          AS cohort_start_date,
    LEAST(index_date + INTERVAL 365 DAY,
          observation_period_end_date)::DATE            AS cohort_end_date
FROM work.nsaid_candidates
WHERE in_observation     = 1
  AND has_365d_prior_obs = 1
  AND is_adult           = 1
  AND has_oa_dx          = 1
  AND no_prior_gi_bleed  = 1;
