-- =============================================================================
-- [패턴 6] 제외 기준 적용 — 안티 조인 3가지 방법과 NOT IN 의 함정
-- -----------------------------------------------------------------------------
-- 쓰는 경우 : "OO 이력이 '없는' 환자"를 뽑을 때. 코호트 제외기준의 기본형.
-- 기법      : NOT EXISTS / LEFT JOIN ... IS NULL / EXCEPT  (셋 다 같은 결과)
--
-- 예제 : 골관절염 환자 중 '소화성 궤양(4027663) 진단을 받은 적이 없는' 환자 수
--
-- 세 방법 비교
--   NOT EXISTS        : 의도가 가장 잘 읽히고 NULL 에 안전. 기본 선택.
--   LEFT JOIN IS NULL : 같은 결과. 오른쪽 테이블 컬럼을 추가로 봐야 할 때 유용.
--   EXCEPT            : 집합 연산. 키 컬럼만 다룰 때 간결.
--
-- NOT IN 을 피하는 이유 :
--   WHERE person_id NOT IN (SELECT person_id FROM t)
--   서브쿼리 결과에 NULL 이 하나라도 있으면 전체 결과가 0행이 된다.
--   (x NOT IN (1, NULL) 은 "알 수 없음"으로 평가되기 때문.)
--   에러 없이 조용히 0건이 나오므로 발견하기 어렵다.
--
-- 세 방법의 결과가 같은지 한 표로 확인 → 내 쿼리를 다른 방식으로 교차검증하는 습관.
-- =============================================================================
WITH oa_patients AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_concept_id = 80180
),
ulcer_patients AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_concept_id = 4027663
)
SELECT '전체 골관절염 환자' AS method, COUNT(*) AS n_persons
FROM oa_patients

UNION ALL
SELECT '궤양 이력 없음 — NOT EXISTS', COUNT(*)
FROM oa_patients o
WHERE NOT EXISTS (SELECT 1 FROM ulcer_patients u WHERE u.person_id = o.person_id)

UNION ALL
SELECT '궤양 이력 없음 — LEFT JOIN + IS NULL', COUNT(*)
FROM oa_patients o
LEFT JOIN ulcer_patients u ON u.person_id = o.person_id
WHERE u.person_id IS NULL

UNION ALL
SELECT '궤양 이력 없음 — EXCEPT', COUNT(*)
FROM (
    SELECT person_id FROM oa_patients
    EXCEPT
    SELECT person_id FROM ulcer_patients
) x;
