"""
compare_mimic_demo.py — 같은 SQL 을 "다른 CDM 데이터베이스"에 그대로 돌려 본다.

실행:  python src/compare_mimic_demo.py     (프로젝트 루트에서)

비교 대상
- Eunomia GiBleed : Synthea 합성 환자 2,694명 (일생에 걸친 기록, 방문 유형은 입원 한 가지)
- MIMIC-IV demo   : 미국 Beth Israel Deaconess 병원 중환자실 실제 환자 100명의 비식별 공개본을
                    OMOP CDM 으로 변환한 것 (PhysioNet, 크레덴셜 없이 공개)
                    https://physionet.org/content/mimic-iv-demo-omop/0.9/

이 스크립트로 보여 주려는 것
1) CDM 의 핵심 가치: 출처가 전혀 다른 두 DB 에 "똑같은 .sql 파일"이 수정 없이 실행된다.
   (sql/01_basic/b01, sql/02_intermediate/i02 를 그대로 재사용)
2) 그러나 "구조가 같다 ≠ 내용이 같다". 테이블마다 채워진 정도가 달라서
   DB 마다 가능한 분석이 다르다 → 분석 전 데이터 품질 점검이 필수인 이유.

발견한 주의점 (README 에도 정리)
- MIMIC demo 의 concept 테이블에는 MIMIC 자체 코드(2,000,000,000번대)만 들어 있다.
  표준 용어(SNOMED, RxNorm 등)는 라이선스 문제로 빠져 있어, OHDSI Athena 에서 별도로 받아
  적재해야 concept 이름 조인과 concept_ancestor 롤업이 가능하다.
  → concept JOIN 을 쓰는 쿼리(b03, b04 등)는 실행은 되지만 결과가 비거나 이름이 NULL 이다.
- MIMIC 은 비식별화를 위해 날짜를 미래(2100년대)로 이동시켰다. 환자 내 간격은 보존되지만
  달력 연도 분석(연도별 추세)은 의미가 없다.
"""
import re
import sys
import zipfile
from pathlib import Path
from urllib.request import urlretrieve

import duckdb
import pandas as pd

from run_sql import connect, ROOT

MIMIC_DIR = ROOT / "data" / "mimic_demo"
ZIP_PATH = MIMIC_DIR / "mimic_omop.zip"
URL = ("https://physionet.org/static/published-projects/mimic-iv-demo-omop/"
       "mimic-iv-demo-data-in-the-omop-common-data-model-0.9.zip")


def load_mimic() -> duckdb.DuckDBPyConnection:
    """MIMIC-IV demo OMOP CSV 를 내려받아(없으면) 메모리 DuckDB 에 테이블로 올린다."""
    MIMIC_DIR.mkdir(parents=True, exist_ok=True)
    if not ZIP_PATH.exists():
        print("MIMIC-IV demo OMOP 다운로드 중 (약 10MB)...")
        urlretrieve(URL, ZIP_PATH)
    extract_dir = MIMIC_DIR / "extracted"
    if not extract_dir.exists():
        with zipfile.ZipFile(ZIP_PATH) as z:
            z.extractall(extract_dir)

    con = duckdb.connect()
    for csv in sorted(extract_dir.glob("*/1_omop_data_csv/*.csv")):
        # 파일명 '2b_concept.csv' → 테이블명 'concept' (배포본의 접두어 제거)
        table = re.sub(r"^2b_", "", csv.stem)
        # sample_size=-1 : 파일 전체를 읽고 컬럼 타입을 추론 (앞부분만 보면 타입을 잘못 잡을 수 있음)
        con.execute(f"CREATE TABLE {table} AS "
                    f"SELECT * FROM read_csv_auto('{csv.as_posix()}', sample_size=-1)")
    return con


def profile(con: duckdb.DuckDBPyConnection) -> dict:
    """DB 하나의 '분석 가능성' 지표를 뽑는다. 두 DB 에 같은 SQL 을 쓴다."""
    one = lambda sql: con.execute(sql).fetchone()[0]
    return {
        "환자 수": one("SELECT COUNT(*) FROM person"),
        "CDM 버전": one("SELECT cdm_version FROM cdm_source"),
        "관찰기간 중앙값 (일)": one(
            "SELECT MEDIAN(DATEDIFF('day', observation_period_start_date, observation_period_end_date)) "
            "FROM observation_period op WHERE EXISTS (SELECT 1 FROM person p WHERE p.person_id = op.person_id)"),
        "방문 유형 종류 수": one("SELECT COUNT(DISTINCT visit_concept_id) FROM visit_occurrence"),
        "환자당 처방 건수 (평균)": round(one(
            "SELECT 1.0 * COUNT(*) / COUNT(DISTINCT person_id) FROM drug_exposure"), 1),
        "환자당 검사 건수 (평균)": round(one(
            "SELECT 1.0 * COUNT(*) / COUNT(DISTINCT person_id) FROM measurement"), 1),
        "검사 수치값 채움률 (%)": round(one(
            "SELECT 100.0 * COUNT(value_as_number) / COUNT(*) FROM measurement"), 1),
        "처방-방문 연결률 (%)": round(one(
            "SELECT 100.0 * COUNT(v.visit_occurrence_id) / COUNT(*) FROM drug_exposure de "
            "LEFT JOIN visit_occurrence v ON v.visit_occurrence_id = de.visit_occurrence_id"), 1),
        "사망 기록 환자 수": one("SELECT COUNT(DISTINCT person_id) FROM death"),
        "진단 concept 이름 조인 성공률 (%)": round(one(
            "SELECT 100.0 * COUNT(c.concept_id) / COUNT(*) FROM condition_occurrence co "
            "LEFT JOIN concept c ON c.concept_id = co.condition_concept_id"), 1),
        "concept_ancestor 사용 가능": "예" if _has_rows(con, "concept_ancestor") else "아니오",
    }


def _has_rows(con, table) -> bool:
    try:
        return con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0] > 0
    except duckdb.Error:
        return False


if __name__ == "__main__":
    dbs = {"Eunomia GiBleed (합성)": connect(), "MIMIC-IV demo (실제·비식별)": load_mimic()}

    # (1) 같은 .sql 파일을 두 DB 에 그대로 실행
    same_sql = (ROOT / "sql" / "01_basic" / "b01_table_row_counts.sql").read_text(encoding="utf-8")
    counts = None
    for name, con in dbs.items():
        df = con.execute(same_sql).df().set_index("table_name")
        df.columns = pd.MultiIndex.from_product([[name], df.columns])
        counts = df if counts is None else counts.join(df)
    print("[같은 SQL(b01) 을 두 DB 에 실행]\n", counts.to_string(), "\n")

    # 환자당 1행 요약 쿼리(i02)도 두 DB 모두에서 '환자 수 = 결과 행 수' 인지 확인
    i02 = (ROOT / "sql" / "02_intermediate" / "i02_patient_summary_avoid_fanout.sql").read_text(encoding="utf-8")
    for name, con in dbs.items():
        n_rows = len(con.execute(i02).fetchall())
        n_person = con.execute("SELECT COUNT(*) FROM person").fetchone()[0]
        assert n_rows == n_person, f"{name}: 행 수 불일치"
        print(f"i02 검증 통과 — {name}: {n_rows:,}행 = 환자 수")

    # (2) 분석 가능성 프로파일 비교
    prof = pd.DataFrame({name: profile(con) for name, con in dbs.items()})
    prof.index.name = "지표"
    out = ROOT / "results" / "tables" / "mimic_vs_eunomia_profile.csv"
    prof.to_csv(out, encoding="utf-8-sig")
    print("\n[두 DB 의 분석 가능성 비교]\n", prof.to_string())
    print(f"\n저장: {out.relative_to(ROOT)}")
