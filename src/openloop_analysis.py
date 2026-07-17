"""OpenLoop synthetic dataset KPI analysis.

Run from the repository root:
    python src/openloop_analysis.py
"""
from __future__ import annotations

from pathlib import Path
import sys
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data" / "csv"
OUTPUT_DIR = ROOT / "outputs"


def load_tables() -> dict[str, pd.DataFrame]:
    required = {
        "departments": "departments.csv",
        "employees": "employees.csv",
        "sources": "sources.csv",
        "conversations": "conversations.csv",
        "messages": "messages.csv",
        "promises": "promises.csv",
        "promise_history": "promise_history.csv",
        "notifications": "notifications.csv",
    }
    missing = [name for name in required.values() if not (DATA_DIR / name).exists()]
    if missing:
        raise FileNotFoundError(f"Missing required data files: {', '.join(missing)}")

    tables = {name: pd.read_csv(DATA_DIR / filename) for name, filename in required.items()}
    for col in ["created_ts", "due_ts", "completed_ts"]:
        tables["promises"][col] = pd.to_datetime(tables["promises"][col], errors="coerce")
    for col in ["conversation_start_ts", "last_activity_ts"]:
        tables["conversations"][col] = pd.to_datetime(tables["conversations"][col], errors="coerce")
    return tables


def validate_relationships(t: dict[str, pd.DataFrame]) -> pd.DataFrame:
    checks = []

    def add_check(name: str, passed: bool, detail: str) -> None:
        checks.append({"check": name, "passed": bool(passed), "detail": detail})

    for table_name, key in [
        ("departments", "department_id"),
        ("employees", "employee_id"),
        ("sources", "source_id"),
        ("conversations", "conversation_id"),
        ("messages", "message_id"),
        ("promises", "promise_id"),
        ("promise_history", "history_id"),
        ("notifications", "notification_id"),
    ]:
        duplicates = int(t[table_name][key].duplicated().sum())
        add_check(f"{table_name}.{key} uniqueness", duplicates == 0, f"duplicate rows={duplicates}")

    fk_checks = [
        ("employees.department_id", t["employees"]["department_id"], t["departments"]["department_id"]),
        ("conversations.source_id", t["conversations"]["source_id"], t["sources"]["source_id"]),
        ("messages.conversation_id", t["messages"]["conversation_id"], t["conversations"]["conversation_id"]),
        ("promises.message_id", t["promises"]["message_id"], t["messages"]["message_id"]),
        ("promises.owner_employee_id", t["promises"]["owner_employee_id"], t["employees"]["employee_id"]),
        ("promise_history.promise_id", t["promise_history"]["promise_id"], t["promises"]["promise_id"]),
        ("notifications.promise_id", t["notifications"]["promise_id"], t["promises"]["promise_id"]),
    ]
    for name, child, parent in fk_checks:
        invalid = int((~child.dropna().isin(parent)).sum())
        add_check(f"{name} referential integrity", invalid == 0, f"invalid references={invalid}")

    p = t["promises"]
    invalid_dates = int((p["due_ts"] < p["created_ts"]).sum())
    add_check("Promise due date follows creation", invalid_dates == 0, f"invalid rows={invalid_dates}")
    return pd.DataFrame(checks)


def calculate_kpis(t: dict[str, pd.DataFrame]) -> pd.DataFrame:
    p = t["promises"].copy()
    c = t["conversations"]
    n = t["notifications"]
    fulfilled = p[p["current_status"].eq("Fulfilled")].copy()
    fulfilled["resolution_hours"] = (
        fulfilled["completed_ts"] - fulfilled["created_ts"]
    ).dt.total_seconds() / 3600

    metrics = [
        ("Total promises", len(p), "count"),
        ("Promise fulfillment rate", p["current_status"].eq("Fulfilled").mean(), "percent"),
        ("Broken/overdue promise rate", p["current_status"].eq("Overdue").mean(), "percent"),
        ("Average resolution time", fulfilled["resolution_hours"].mean(), "hours"),
        ("Ownership reassignment rate", p["current_status"].eq("Reassigned").mean(), "percent"),
        ("Escalation rate", p["current_status"].eq("Escalated").mean(), "percent"),
        ("SLA compliance among fulfilled", (fulfilled["completed_ts"] <= fulfilled["due_ts"]).mean(), "percent"),
        ("Dormant conversation rate", c["conversation_status"].eq("Dormant").mean(), "percent"),
        ("Notification failure rate", n["delivery_status"].eq("Failed").mean(), "percent"),
        ("Human confirmation rate", p["is_human_confirmed"].mean(), "percent"),
        ("Average AI confidence", p["ai_confidence_score"].mean(), "score"),
        ("Average promise risk", p["risk_score"].mean(), "score"),
    ]
    return pd.DataFrame(metrics, columns=["metric", "value", "unit"])


def department_performance(t: dict[str, pd.DataFrame]) -> pd.DataFrame:
    p = t["promises"].merge(
        t["departments"][["department_id", "department_name"]],
        left_on="owner_department_id",
        right_on="department_id",
        how="left",
    )
    summary = p.groupby("department_name", as_index=False).agg(
        total_promises=("promise_id", "count"),
        fulfilled_promises=("current_status", lambda s: int(s.eq("Fulfilled").sum())),
        overdue_promises=("current_status", lambda s: int(s.eq("Overdue").sum())),
        escalated_promises=("current_status", lambda s: int(s.eq("Escalated").sum())),
        average_risk_score=("risk_score", "mean"),
    )
    summary["fulfillment_rate"] = summary["fulfilled_promises"] / summary["total_promises"]
    summary["overdue_rate"] = summary["overdue_promises"] / summary["total_promises"]
    return summary.sort_values(["fulfillment_rate", "average_risk_score"], ascending=[False, True])


def format_value(value: float, unit: str) -> str:
    if unit == "percent": return f"{value:.1%}"
    if unit == "hours": return f"{value:.1f} hours"
    if unit == "score": return f"{value:.3f}"
    return f"{int(value):,}"


def main() -> int:
    try:
        tables = load_tables()
        checks = validate_relationships(tables)
        kpis = calculate_kpis(tables)
        departments = department_performance(tables)
        OUTPUT_DIR.mkdir(exist_ok=True)
        checks.to_csv(OUTPUT_DIR / "data_quality_checks.csv", index=False)
        kpis.to_csv(OUTPUT_DIR / "kpi_summary.csv", index=False)
        departments.to_csv(OUTPUT_DIR / "department_performance.csv", index=False)

        print("OPENLOOP KPI SUMMARY")
        print("=" * 60)
        for row in kpis.itertuples(index=False):
            print(f"{row.metric:<38} {format_value(row.value, row.unit):>20}")
        print("\nDATA QUALITY")
        print("=" * 60)
        print(checks.to_string(index=False))
        print("\nDEPARTMENT PERFORMANCE")
        print("=" * 60)
        display_cols = ["department_name", "total_promises", "fulfillment_rate", "overdue_rate", "average_risk_score"]
        print(departments[display_cols].to_string(index=False, formatters={
            "fulfillment_rate": "{:.1%}".format,
            "overdue_rate": "{:.1%}".format,
            "average_risk_score": "{:.3f}".format,
        }))
        print(f"\nOutputs written to: {OUTPUT_DIR}")
        return 0 if checks["passed"].all() else 2
    except Exception as exc:
        print(f"Analysis failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
