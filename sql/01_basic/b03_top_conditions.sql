-- =============================================================================
-- [기초 3] 가장 흔한 진단 상위 20개
-- -----------------------------------------------------------------------------
-- 목적 : condition_occurrence(진단 기록)에서 어떤 질환이 많은지 본다.
-- 기법 : INNER JOIN, GROUP BY, COUNT vs COUNT(DISTINCT), 스칼라 서브쿼리
--
-- 포인트 — "건수"와 "환자 수"는 다르다
--   n_records  : 진단 기록 건수 (감기처럼 반복되는 질환은 한 환자가 여러 건)
--   n_persons  : 그 진단을 한 번이라도 받은 환자 수
--   유병률(prevalence)을 말하려면 반드시 n_persons 를 전체 환자 수로 나눠야 한다.
-- =============================================================================
SELECT
    c.concept_id,
    c.concept_name                                   AS condition_name,
    c.vocabulary_id,                                 -- 표준 진단 용어는 SNOMED
    COUNT(*)                                         AS n_records,
    COUNT(DISTINCT co.person_id)                     AS n_persons,
    ROUND(1.0 * COUNT(*) / COUNT(DISTINCT co.person_id), 2) AS records_per_person,
    -- 스칼라 서브쿼리: 전체 환자 수(값 1개)를 분모로 사용
    ROUND(100.0 * COUNT(DISTINCT co.person_id)
          / (SELECT COUNT(*) FROM person), 1)        AS pct_of_all_persons
FROM condition_occurrence co
JOIN concept c
  ON c.concept_id = co.condition_concept_id
GROUP BY c.concept_id, c.concept_name, c.vocabulary_id
ORDER BY n_persons DESC
LIMIT 20;
