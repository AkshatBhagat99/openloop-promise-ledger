# Power BI Build Guide

## Data Source

Import `data/OpenLoop_Enterprise_Dataset.xlsx` or the CSV tables in `data/csv/`.

## Model Relationships

- `departments[department_id]` 1 → * `employees[department_id]`
- `departments[department_id]` 1 → * `conversations[department_id]`
- `departments[department_id]` 1 → * `promises[owner_department_id]`
- `sources[source_id]` 1 → * `conversations[source_id]`
- `conversations[conversation_id]` 1 → * `messages[conversation_id]`
- `conversations[conversation_id]` 1 → * `promises[conversation_id]`
- `messages[message_id]` 1 → * `promises[message_id]`
- `employees[employee_id]` 1 → * `promises[owner_employee_id]`
- `promises[promise_id]` 1 → * `promise_history[promise_id]`
- `promises[promise_id]` 1 → * `notifications[promise_id]`
- `calendar[calendar_date]` 1 → * `promises[created_date]` using a derived date column

## Recommended Measures

```DAX
Total Promises = COUNTROWS(promises)

Fulfilled Promises =
CALCULATE([Total Promises], promises[current_status] = "Fulfilled")

Promise Fulfillment Rate =
DIVIDE([Fulfilled Promises], [Total Promises])

Overdue Promises =
CALCULATE([Total Promises], promises[current_status] = "Overdue")

Broken Promise Rate =
DIVIDE([Overdue Promises], [Total Promises])

Escalated Promises =
CALCULATE([Total Promises], promises[current_status] = "Escalated")

Escalation Rate =
DIVIDE([Escalated Promises], [Total Promises])

Reassigned Promises =
CALCULATE([Total Promises], promises[current_status] = "Reassigned")

Reassignment Rate =
DIVIDE([Reassigned Promises], [Total Promises])

Average Risk Score = AVERAGE(promises[risk_score])
Average AI Confidence = AVERAGE(promises[ai_confidence_score])

Average Resolution Hours =
AVERAGEX(
    FILTER(promises, NOT ISBLANK(promises[completed_ts])),
    DATEDIFF(promises[created_ts], promises[completed_ts], HOUR)
)

SLA Compliant Fulfilled =
CALCULATE(
    [Total Promises],
    FILTER(
        promises,
        promises[current_status] = "Fulfilled" &&
        promises[completed_ts] <= promises[due_ts]
    )
)

SLA Compliance Rate =
DIVIDE([SLA Compliant Fulfilled], [Fulfilled Promises])
```

## Page 1 — Executive Overview

KPI cards: Total Promises, Fulfillment Rate, Broken Promise Rate, SLA Compliance, Average Resolution Hours, Escalation Rate.

Visuals:
- Monthly promise trend
- Status distribution
- Department fulfillment heatmap
- Aging distribution
- High-risk open commitments table

Filters: date, department, source, priority, status.

## Page 2 — Department Performance

- Department ranking by fulfillment rate
- Overdue promises by department
- Average risk and resolution time
- Ownership reassignment rate
- SLA compliance trend
- Drill-through to Promise Operations

## Page 3 — Promise Operations

Table fields:
- Promise ID
- Promise text
- Owner
- Department
- Source
- Created date
- Due date
- Status
- Priority
- Risk score
- AI confidence

Add conditional formatting for overdue status, high risk, and approaching due date.

## Page 4 — Risk and SLA

- Risk-score distribution
- High-risk promises by source and department
- Overdue aging buckets
- Escalation trend
- SLA breaches by priority
- Notification delivery outcomes

## Interaction Design

- Enable drill-through from department to promise-level detail.
- Add report-page tooltips with lifecycle and evidence context.
- Use bookmarks for Executive and Operational views.
- Apply row-level security by department for a production-style demonstration.
- Include an information tooltip stating that the dataset is synthetic.
