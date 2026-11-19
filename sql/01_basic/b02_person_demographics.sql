-- =============================================================================
-- [기초 2] 환자 인구통계: 성별 × 출생 연대 분포
-- -----------------------------------------------------------------------------
-- 목적 : person 테이블로 전체 인구 구성을 파악한다.
-- 기법 : LEFT JOIN(concept), GROUP BY, FLOOR 로 10년 단위 구간화, 윈도우 함수로 비율 계산
--
-- OMOP 핵심 개념 — "모든 코드는 concept_id(숫자)로 저장된다"
--   person.gender_concept_id 에는 'F' 같은 글자가 아니라 8532 같은 숫자가 들어 있다.
--   사람이 읽을 이름은 concept 테이블과 JOIN 해서 얻는다. (8507 = MALE, 8532 = FEMALE)
--   이렇게 하는 이유: 병원마다 'F', '여', '2' 처럼 제각각인 원본 코드를
--   전 세계 공통 숫자로 통일해야 여러 기관 데이터를 같은 쿼리로 분석할 수 있기 때문.
--
-- 왜 LEFT JOIN 인가: concept 테이블에 없는 코드가 있어도 환자가 결과에서 빠지지 않게 하려고.
--   (INNER JOIN 이면 매핑 안 된 환자가 조용히 사라져 분모가 틀어진다.)
-- =============================================================================
SELECT
    COALESCE(g.concept_name, '(매핑 없음)')        AS gender,
    CAST(FLOOR(p.year_of_birth / 10.0) * 10 AS INTEGER) AS birth_decade,   -- 1957 → 195.7 → 195 → 1950
    COUNT(*)                                       AS n_persons,
    -- 윈도우 함수 SUM() OVER (): GROUP BY 결과 전체의 합을 각 행 옆에 붙인다 → 비율 계산
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_total
FROM person p
LEFT JOIN concept g
       ON g.concept_id = p.gender_concept_id
GROUP BY g.concept_name, CAST(FLOOR(p.year_of_birth / 10.0) * 10 AS INTEGER)
ORDER BY birth_decade, gender;
