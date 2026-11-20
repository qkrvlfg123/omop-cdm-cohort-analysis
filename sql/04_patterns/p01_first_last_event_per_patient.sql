-- =============================================================================
-- [패턴 1] 환자별 "최초 / 최근" 사건 찾기
-- -----------------------------------------------------------------------------
-- 쓰는 경우 : 최초 진단일(발병 시점), 최초 처방일(지표일), 최근 방문일(마지막 추적 시점)
--             → 코호트 연구에서 가장 자주 쓰는 패턴.
-- 기법      : ROW_NUMBER() 를 오름차순/내림차순으로 두 번, 조건부 집계로 한 행에 합치기
--
-- MIN/MAX 로도 날짜는 구할 수 있다. 하지만 "그 최초 진단의 '다른 컬럼'(진단명 등)"까지
-- 가져오려면 ROW_NUMBER 로 행 자체를 골라야 한다. 이것이 윈도우 함수를 쓰는 이유.
--
-- 예제 : 환자별 첫 진단과 가장 최근 진단, 그 사이 기간
-- 참고 : DuckDB/Snowflake/BigQuery 는 QUALIFY rn = 1 로 서브쿼리 없이 쓸 수 있지만,
--        PostgreSQL·Oracle·SQL Server 에서도 돌도록 서브쿼리 방식으로 작성했다.
-- =============================================================================
WITH numbered AS (
    SELECT
        co.person_id,
        co.condition_start_date,
        c.concept_name AS condition_name,
        -- 동점(같은 날 여러 진단)일 때 결과가 실행마다 달라지지 않도록 PK 를 2차 정렬 키로 둔다
        ROW_NUMBER() OVER (PARTITION BY co.person_id
                           ORDER BY co.condition_start_date ASC,  co.condition_occurrence_id ASC)  AS rn_first,
        ROW_NUMBER() OVER (PARTITION BY co.person_id
                           ORDER BY co.condition_start_date DESC, co.condition_occurrence_id DESC) AS rn_last,
        COUNT(*)     OVER (PARTITION BY co.person_id)                                              AS n_total
    FROM condition_occurrence co
    JOIN concept c ON c.concept_id = co.condition_concept_id
)
SELECT
    person_id,
    MAX(n_total)                                                  AS n_conditions,
    MAX(CASE WHEN rn_first = 1 THEN condition_start_date END)     AS first_dx_date,
    MAX(CASE WHEN rn_first = 1 THEN condition_name END)           AS first_dx_name,
    MAX(CASE WHEN rn_last  = 1 THEN condition_start_date END)     AS last_dx_date,
    MAX(CASE WHEN rn_last  = 1 THEN condition_name END)           AS last_dx_name,
    DATEDIFF('day',
             MAX(CASE WHEN rn_first = 1 THEN condition_start_date END),
             MAX(CASE WHEN rn_last  = 1 THEN condition_start_date END)) AS days_between
FROM numbered
WHERE rn_first = 1 OR rn_last = 1
GROUP BY person_id
ORDER BY person_id
LIMIT 20;
