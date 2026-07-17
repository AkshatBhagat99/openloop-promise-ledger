# Resume and Interview Guide

## Resume Entry — Balanced BA/Data Analyst Version

**OPENLOOP — AI-Powered Promise Ledger & Conversation Intelligence Platform**  
*Independent Business Analysis and Data Analytics Project | PostgreSQL, SQL Server, Power BI, Excel, Python, Jira*

- Designed an end-to-end enterprise SaaS case study for a modeled 3,500-user rollout, translating an unstructured commitment-tracking problem into 18 business requirements, 45 functional and non-functional requirements, 24 user stories, and 30 traceable test cases.
- Built a relational synthetic dataset containing 1,168 interconnected records and developed 90 SQL queries to analyze promise fulfillment, SLA compliance, commitment aging, escalations, ownership changes, and department performance.
- Created the BRD, FRD, RACI, process models, ER and star schemas, KPI definitions, dashboard specifications, UAT scenarios, and a 30-row Requirements Traceability Matrix.
- Developed a modeled business case estimating $4.06M in Year-1 benefits against $2.15M in cost, representing an 88.8% potential ROI and 6.4-month payback subject to pilot validation.

## Business Analyst Version

- Led requirements engineering for an AI-enabled commitment-management concept, producing a BRD, FRD, stakeholder matrix, RACI, business rules, process models, and implementation roadmap.
- Translated 18 business requirements into 30 functional requirements, 15 non-functional requirements, 24 INVEST-aligned user stories, and 30 UAT test cases through an end-to-end traceability matrix.
- Designed AS-IS and TO-BE workflows covering AI promise detection, owner confirmation, reassignment, dispute resolution, escalation, and fulfillment.
- Prioritized the product backlog using MoSCoW, business value, compliance risk, implementation effort, and dependency analysis.

## Data Analyst Version

- Designed a normalized enterprise dataset with 1,168 synthetic records spanning employees, conversations, messages, promises, lifecycle events, notifications, departments, and SLA reference data.
- Developed 90 PostgreSQL and SQL Server queries using CTEs, recursive CTEs, window functions, ranking, LEAD/LAG, pivots, views, stored procedures, and data-quality checks.
- Analyzed promise completion, broken commitments, resolution time, SLA compliance, ownership changes, escalations, aging, and department performance.
- Designed executive and operational Power BI dashboards with drilldowns, heatmaps, trend analysis, SLA indicators, aging distributions, and risk filters.

## Two-Minute Pitch

OpenLoop is an AI-powered Promise Ledger designed to address a common enterprise problem: critical commitments are made in Slack, Teams, email, meetings, Jira, and CRM notes, but many never become formal tasks. That creates unclear ownership, missed deadlines, duplicated follow-up, and weak execution visibility.

I approached the project as a Business Analyst and Data Analyst. I defined the business case and target operating model, identified stakeholders, created the BRD and FRD, and translated the requirements into epics, user stories, acceptance criteria, and test cases. I also designed the operational database, star schema, synthetic dataset, SQL analytics, KPI framework, dashboards, AI governance controls, UAT plan, and implementation roadmap.

One of the strongest aspects is end-to-end traceability. Every major business requirement maps to a functional requirement, story, data object, KPI, SQL rule, test case, and report. I also made deliberate governance choices, including preserving source permissions, using human review for uncertain AI outputs, and avoiding simplistic employee scoring.

The result is a realistic enterprise implementation package that demonstrates how I translate an ambiguous business problem into a measurable, governed, and testable technology solution.

## Five-Minute Demo Sequence

1. **Problem:** Commitments remain trapped in conversations and are not consistently governed.
2. **Solution:** Show the architecture and explain detection, review, ledger creation, reminders, and escalation.
3. **Requirements:** Open the traceability workbook and follow one requirement through story, data, KPI, and test.
4. **Data:** Show the ER model and explain current-state versus append-only history.
5. **Analytics:** Run fulfillment, SLA, aging, and department queries.
6. **Dashboard:** Present the four dashboard pages and drill into a promise record.
7. **Trade-off:** Explain source-permission preservation and why contextual metrics are safer than employee scoring.

## Likely Interview Questions

### How did you gather requirements?
I modeled discovery workshops with Operations, Product, Engineering, Security, Legal, Compliance, HR, Data, and end users. I separated business outcomes from solution requirements and documented conflicts, assumptions, risks, and decision owners.

### How did you prioritize the backlog?
I combined MoSCoW with business value, regulatory risk, implementation effort, dependency sequencing, and learning value. Security, source authorization, audit, core extraction, and lifecycle controls were release gates.

### What was the hardest requirement?
Preserving source-level permissions while making promises searchable and reportable. The design stores evidence references and applies source ACLs and row-level security rather than creating a broadly visible copy of protected content.

### How did you validate the data?
I designed primary-key, foreign-key, duplicate, null, date, status-transition, reconciliation, and KPI-control queries. Requirements map to test cases in the RTM.

### What would you build next?
A working NLP extraction prototype, a Power BI file, model-quality monitoring, a Slack/Teams sandbox integration, and a simulated stakeholder UAT cycle.

## Honesty Statement

Describe this as a self-directed portfolio case study that you designed, modeled, and analyzed. Do not claim it was deployed, used by real employees, or generated realized savings. Always label the data as synthetic and ROI as modeled.
