"""
run_sql.py — sql/ 폴더의 모든 쿼리를 순서대로 실행하고 결과를 CSV로 저장한다.

실행:  python src/run_sql.py        (프로젝트 루트에서)

설계 메모 (왜 이렇게 했는지)
- SQL 은 .sql 파일에만 둔다. 파이썬 문자열 안에 SQL 을 넣지 않는다.
  → SQL 파일만 열어 봐도 분석 로직 전체를 읽을 수 있고, DB 클라이언트(DBeaver 등)에
    그대로 붙여 넣어 실행할 수 있다.
- 파일 하나 = SQL 문장 하나. 파일명 순서 = 실행 순서.
- 원본 CDM 은 읽기 전용(READ_ONLY)으로 연결한다. 실수로 원본을 바꾸는 일을 원천 차단.
  코호트 같은 중간 산출물은 별도 'work' 스키마(메모리)에 만든다.
  실제 병원 환경도 똑같다: CDM 스키마는 읽기 권한만, 결과는 본인 results 스키마에 쓴다.
"""
from pathlib import Path
import sys

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "data" / "eunomia_gibleed.duckdb"
SQL_DIR = ROOT / "sql"
OUT_DIR = ROOT / "results" / "tables"


def connect(db_path: Path = DB_PATH) -> duckdb.DuckDBPyConnection:
    """CDM(읽기 전용) + work(메모리, 쓰기 가능) 두 저장소를 붙인 연결을 돌려준다."""
    if not db_path.exists():
        sys.exit(f"DB 파일이 없습니다: {db_path}\n먼저 `Rscript R/01_setup_eunomia.R` 를 실행하세요.")
    con = duckdb.connect()  # 메모리 DB 로 시작
    con.execute(f"ATTACH '{db_path.as_posix()}' AS cdm (READ_ONLY)")
    con.execute("ATTACH ':memory:' AS work")
    con.execute("USE cdm")  # 이후 person, drug_exposure 처럼 스키마 이름 없이 쓰면 CDM 을 가리킨다
    return con


def run_all(con: duckdb.DuckDBPyConnection, save: bool = True) -> dict:
    """sql/ 아래 모든 .sql 을 경로 순으로 실행. SELECT 결과는 DataFrame 으로 모아 돌려준다."""
    results = {}
    if save:
        OUT_DIR.mkdir(parents=True, exist_ok=True)
    for path in sorted(SQL_DIR.rglob("*.sql")):
        sql = path.read_text(encoding="utf-8")
        # 주석(-- ...)을 걷어낸 뒤 첫 단어가 CREATE 면 "테이블을 만드는 문장"이다.
        body = "\n".join(line for line in sql.splitlines() if not line.strip().startswith("--"))
        if body.strip().upper().startswith("CREATE"):
            con.execute(sql)
            print(f"[실행] {path.relative_to(ROOT)}  (테이블 생성)")
            continue
        df = con.execute(sql).df()
        results[path.stem] = df
        print(f"[실행] {path.relative_to(ROOT)}  → {len(df):,}행")
        if save:
            df.to_csv(OUT_DIR / f"{path.stem}.csv", index=False, encoding="utf-8-sig")
    return results


if __name__ == "__main__":
    con = connect()
    res = run_all(con)

    # ---- 자동 검증(sanity check): 틀린 숫자가 조용히 나가지 않도록 ----
    n_person = con.execute("SELECT COUNT(*) FROM person").fetchone()[0]
    # (1) 환자 요약은 환자당 정확히 1행이어야 한다 (조인 뻥튀기 없음)
    assert len(res["i02_patient_summary_avoid_fanout"]) == n_person
    # (2) 코호트에 같은 환자가 두 번 들어가면 안 된다
    dup = con.execute("SELECT COUNT(*) - COUNT(DISTINCT subject_id) FROM work.cohort").fetchone()[0]
    assert dup == 0
    # (3) 특성표·결과표 행 수 = 코호트 인원
    n_cohort = con.execute("SELECT COUNT(*) FROM work.cohort").fetchone()[0]
    assert len(res["c04_baseline_characteristics"]) == n_cohort
    assert len(res["c06_outcome_time_to_event"]) == n_cohort
    # (4) 탈락 흐름표의 마지막 숫자 = 코호트 인원
    assert int(res["c02_cohort_attrition"]["n_remaining"].iloc[-1]) == n_cohort
    print(f"\n검증 통과: person {n_person:,}명, 최종 코호트 {n_cohort:,}명")
