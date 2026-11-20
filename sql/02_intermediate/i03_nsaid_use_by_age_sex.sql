-- =============================================================================
-- [중급 3] 약물 사용 현황(Drug Utilization): NSAID 성분별 × 성별 × 첫 복용 연령대
-- -----------------------------------------------------------------------------
-- 목적 : "누가 어떤 NSAID를 언제부터 쓰기 시작했나"를 한 표로 본다.
-- 기법 : IN (서브쿼리), 파생 테이블(FROM 절 서브쿼리), CASE 구간화, HAVING
--
-- NSAID(비스테로이드 소염진통제) 성분 concept_id
--   1118084 celecoxib / 1124300 diclofenac / 1177480 ibuprofen / 1115008 naproxen / 1112807 aspirin
--   (concept 테이블에서 concept_class_id = 'Ingredient' 로 조회해서 확인한 값)
--
-- "첫 복용 시점 연령"을 쓰는 이유 : 같은 환자가 수십 년에 걸쳐 여러 번 복용하므로
--   기록마다 나이를 계산하면 한 환자가 여러 연령대에 중복 집계된다.
--   환자×성분당 최초 1건만 남겨야 "사용자 수" 통계가 된다.
-- =============================================================================
SELECT
    f.ingredient_name,
    g.concept_name AS gender,
    CASE
        WHEN f.age_at_first_use < 18 THEN '1) 0-17'
        WHEN f.age_at_first_use < 40 THEN '2) 18-39'
        WHEN f.age_at_first_use < 65 THEN '3) 40-64'
        ELSE                              '4) 65+'
    END AS age_group_at_first_use,
    COUNT(*)                          AS n_users,
    ROUND(AVG(f.age_at_first_use), 1) AS mean_age_at_first_use
FROM (
    -- 파생 테이블: 환자 × 성분별 최초 복용일과 그때 나이
    SELECT
        de.person_id,
        ing.concept_name AS ingredient_name,
        MIN(de.drug_exposure_start_date) AS first_use_date,
        -- OHDSI 관례: 나이 = 사건 연도 - 출생 연도 (월/일은 결측이 많아 연도만 사용)
        EXTRACT(YEAR FROM MIN(de.drug_exposure_start_date)) - MIN(p.year_of_birth) AS age_at_first_use
    FROM drug_exposure de
    JOIN concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
    JOIN concept ing         ON ing.concept_id = ca.ancestor_concept_id
    JOIN person p            ON p.person_id = de.person_id
    WHERE ca.ancestor_concept_id IN (
        -- IN (서브쿼리): 성분 목록을 하드코딩 대신 concept 테이블에서 이름으로 가져온다
        SELECT concept_id
        FROM concept
        WHERE concept_class_id = 'Ingredient'
          AND LOWER(concept_name) IN ('celecoxib', 'diclofenac', 'ibuprofen', 'naproxen', 'aspirin')
    )
    GROUP BY de.person_id, ing.concept_name
) f
JOIN person p       ON p.person_id = f.person_id
LEFT JOIN concept g ON g.concept_id = p.gender_concept_id
GROUP BY f.ingredient_name, g.concept_name, age_group_at_first_use
HAVING COUNT(*) >= 10          -- HAVING: 집계 "후" 필터. 10명 미만 셀은 숨김
                               -- (실무에서도 소수 셀은 재식별 위험 때문에 마스킹한다)
ORDER BY f.ingredient_name, gender, age_group_at_first_use;
