"""
analyze_cohort.py — SQL 로 뽑은 코호트를 요약(Table 1)하고 그림을 그린다.

실행:  python src/analyze_cohort.py      (프로젝트 루트에서)

역할 분담과 그 이유
- 코호트 구성원과 변수 정의는 전부 SQL(sql/03_cohort)이 결정한다.
- 파이썬은 SQL 결과(환자당 1행 테이블)를 받아 통계 요약과 시각화만 한다.
  → 데이터 추출 로직이 한 곳(SQL)에만 있어야 검증·재현이 쉽다.

산출물
- results/tables/table1_baseline.csv        기저 특성표 + 표준화 평균차(SMD)
- results/tables/stratified_incidence.csv   소화성 궤양 과거력으로 층화한 발생률
- results/figures/fig1~fig5 *.png
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # 화면 없이 파일로만 저장
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from run_sql import connect, run_all, ROOT

FIG_DIR = ROOT / "results" / "figures"
TAB_DIR = ROOT / "results" / "tables"

# ---- 그림 공통 스타일 -------------------------------------------------------
# 색은 "약물(집단)"에 고정한다: 어느 그림에서든 celecoxib=파랑, diclofenac=주황.
# 그림마다 색이 바뀌면 읽는 사람이 범례를 매번 다시 확인해야 한다.
COLORS = {"celecoxib": "#2a78d6", "diclofenac": "#eb6834"}
COHORTS = ["celecoxib", "diclofenac"]
INK, MUTED, GRID = "#0b0b0b", "#52514e", "#e4e3df"

plt.rcParams.update({
    "font.family": "Malgun Gothic",      # 한글 글꼴(윈도우 기본). 없으면 한글이 깨진다.
    "axes.unicode_minus": False,         # 음수 부호 깨짐 방지
    "figure.facecolor": "#fcfcfb", "axes.facecolor": "#fcfcfb", "savefig.facecolor": "#fcfcfb",
    "axes.edgecolor": GRID, "axes.labelcolor": MUTED, "text.color": INK,
    "xtick.color": MUTED, "ytick.color": MUTED,
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "axes.axisbelow": True, "font.size": 10.5, "axes.titlesize": 12.5,
    "axes.titleweight": "bold", "axes.titlelocation": "left",
})


def save(fig, name):
    fig.savefig(FIG_DIR / name, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print(f"[그림] results/figures/{name}")


# =============================================================================
# 통계 함수
# =============================================================================
def smd(x1: pd.Series, x2: pd.Series, binary: bool) -> float:
    """표준화 평균차(Standardized Mean Difference).

    두 집단의 차이를 표준편차 단위로 나타낸 값.
    - p-value 는 표본이 크면 사소한 차이에도 작아지지만, SMD 는 표본 크기와 무관하다.
      그래서 RWE 연구에서는 집단 간 균형을 p-value 가 아닌 SMD 로 본다.
    - 관례: |SMD| > 0.1 이면 "의미 있는 불균형"(교란 가능성)으로 판단.
    """
    m1, m2 = x1.mean(), x2.mean()
    if binary:   # 0/1 변수: 분산 = p(1-p)
        v1, v2 = m1 * (1 - m1), m2 * (1 - m2)
    else:        # 연속 변수: 표본분산
        v1, v2 = x1.var(ddof=1), x2.var(ddof=1)
    pooled_sd = np.sqrt((v1 + v2) / 2)
    return 0.0 if pooled_sd == 0 else (m1 - m2) / pooled_sd


def kaplan_meier(time: np.ndarray, event: np.ndarray) -> pd.DataFrame:
    """Kaplan-Meier 추정으로 누적 발생률(1 - 생존확률)을 계산한다.

    단순 비율(사건 수 / 환자 수) 대신 KM 을 쓰는 이유
    - 추적이 중간에 끝난 환자(중도절단: 관찰기간 종료)는 "그 시점까지는 사건이 없었다"는
      정보만 준다. KM 은 각 시점에서 '아직 추적 중인 사람(risk set)'만 분모로 써서
      이 정보를 버리지도, 과대평가하지도 않는다.
    - 원리: S(t) = Π (1 - d_i / n_i)   (d_i = t_i 시점 사건 수, n_i = t_i 직전 추적 중 인원)
    라이브러리(lifelines) 대신 직접 구현한 이유: 원리를 설명할 수 있도록.
    """
    df = pd.DataFrame({"t": time, "e": event})
    grouped = df.groupby("t")["e"].agg(d="sum", n_leave="size").sort_index()
    at_risk = len(df) - grouped["n_leave"].cumsum().shift(fill_value=0)   # 각 시점 직전 추적 인원
    surv = (1 - grouped["d"] / at_risk).cumprod()
    out = pd.DataFrame({"t": grouped.index, "cum_inc": 1 - surv.values, "at_risk": at_risk.values})
    return pd.concat([pd.DataFrame({"t": [0], "cum_inc": [0.0], "at_risk": [len(df)]}), out],
                     ignore_index=True)


# =============================================================================
# 메인
# =============================================================================
def main():
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    con = connect()
    res = run_all(con, save=True)

    base = res["c04_baseline_characteristics"]          # 환자당 1행: 기저 특성
    tte = res["c06_outcome_time_to_event"]              # 환자당 1행: 사건 여부, 추적 일수
    attr = res["c02_cohort_attrition"]
    df = base.merge(tte[["subject_id", "event", "time_days"]], on="subject_id", validate="1:1")
    g = {c: df[df["cohort_name"] == c] for c in COHORTS}

    # -------------------------------------------------------------------------
    # Table 1: 기저 특성 + SMD
    # -------------------------------------------------------------------------
    cont = {"age_at_index": "지표일 연령 (세)",
            "n_distinct_prior_conditions": "과거 진단 종류 수",
            "prior_obs_days": "지표일 이전 관찰 일수"}
    binary = {"is_female": "여성",
              "prior_peptic_ulcer": "과거력: 소화성 궤양",
              "prior_ulcerative_colitis": "과거력: 궤양성 대장염",
              "prior_esophagitis": "과거력: 식도염",
              "prior_angiodysplasia_stomach": "과거력: 위 혈관이형성",
              "prior_colon_polyp": "과거력: 대장 용종",
              "prior_aspirin": "365일 내 아스피린",
              "prior_ibuprofen": "365일 내 이부프로펜",
              "prior_naproxen": "365일 내 나프록센",
              "prior_acetaminophen": "365일 내 아세트아미노펜"}
    rows = [{"특성": "환자 수 (N)", **{c: f"{len(g[c]):,}" for c in COHORTS}, "SMD": ""}]
    for col, label in cont.items():       # 연속 변수: 평균 ± 표준편차
        rows.append({"특성": label + ", 평균 ± SD",
                     **{c: f"{g[c][col].mean():.1f} ± {g[c][col].std():.1f}" for c in COHORTS},
                     "SMD": round(smd(g["celecoxib"][col], g["diclofenac"][col], False), 3)})
    for col, label in binary.items():     # 이분 변수: n (%)
        rows.append({"특성": label + ", n (%)",
                     **{c: f"{int(g[c][col].sum()):,} ({100 * g[c][col].mean():.1f}%)" for c in COHORTS},
                     "SMD": round(smd(g["celecoxib"][col], g["diclofenac"][col], True), 3)})
    table1 = pd.DataFrame(rows)
    table1.to_csv(TAB_DIR / "table1_baseline.csv", index=False, encoding="utf-8-sig")
    print("\n[Table 1] 기저 특성\n", table1.to_string(index=False))

    # -------------------------------------------------------------------------
    # Fig 1. 탈락 흐름 (단일 계열 → 범례 불필요, 값은 막대 끝에 직접 표기)
    # -------------------------------------------------------------------------
    fig, ax = plt.subplots(figsize=(8.6, 3.6))
    a = attr.iloc[::-1]
    ax.barh(a["criterion"], a["n_remaining"], color="#2a78d6", height=0.55)
    for y, (n, ex) in enumerate(zip(a["n_remaining"], a["n_excluded_at_step"])):
        note = f"{int(n):,}명" + (f"  ({int(ex)}명 제외)" if ex > 0 else "")
        ax.text(n + 25, y, note, va="center", fontsize=9.5, color=INK)
    ax.set_xlim(0, attr["n_remaining"].max() * 1.28)
    ax.set_xlabel("남은 환자 수")
    ax.grid(axis="y", visible=False)
    ax.set_title("그림 1. 코호트 선정 흐름: 기준을 순서대로 적용했을 때 남는 환자 수")
    save(fig, "fig1_attrition.png")

    # -------------------------------------------------------------------------
    # Fig 2. 지표일 연령 분포 (두 집단 크기가 달라서 '명'이 아닌 '비율'로 비교)
    # -------------------------------------------------------------------------
    fig, axes = plt.subplots(1, 2, figsize=(9.2, 3.5), sharey=True, sharex=True)
    ages = np.arange(df["age_at_index"].min(), df["age_at_index"].max() + 1)
    for ax, c in zip(axes, COHORTS):
        pct = g[c]["age_at_index"].value_counts(normalize=True).reindex(ages, fill_value=0) * 100
        ax.bar(ages, pct, color=COLORS[c], width=0.8)
        ax.axvline(g[c]["age_at_index"].mean(), color=INK, lw=1, ls="--")
        ax.set_title(f"{c}  (N={len(g[c]):,}, 평균 {g[c]['age_at_index'].mean():.1f}세)",
                     fontsize=11, fontweight="normal")
        ax.set_xlabel("지표일 연령 (세)")
        ax.grid(axis="x", visible=False)
    axes[0].set_ylabel("집단 내 비율 (%)")
    fig.suptitle("그림 2. 지표일 연령 분포는 두 집단이 거의 같다", x=0.01, ha="left",
                 fontweight="bold", fontsize=12.5)
    fig.tight_layout()
    save(fig, "fig2_age_distribution.png")

    # -------------------------------------------------------------------------
    # Fig 3. 기저 특성 균형 (집단별 유병률 점 그림 + SMD)
    #   같은 특성의 두 점이 멀수록 불균형. 오른쪽 숫자가 |SMD| > 0.1 이면 주의.
    # -------------------------------------------------------------------------
    labels = list(binary.values())
    cols = list(binary.keys())
    fig, ax = plt.subplots(figsize=(8.6, 4.6))
    ypos = np.arange(len(cols))[::-1]
    for y, col in zip(ypos, cols):
        p = [100 * g[c][col].mean() for c in COHORTS]
        ax.plot(p, [y, y], color=GRID, lw=2, zorder=1)        # 두 점을 잇는 선 = 차이의 크기
        s = smd(g["celecoxib"][col], g["diclofenac"][col], True)
        ax.text(62, y, f"{s:+.2f}", va="center", ha="right", fontsize=9.5,
                color=INK, fontweight="bold" if abs(s) > 0.1 else "normal")
    for c in COHORTS:
        ax.scatter([100 * g[c][col].mean() for col in cols], ypos, s=64, color=COLORS[c],
                   edgecolor="#fcfcfb", linewidth=1.5, zorder=3, label=c)
    ax.text(62, len(cols) - 0.35, "SMD", ha="right", fontsize=9.5, color=MUTED)
    ax.set_yticks(ypos, labels)
    ax.set_xlim(-2, 63)
    ax.set_xlabel("집단 내 해당 환자 비율 (%)")
    ax.grid(axis="y", visible=False)
    ax.legend(frameon=False, loc="lower right", bbox_to_anchor=(0.9, 0.02))
    ax.set_title("그림 3. 기저 특성 비교: celecoxib 군에 위장관 질환 과거력이 2배 이상 많다\n"
                 "(굵은 SMD = |SMD| > 0.1, 집단 간 불균형)", fontsize=11.5)
    save(fig, "fig3_baseline_balance.png")

    # -------------------------------------------------------------------------
    # Fig 4. 위장관 출혈 누적 발생률 (Kaplan-Meier)
    # -------------------------------------------------------------------------
    fig, ax = plt.subplots(figsize=(8.2, 4.2))
    for c in COHORTS:
        km = kaplan_meier(g[c]["time_days"].to_numpy(), g[c]["event"].to_numpy())
        ax.step(km["t"], 100 * km["cum_inc"], where="post", color=COLORS[c], lw=2)
        ax.text(372, 100 * km["cum_inc"].iloc[-1], f"{c}\n{100 * km['cum_inc'].iloc[-1]:.1f}%",
                color=INK, va="center", fontsize=9.5)       # 선 끝에 직접 라벨
        ax.plot([], [], color=COLORS[c], lw=2, label=f"{c} (N={len(g[c]):,})")
    ax.set_xlim(0, 430)
    ax.set_xticks([0, 30, 90, 180, 270, 365])
    ax.set_ylim(0, None)
    ax.set_xlabel("지표일(첫 처방) 이후 일수")
    ax.set_ylabel("위장관 출혈 누적 발생률 (%)")
    ax.legend(frameon=False, loc="lower right", bbox_to_anchor=(0.85, 0.05))
    ax.set_title("그림 4. Kaplan-Meier 누적 발생률(보정 전): 출혈은 모두 처방 후 90일 안에 발생")
    save(fig, "fig4_cumulative_incidence.png")

    # -------------------------------------------------------------------------
    # 층화 분석: 소화성 궤양 과거력 유무로 나눠서 다시 비교
    #   그림 3 에서 가장 불균형이 컸던 변수(=교란 의심 변수)로 층을 나눈다.
    # -------------------------------------------------------------------------
    df["stratum"] = np.where(df["prior_peptic_ulcer"] == 1, "궤양 과거력 있음", "궤양 과거력 없음")
    strat = (df.groupby(["stratum", "cohort_name"])["event"]
               .agg(n_persons="size", n_events="sum").reset_index())
    overall = (df.assign(stratum="전체 (보정 전)").groupby(["stratum", "cohort_name"])["event"]
                 .agg(n_persons="size", n_events="sum").reset_index())
    strat = pd.concat([overall, strat], ignore_index=True)
    strat["risk_pct"] = (100 * strat["n_events"] / strat["n_persons"]).round(1)
    # 위험도비(Risk Ratio, RR) = celecoxib 누적 발생률 / diclofenac 누적 발생률  (1 보다 크면 celecoxib 쪽이 높음)
    #   - 반올림한 백분율이 아니라 사건 수·환자 수 원값으로 계산한다.
    #   - 95% 신뢰구간: log(RR) 의 정규근사. SE = sqrt(1/a - 1/n1 + 1/c - 1/n0)
    #   - Cox 모형의 위험비(Hazard Ratio)와는 다른 지표다. 여기서는 1년 누적 발생률의 비만 본다.
    ev = strat.pivot(index="stratum", columns="cohort_name", values="n_events")
    n = strat.pivot(index="stratum", columns="cohort_name", values="n_persons")
    rr = (ev["celecoxib"] / n["celecoxib"]) / (ev["diclofenac"] / n["diclofenac"])
    se = np.sqrt(1 / ev["celecoxib"] - 1 / n["celecoxib"] + 1 / ev["diclofenac"] - 1 / n["diclofenac"])
    strat["risk_ratio_cele_vs_diclo"] = strat["stratum"].map(rr.round(2))
    strat["rr_ci95_low"] = strat["stratum"].map(np.exp(np.log(rr) - 1.96 * se).round(2))
    strat["rr_ci95_high"] = strat["stratum"].map(np.exp(np.log(rr) + 1.96 * se).round(2))
    strat.to_csv(TAB_DIR / "stratified_incidence.csv", index=False, encoding="utf-8-sig")
    print("\n[층화 분석]\n", strat.to_string(index=False))

    # Mantel-Haenszel 공통 위험도비: 층(궤양 과거력 유무)을 고정한 채 두 약을 비교한 요약값.
    #   보정 전 RR 과 비교하면 '궤양 과거력' 하나가 차이를 얼마나 설명하는지 볼 수 있다.
    #   단, 두 층의 RR 방향이 반대이므로(효과 변경) 하나의 값으로 요약하는 데에는 한계가 있다.
    layers = [s for s in rr.index if s != "전체 (보정 전)"]
    tot = n.loc[layers].sum(axis=1)
    mh = ((ev.loc[layers, "celecoxib"] * n.loc[layers, "diclofenac"] / tot).sum()
          / (ev.loc[layers, "diclofenac"] * n.loc[layers, "celecoxib"] / tot).sum())
    pd.DataFrame([{"measure": "crude_risk_ratio", "value": round(float(rr["전체 (보정 전)"]), 3)},
                  {"measure": "mantel_haenszel_risk_ratio_by_prior_peptic_ulcer", "value": round(float(mh), 3)}]
                 ).to_csv(TAB_DIR / "risk_ratio_summary.csv", index=False, encoding="utf-8-sig")
    print(f"\n보정 전 RR {rr['전체 (보정 전)']:.2f} → 궤양 과거력 층화 Mantel-Haenszel RR {mh:.2f}")

    # Fig 5. 층화 발생률 (집단 2개 → 묶은 막대, 값 직접 표기)
    order = ["전체 (보정 전)", "궤양 과거력 없음", "궤양 과거력 있음"]
    fig, ax = plt.subplots(figsize=(8.2, 4.2))
    w = 0.36
    for i, c in enumerate(COHORTS):
        s = strat[strat["cohort_name"] == c].set_index("stratum").loc[order]
        x = np.arange(len(order)) + (i - 0.5) * (w + 0.03)
        ax.bar(x, s["risk_pct"], width=w, color=COLORS[c], label=c)
        for xi, (r, e, n) in zip(x, zip(s["risk_pct"], s["n_events"], s["n_persons"])):
            ax.text(xi, r + 0.7, f"{r:.1f}%\n({int(e)}/{int(n):,})", ha="center", fontsize=9, color=INK)
    ax.set_xticks(np.arange(len(order)), order)
    ax.set_ylim(0, strat["risk_pct"].max() * 1.25)
    ax.set_ylabel("1년 내 위장관 출혈 발생률 (%)")
    ax.grid(axis="x", visible=False)
    ax.legend(frameon=False, loc="upper left")
    ax.set_title("그림 5. 궤양 과거력으로 층화하면 결과가 달라진다\n"
                 "(과거력 없는 층에서는 celecoxib 가 오히려 낮음)", fontsize=11.5)
    save(fig, "fig5_stratified_incidence.png")


if __name__ == "__main__":
    main()
