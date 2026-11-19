# =============================================================================
# 01_setup_eunomia.R
# 목적: OHDSI Eunomia 패키지로 합성 OMOP CDM 데이터셋(GiBleed)을 로컬에 내려받아
#       DuckDB 파일(data/eunomia_gibleed.duckdb)로 만든다.
#
# 왜 Eunomia인가?
#   - OHDSI(OMOP CDM을 만든 국제 컨소시엄)가 교육/테스트용으로 공식 배포하는 데이터셋.
#   - Synthea(합성 환자 생성기)로 만든 가상 환자라 개인정보가 없고, 크레덴셜·심사가 필요 없다.
#   - 실제 병원 CDM과 "테이블 구조와 컬럼 이름이 동일"하므로, 여기서 짠 SQL은
#     실제 CDM에서도 스키마 이름만 바꾸면 그대로 돌아간다. (= CDM을 쓰는 이유 자체)
#
# 왜 DuckDB인가?
#   - 서버 설치 없이 파일 하나로 동작하는 분석용(OLAP) DB. 윈도우 함수·CTE·날짜 연산 등
#     표준 SQL 지원이 좋아 PostgreSQL 계열 문법과 거의 같다.
#   - SQLite는 DATE 타입이 없어 날짜 계산이 불편하다 → 코호트 분석은 날짜 연산이 핵심이라 DuckDB 선택.
#
# 실행: Rscript R/01_setup_eunomia.R   (프로젝트 루트에서)
# =============================================================================

library(Eunomia)
library(DBI)

data_dir <- "data"
db_file  <- file.path(data_dir, "eunomia_gibleed.duckdb")
dir.create(data_dir, showWarnings = FALSE)

# 이미 만들어져 있으면 지우고 새로 만든다 (재현성: 언제 돌려도 같은 결과).
if (file.exists(db_file)) file.remove(db_file)

# getDatabaseFile():
#   1) OHDSI/EunomiaDatasets 저장소에서 GiBleed_5.3.zip 을 내려받고
#   2) 압축 안의 테이블(parquet)을 지정한 DBMS 파일로 적재한다.
# GiBleed = "위장관 출혈(GI Bleed)" 연구용 예제 데이터. 약 2,700명의 합성 환자.
# 주의: Eunomia가 배포하는 GiBleed는 CDM v5.3 이다. v5.4와의 차이는 README에 정리.
Eunomia::getDatabaseFile(
  datasetName  = "GiBleed",
  cdmVersion   = "5.3",
  pathToData   = data_dir,
  dbms         = "duckdb",
  databaseFile = db_file,
  overwrite    = TRUE
)

# ---- 적재 검증: 테이블별 행 수를 찍어 본다 -----------------------------------
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_file, read_only = TRUE)
tables <- DBI::dbListTables(con)
counts <- sapply(tables, function(t) {
  DBI::dbGetQuery(con, sprintf('SELECT COUNT(*) AS n FROM "%s"', t))$n
})
print(sort(counts[counts > 0], decreasing = TRUE))
cat(sprintf("\n총 테이블 %d개 중 데이터가 있는 테이블 %d개\n",
            length(tables), sum(counts > 0)))
DBI::dbDisconnect(con, shutdown = TRUE)
