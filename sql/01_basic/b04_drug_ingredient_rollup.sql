-- =============================================================================
-- [기초 4] 약물을 "성분(Ingredient)" 단위로 묶어서 사용 현황 보기
-- -----------------------------------------------------------------------------
-- 목적 : 처방 기록을 성분 기준으로 집계한다. (약처방 분석의 첫 단계)
-- 기법 : 3-테이블 JOIN, concept_ancestor(계층 테이블) 활용
--
-- 왜 필요한가 — drug_exposure 에는 약이 "제품 수준"으로 들어 있다
--   예) 'Aspirin 81 MG Oral Tablet', 'Ibuprofen 200 MG Oral Tablet', 'Ibuprofen 100 MG ...'
--   "이부프로펜 복용자"를 세려면 용량·제형이 다른 제품을 모두 찾아야 한다.
--   제품명을 LIKE '%ibuprofen%' 로 찾는 것은 누락·오탐 위험이 크다.
--
-- OMOP 의 해법 — concept_ancestor
--   (ancestor_concept_id = 성분, descendant_concept_id = 그 성분이 들어간 모든 제품)
--   관계가 미리 계산되어 있다. 성분 concept 하나만 알면 하위 제품을 전부 잡을 수 있다.
--   실제 병원 CDM에서 "메트포르민 처방 환자"를 뽑을 때도 정확히 이 방식을 쓴다.
--
-- 주의 : 복합제(예: Amoxicillin + Clavulanate)는 성분이 2개라 두 성분 모두에 집계된다.
--        그래서 n_records 의 합은 drug_exposure 전체 행 수보다 크다 (의도된 동작).
-- =============================================================================
SELECT
    ing.concept_id                    AS ingredient_concept_id,
    ing.concept_name                  AS ingredient_name,
    COUNT(DISTINCT de.drug_concept_id) AS n_distinct_products,  -- 이 성분으로 묶인 제품 종류 수
    COUNT(*)                          AS n_records,
    COUNT(DISTINCT de.person_id)      AS n_persons
FROM drug_exposure de
JOIN concept_ancestor ca
  ON ca.descendant_concept_id = de.drug_concept_id      -- 처방된 제품이 "자손"
JOIN concept ing
  ON ing.concept_id = ca.ancestor_concept_id            -- 그 "조상" 중에서
 AND ing.concept_class_id = 'Ingredient'                -- 성분 수준만 남긴다
GROUP BY ing.concept_id, ing.concept_name
ORDER BY n_persons DESC
LIMIT 20;
