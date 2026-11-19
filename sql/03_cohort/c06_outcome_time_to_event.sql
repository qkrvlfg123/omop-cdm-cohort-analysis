-- =============================================================================
-- [코호트 6] 결과(outcome) 테이블: 환자별 위장관 출혈 발생 여부와 추적 기간
-- -----------------------------------------------------------------------------
-- 목적 : 생존분석(time-to-event)용 데이터셋을 만든다. 환자당 1행.
--          event     = 추적 기간 중 위장관 출혈이 발생했는가 (1/0)
--          time_days = 지표일부터 [출혈 발생일 또는 추적 종료일]까지 일수
-- 기법 : LEFT JOIN 에 날짜 범위 조건, MIN() 으로 첫 사건, COALESCE, CASE
--
-- 위험 노출 기간(Time-at-Risk) 정의 : 지표일 다음 날(+1일) ~ cohort_end_date
--   왜 +1일부터? 지표일 당일의 출혈은 "약 때문에 생긴 것"이라기보다 그 출혈 때문에
--   병원에 와서 약을 받은 것일 수 있다(역인과). 그래서 당일 사건은 결과로 세지 않는다.
--
-- LEFT JOIN 을 쓰는 이유 : 출혈이 없었던 환자(대다수)도 분모로 남아야 한다.
--   INNER JOIN 이면 출혈 환자만 남아 발생률 100% 라는 엉뚱한 결과가 나온다.
--   날짜 조건을 WHERE 가 아닌 ON 절에 둔 것도 같은 이유다.
--   (WHERE 에 두면 NULL 행이 걸러져 LEFT JOIN 이 사실상 INNER JOIN 으로 변한다)
-- =============================================================================
WITH first_outcome AS (
    SELECT
        c.subject_id,
        MIN(co.condition_start_date) AS outcome_date      -- 추적 기간 내 "첫" 출혈
    FROM work.cohort c
    JOIN condition_occurrence co
      ON co.person_id = c.subject_id
     AND co.condition_concept_id = 192671                 -- Gastrointestinal hemorrhage
     AND co.condition_start_date >  c.cohort_start_date   -- 지표일 다음 날부터
     AND co.condition_start_date <= c.cohort_end_date     -- 추적 종료일까지
    GROUP BY c.subject_id
)
SELECT
    c.cohort_definition_id,
    CASE c.cohort_definition_id WHEN 1 THEN 'celecoxib' ELSE 'diclofenac' END AS cohort_name,
    c.subject_id,
    c.cohort_start_date,
    c.cohort_end_date,
    fo.outcome_date,
    CASE WHEN fo.outcome_date IS NOT NULL THEN 1 ELSE 0 END AS event,
    -- 사건이 있으면 사건일까지, 없으면 추적 종료일까지 (= 중도절단 시점)
    DATEDIFF('day', c.cohort_start_date,
             COALESCE(fo.outcome_date, c.cohort_end_date))  AS time_days
FROM work.cohort c
LEFT JOIN first_outcome fo
       ON fo.subject_id = c.subject_id
ORDER BY c.cohort_definition_id, c.subject_id;
