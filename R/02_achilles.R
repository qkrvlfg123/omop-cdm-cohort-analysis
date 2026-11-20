# =============================================================================
# 02_achilles.R
# 목적: OHDSI ACHILLES 로 CDM 데이터베이스 전체를 특성화(characterization)한다.
#
# ACHILLES
#   (Automated Characterization of Health Information at Large-scale Longitudinal
#    Evidence Systems)
#   - CDM 테이블 전체를 훑어 수백 개의 표준 요약 통계를 자동으로 계산하는 OHDSI 공식 R 패키지.
#     예) 성별·출생연도 분포, 진단/약물별 환자 수, 관찰기간 길이 분포 등.
#   - 병원이 CDM 을 구축(ETL)한 뒤 "변환이 제대로 됐는지" 확인하는 첫 단계로 쓰이고,
#     결과는 ATLAS 의 Data Sources 화면에 그대로 표시된다.
#   - 내가 sql/01_basic, 02_intermediate 에서 손으로 짠 요약 쿼리를
#     표준화·자동화한 도구라고 이해하면 된다. → 내 SQL 결과와 숫자를 교차검증하는 데도 사용.
#
# 동작 방식: 분석 하나 = analysis_id 하나. 결과는 achilles_results 테이블에
#   (analysis_id, stratum_1..5, count_value) 형태의 "긴 표"로 쌓인다.
#   stratum 의 의미는 analysis_id 마다 다르다(예: 2번 분석의 stratum_1 = gender_concept_id).
#
# 실행: Rscript R/02_achilles.R      (Java 필요. JAVA_HOME 환경변수 설정)
# =============================================================================

library(Achilles)
library(DatabaseConnector)

ach_db  <- "data/eunomia_achilles.sqlite"
out_dir <- "results/achilles"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ACHILLES 전용으로 같은 GiBleed 데이터를 SQLite 파일로 한 벌 더 만든다.
#  - 이유 1: ACHILLES 는 결과 테이블을 DB 안에 "쓴다". 분석용 원본(DuckDB)은 건드리지 않으려고 분리.
#            (실무에서도 CDM 스키마는 읽기 전용, 결과는 별도 results 스키마에 쓴다)
#  - 이유 2: 현재 Achilles + DuckDB 드라이버 조합은 결과 적재 단계에서 컬럼 대소문자 오류
#            ("Column ANALYSIS_ID does not exist")가 난다. 직접 시도해 확인했고,
#            OHDSI 가 Eunomia 기본으로 쓰는 SQLite 로 우회했다.
#  이미 내려받은 data/GiBleed_5.3.zip 을 재사용하므로 추가 다운로드는 없다.
if (file.exists(ach_db)) file.remove(ach_db)
Eunomia::getDatabaseFile(
  datasetName  = "GiBleed",
  cdmVersion   = "5.3",
  pathToData   = "data",
  dbms         = "sqlite",
  databaseFile = ach_db,
  overwrite    = TRUE
)

connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms   = "sqlite",
  server = ach_db
)

# ---- ACHILLES 실행 ----------------------------------------------------------
Achilles::achilles(
  connectionDetails        = connectionDetails,
  cdmDatabaseSchema        = "main",     # CDM 테이블이 있는 스키마
  resultsDatabaseSchema    = "main",     # 결과(achilles_results 등)를 쓸 스키마
  cdmVersion               = "5.3",
  sourceName               = "Eunomia GiBleed (Synthea)",
  createTable              = TRUE,
  smallCellCount           = 5,          # 5명 이하 셀은 결과에서 제외(재식별 방지 관례)
  optimizeAtlasCache       = FALSE,
  outputFolder             = out_dir
)

# ---- 결과를 사람이 읽을 수 있는 CSV 로 내보내기 --------------------------------
con <- DatabaseConnector::connect(connectionDetails)

# (1) 어떤 분석이 몇 행의 결과를 냈는지 목록
details <- Achilles::getAnalysisDetails()
names(details) <- tolower(names(details))
summary_tbl <- DatabaseConnector::querySql(con, "
  SELECT analysis_id, COUNT(*) AS n_result_rows, SUM(count_value) AS sum_count_value
  FROM main.achilles_results
  GROUP BY analysis_id
  ORDER BY analysis_id")
names(summary_tbl) <- tolower(names(summary_tbl))
summary_tbl <- merge(summary_tbl,
                     details[, c("analysis_id", "analysis_name", "category")],
                     by = "analysis_id", all.x = TRUE)
write.csv(summary_tbl, file.path(out_dir, "achilles_analysis_summary.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

# (2) 대표 분석 몇 개를 concept 이름과 함께 추출
#     analysis_id 의미: 1=전체 환자 수, 2=성별 환자 수, 3=출생연도별 환자 수,
#                       400=진단 concept 별 환자 수, 700=약물 concept 별 환자 수
key <- DatabaseConnector::querySql(con, "
  SELECT r.analysis_id, r.stratum_1, c.concept_name, r.count_value
  FROM main.achilles_results r
  LEFT JOIN main.concept c
         ON CAST(c.concept_id AS VARCHAR) = r.stratum_1
        AND r.analysis_id IN (2, 400, 700)
  WHERE r.analysis_id IN (1, 2, 3, 400, 700)
  ORDER BY r.analysis_id, r.count_value DESC")
names(key) <- tolower(names(key))
write.csv(key, file.path(out_dir, "achilles_key_results.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

# (3) 연속형 분포 결과 (예: 105/106 = 관찰기간 길이 분포)
dist <- DatabaseConnector::querySql(con, "SELECT * FROM main.achilles_results_dist ORDER BY analysis_id")
names(dist) <- tolower(names(dist))
write.csv(dist, file.path(out_dir, "achilles_results_dist.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

DatabaseConnector::disconnect(con)

cat(sprintf("\nACHILLES 완료: 분석 %d종, 결과 %d행\n",
            nrow(summary_tbl), sum(summary_tbl$n_result_rows)))
print(head(key[key$analysis_id %in% c(1, 2), ], 5))
