-- =============================================================================
-- [패턴 7] 누적합 · 이동평균 · 분위수 — 추세와 분포 요약
-- -----------------------------------------------------------------------------
-- 쓰는 경우 : 연도별 신규 환자 추이(등록 속도), 누적 환자 수, 전년 대비 변화,
--             환자를 이용량 기준 4분위로 나누기(고이용자 식별) 등.
-- 기법      : SUM() OVER (ORDER BY ...) 누적합, AVG() OVER (ROWS BETWEEN ...) 이동평균,
--             LAG 로 전기 대비 증감, NTILE 로 분위 그룹
--
-- 프레임(ROWS BETWEEN) 을 명시하는 이유 :
--   ORDER BY 만 쓰면 기본 프레임이 RANGE ... CURRENT ROW 라서 정렬 키가 같은 행이
--   한꺼번에 더해진다. 의도를 분명히 하려고 ROWS 프레임을 직접 적는다.
--
-- 예제 A (이 쿼리) : 연도별 NSAID 코호트 신규 진입자 수, 누적 인원, 3년 이동평균
-- =============================================================================
WITH yearly AS (
    SELECT
        CAST(EXTRACT(YEAR FROM cohort_start_date) AS INTEGER) AS index_year,
        COUNT(*)                                              AS n_new_users
    FROM work.cohort
    GROUP BY 1
),
user_quartile AS (
    -- NTILE(4): 환자를 처방 건수 기준으로 4등분. 4 = 상위 25% (다빈도 이용자)
    SELECT
        person_id,
        n_rx,
        NTILE(4) OVER (ORDER BY n_rx) AS rx_quartile
    FROM (SELECT person_id, COUNT(*) AS n_rx FROM drug_exposure GROUP BY person_id) t
)
SELECT
    y.index_year,
    y.n_new_users,
    -- 누적합: 첫 해부터 현재 행까지
    SUM(y.n_new_users) OVER (ORDER BY y.index_year
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_users,
    -- 3년 이동평균: 직전 2개 행 + 현재 행 (연도별 들쭉날쭉함을 완화해 추세를 본다)
    ROUND(AVG(y.n_new_users) OVER (ORDER BY y.index_year
                                   ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1) AS moving_avg_3rows,
    -- 직전 행 대비 증감
    y.n_new_users - LAG(y.n_new_users) OVER (ORDER BY y.index_year)             AS diff_vs_prev,
    -- 스칼라 서브쿼리로 붙인 참고값: 처방 건수 상위 25% 환자의 최소 처방 건수(컷오프)
    (SELECT MIN(n_rx) FROM user_quartile WHERE rx_quartile = 4)                 AS top_quartile_rx_cutoff
FROM yearly y
ORDER BY y.index_year;
