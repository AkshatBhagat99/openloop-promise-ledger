
-- OPENLOOP ENTERPRISE DATA MODEL
-- Primary dialect: PostgreSQL 15+. SQL Server alternatives are labeled.
CREATE SCHEMA IF NOT EXISTS openloop;
SET search_path TO openloop;

CREATE TABLE department (
    department_id varchar(10) PRIMARY KEY,
    department_name varchar(100) NOT NULL UNIQUE,
    business_unit varchar(100) NOT NULL,
    cost_center varchar(30) NOT NULL,
    default_sla_hours integer NOT NULL CHECK (default_sla_hours > 0)
);

CREATE TABLE employee (
    employee_id varchar(10) PRIMARY KEY,
    employee_name varchar(150) NOT NULL,
    email varchar(255) NOT NULL UNIQUE,
    department_id varchar(10) NOT NULL REFERENCES department(department_id),
    job_title varchar(120) NOT NULL,
    management_level varchar(50),
    region varchar(50),
    employment_status varchar(30) NOT NULL,
    manager_employee_id varchar(10) REFERENCES employee(employee_id)
);

CREATE TABLE source_system (
    source_id varchar(10) PRIMARY KEY,
    source_name varchar(80) NOT NULL UNIQUE,
    source_type varchar(50) NOT NULL,
    integration_mode varchar(100) NOT NULL,
    retention_days integer NOT NULL CHECK (retention_days > 0)
);

CREATE TABLE conversation (
    conversation_id varchar(20) PRIMARY KEY,
    source_id varchar(10) NOT NULL REFERENCES source_system(source_id),
    external_thread_id varchar(120) NOT NULL,
    conversation_title varchar(300),
    channel_or_mailbox varchar(150),
    project_name varchar(150),
    department_id varchar(10) REFERENCES department(department_id),
    conversation_start_ts timestamptz NOT NULL,
    last_activity_ts timestamptz NOT NULL,
    conversation_status varchar(30) NOT NULL,
    sensitivity_label varchar(30) NOT NULL,
    UNIQUE(source_id, external_thread_id)
);

CREATE TABLE message (
    message_id varchar(20) PRIMARY KEY,
    conversation_id varchar(20) NOT NULL REFERENCES conversation(conversation_id),
    sender_employee_id varchar(10) REFERENCES employee(employee_id),
    message_ts timestamptz NOT NULL,
    message_text text NOT NULL,
    message_language varchar(10) NOT NULL,
    has_attachment boolean NOT NULL DEFAULT false,
    ingestion_ts timestamptz NOT NULL,
    content_hash varchar(100) NOT NULL UNIQUE
);

CREATE TABLE promise (
    promise_id varchar(20) PRIMARY KEY,
    message_id varchar(20) NOT NULL REFERENCES message(message_id),
    conversation_id varchar(20) NOT NULL REFERENCES conversation(conversation_id),
    promise_text text NOT NULL,
    promise_type varchar(50) NOT NULL,
    owner_employee_id varchar(10) REFERENCES employee(employee_id),
    owner_department_id varchar(10) REFERENCES department(department_id),
    created_ts timestamptz NOT NULL,
    due_ts timestamptz,
    completed_ts timestamptz,
    current_status varchar(30) NOT NULL,
    priority varchar(20) NOT NULL,
    ai_confidence_score numeric(5,4) NOT NULL CHECK (ai_confidence_score BETWEEN 0 AND 1),
    risk_score numeric(5,4) NOT NULL CHECK (risk_score BETWEEN 0 AND 1),
    sla_hours integer NOT NULL CHECK (sla_hours > 0),
    is_human_confirmed boolean NOT NULL DEFAULT false,
    duplicate_group_id varchar(20),
    CHECK (completed_ts IS NULL OR completed_ts >= created_ts)
);

CREATE TABLE promise_status_history (
    history_id varchar(20) PRIMARY KEY,
    promise_id varchar(20) NOT NULL REFERENCES promise(promise_id),
    event_ts timestamptz NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    changed_by_employee_id varchar(10) REFERENCES employee(employee_id),
    change_reason varchar(500)
);

CREATE TABLE notification (
    notification_id varchar(20) PRIMARY KEY,
    promise_id varchar(20) NOT NULL REFERENCES promise(promise_id),
    recipient_employee_id varchar(10) REFERENCES employee(employee_id),
    notification_type varchar(40) NOT NULL,
    channel varchar(30) NOT NULL,
    scheduled_ts timestamptz NOT NULL,
    sent_ts timestamptz,
    delivery_status varchar(30),
    action_taken varchar(50)
);

CREATE TABLE sla_reference (
    priority varchar(20) PRIMARY KEY,
    target_hours integer NOT NULL,
    warning_hours integer NOT NULL,
    escalation_level integer NOT NULL
);

CREATE INDEX ix_promise_owner_status_due ON promise(owner_employee_id, current_status, due_ts);
CREATE INDEX ix_promise_department_created ON promise(owner_department_id, created_ts);
CREATE INDEX ix_promise_risk_open ON promise(risk_score DESC, due_ts)
    WHERE current_status IN ('Open','In Progress','Overdue','Escalated');
CREATE INDEX ix_message_conversation_time ON message(conversation_id, message_ts);
CREATE INDEX ix_history_promise_event ON promise_status_history(promise_id, event_ts);
CREATE INDEX ix_notification_promise_schedule ON notification(promise_id, scheduled_ts);


-- =========================================================
-- 90 BUSINESS-FOCUSED SQL QUERIES
-- =========================================================


-- ---- SIMPLE ----


-- Q01. All active commitments
SELECT * FROM openloop.promise WHERE current_status IN ('Open','In Progress') ORDER BY due_ts;


-- Q02. Critical commitments due in seven days
SELECT promise_id, promise_text, owner_employee_id, due_ts FROM openloop.promise WHERE priority='Critical' AND due_ts >= CURRENT_TIMESTAMP AND due_ts < CURRENT_TIMESTAMP + INTERVAL '7 days' ORDER BY due_ts;


-- Q03. Overdue commitments
SELECT promise_id, owner_employee_id, due_ts, CURRENT_TIMESTAMP-due_ts AS overdue_duration FROM openloop.promise WHERE current_status='Overdue' ORDER BY due_ts;


-- Q04. Unconfirmed AI-created commitments
SELECT promise_id, promise_text, ai_confidence_score FROM openloop.promise WHERE is_human_confirmed=false ORDER BY ai_confidence_score DESC;


-- Q05. Low-confidence candidates already in ledger
SELECT promise_id, ai_confidence_score, current_status FROM openloop.promise WHERE ai_confidence_score < 0.80 ORDER BY ai_confidence_score;


-- Q06. Commitments without due dates
SELECT promise_id, promise_type, owner_employee_id, promise_text FROM openloop.promise WHERE due_ts IS NULL;


-- Q07. Commitments without resolved owners
SELECT promise_id, conversation_id, promise_text FROM openloop.promise WHERE owner_employee_id IS NULL;


-- ---- JOIN ----


-- Q08. Promises by source conversation
SELECT p.promise_id, s.source_name, c.conversation_title, p.current_status FROM openloop.promise p JOIN openloop.conversation c ON c.conversation_id=p.conversation_id JOIN openloop.source_system s ON s.source_id=c.source_id ORDER BY s.source_name, p.created_ts;


-- ---- SIMPLE ----


-- Q09. Employee commitment queue
SELECT p.promise_id, p.promise_text, p.priority, p.current_status, p.due_ts FROM openloop.promise p WHERE p.owner_employee_id=:employee_id ORDER BY CASE p.priority WHEN 'Critical' THEN 1 WHEN 'High' THEN 2 WHEN 'Medium' THEN 3 ELSE 4 END, p.due_ts;


-- Q10. Commitments created this month
SELECT promise_id, created_ts, promise_type FROM openloop.promise WHERE created_ts >= date_trunc('month', CURRENT_DATE) ORDER BY created_ts DESC;


-- Q11. Recently completed commitments
SELECT promise_id, owner_employee_id, completed_ts FROM openloop.promise WHERE current_status='Fulfilled' AND completed_ts >= CURRENT_TIMESTAMP-INTERVAL '30 days' ORDER BY completed_ts DESC;


-- Q12. Dormant conversations
SELECT conversation_id, conversation_title, last_activity_ts FROM openloop.conversation WHERE conversation_status='Dormant' OR last_activity_ts < CURRENT_TIMESTAMP-INTERVAL '30 days' ORDER BY last_activity_ts;


-- Q13. Failed notifications
SELECT notification_id, promise_id, channel, scheduled_ts FROM openloop.notification WHERE delivery_status='Failed' ORDER BY scheduled_ts DESC;


-- ---- AGGREGATE ----


-- Q14. Promises with duplicate-group signals
SELECT duplicate_group_id, COUNT(*) AS candidate_count FROM openloop.promise WHERE duplicate_group_id IS NOT NULL GROUP BY duplicate_group_id HAVING COUNT(*)>1 ORDER BY candidate_count DESC;


-- ---- SECURITY ----


-- Q15. Restricted conversations containing commitments
SELECT DISTINCT c.conversation_id, c.conversation_title, c.sensitivity_label FROM openloop.conversation c JOIN openloop.promise p ON p.conversation_id=c.conversation_id WHERE c.sensitivity_label='Restricted';


-- ---- AGGREGATE ----


-- Q16. Promise count by department
SELECT d.department_name, COUNT(p.promise_id) AS promise_count FROM openloop.department d LEFT JOIN openloop.promise p ON p.owner_department_id=d.department_id GROUP BY d.department_name ORDER BY promise_count DESC;


-- ---- KPI ----


-- Q17. Completion rate by department
SELECT d.department_name, COUNT(*) FILTER (WHERE p.current_status='Fulfilled')::numeric/NULLIF(COUNT(*),0) AS completion_rate FROM openloop.promise p JOIN openloop.department d ON d.department_id=p.owner_department_id GROUP BY d.department_name ORDER BY completion_rate DESC;


-- Q18. Broken promise rate by department
SELECT d.department_name, COUNT(*) FILTER (WHERE p.current_status IN ('Overdue','Escalated'))::numeric/NULLIF(COUNT(*),0) AS broken_promise_rate FROM openloop.promise p JOIN openloop.department d ON d.department_id=p.owner_department_id GROUP BY d.department_name ORDER BY broken_promise_rate DESC;


-- Q19. Average resolution hours by promise type
SELECT promise_type, AVG(EXTRACT(EPOCH FROM (completed_ts-created_ts))/3600.0) AS avg_resolution_hours FROM openloop.promise WHERE completed_ts IS NOT NULL GROUP BY promise_type ORDER BY avg_resolution_hours DESC;


-- Q20. SLA compliance by priority
SELECT priority, COUNT(*) FILTER (WHERE completed_ts IS NOT NULL AND completed_ts <= created_ts + make_interval(hours=>sla_hours))::numeric / NULLIF(COUNT(*) FILTER (WHERE completed_ts IS NOT NULL),0) AS sla_compliance FROM openloop.promise GROUP BY priority ORDER BY priority;


-- ---- AI ANALYTICS ----


-- Q21. Source-level AI confidence
SELECT s.source_name, AVG(p.ai_confidence_score) AS avg_confidence, COUNT(*) AS promises FROM openloop.promise p JOIN openloop.conversation c ON c.conversation_id=p.conversation_id JOIN openloop.source_system s ON s.source_id=c.source_id GROUP BY s.source_name ORDER BY avg_confidence DESC;


-- ---- KPI ----


-- Q22. Notification effectiveness
SELECT notification_type, COUNT(*) AS sent, COUNT(*) FILTER (WHERE action_taken<>'None')::numeric/NULLIF(COUNT(*),0) AS action_rate FROM openloop.notification WHERE sent_ts IS NOT NULL GROUP BY notification_type ORDER BY action_rate DESC;


-- ---- MANAGEMENT ----


-- Q23. Manager team backlog
SELECT m.employee_name AS manager, COUNT(p.promise_id) FILTER (WHERE p.current_status IN ('Open','In Progress','Overdue','Escalated')) AS active_backlog FROM openloop.employee e JOIN openloop.employee m ON m.employee_id=e.manager_employee_id LEFT JOIN openloop.promise p ON p.owner_employee_id=e.employee_id GROUP BY m.employee_name ORDER BY active_backlog DESC;


-- ---- EXECUTIVE ----


-- Q24. Project risk summary
SELECT c.project_name, COUNT(*) AS total, COUNT(*) FILTER (WHERE p.current_status IN ('Overdue','Escalated')) AS at_risk, AVG(p.risk_score) AS avg_risk FROM openloop.promise p JOIN openloop.conversation c ON c.conversation_id=p.conversation_id GROUP BY c.project_name ORDER BY at_risk DESC, avg_risk DESC;


-- ---- ANALYTICS ----


-- Q25. Conversation promise density
SELECT c.conversation_id, c.conversation_title, COUNT(m.message_id) AS messages, COUNT(DISTINCT p.promise_id) AS promises, COUNT(DISTINCT p.promise_id)::numeric/NULLIF(COUNT(m.message_id),0) AS promises_per_message FROM openloop.conversation c LEFT JOIN openloop.message m ON m.conversation_id=c.conversation_id LEFT JOIN openloop.promise p ON p.conversation_id=c.conversation_id GROUP BY c.conversation_id,c.conversation_title ORDER BY promises_per_message DESC;


-- ---- KPI ----


-- Q26. Ownership change count
SELECT p.promise_id, COUNT(*) FILTER (WHERE h.to_status='Reassigned') AS reassignments FROM openloop.promise p LEFT JOIN openloop.promise_status_history h ON h.promise_id=p.promise_id GROUP BY p.promise_id HAVING COUNT(*) FILTER (WHERE h.to_status='Reassigned')>0 ORDER BY reassignments DESC;


-- ---- OPERATIONAL ----


-- Q27. Department notification load
SELECT d.department_name, COUNT(n.notification_id) AS notifications, COUNT(DISTINCT n.promise_id) AS promises_notified FROM openloop.notification n JOIN openloop.promise p ON p.promise_id=n.promise_id JOIN openloop.department d ON d.department_id=p.owner_department_id GROUP BY d.department_name ORDER BY notifications DESC;


-- Q28. Average ingestion delay by source
SELECT s.source_name, AVG(EXTRACT(EPOCH FROM (m.ingestion_ts-m.message_ts))/60.0) AS avg_ingestion_minutes FROM openloop.message m JOIN openloop.conversation c ON c.conversation_id=m.conversation_id JOIN openloop.source_system s ON s.source_id=c.source_id GROUP BY s.source_name ORDER BY avg_ingestion_minutes DESC;


-- ---- ADOPTION ----


-- Q29. Human confirmation by source
SELECT s.source_name, COUNT(*) FILTER (WHERE p.is_human_confirmed)::numeric/NULLIF(COUNT(*),0) AS confirmation_rate FROM openloop.promise p JOIN openloop.conversation c ON c.conversation_id=p.conversation_id JOIN openloop.source_system s ON s.source_id=c.source_id GROUP BY s.source_name ORDER BY confirmation_rate DESC;


-- ---- OPERATIONAL ----


-- Q30. Employees with overloaded active backlog
SELECT e.employee_id,e.employee_name,d.department_name,COUNT(*) AS active_commitments FROM openloop.promise p JOIN openloop.employee e ON e.employee_id=p.owner_employee_id JOIN openloop.department d ON d.department_id=e.department_id WHERE p.current_status IN ('Open','In Progress','Overdue','Escalated') GROUP BY e.employee_id,e.employee_name,d.department_name HAVING COUNT(*)>=5 ORDER BY active_commitments DESC;


-- ---- WINDOW ----


-- Q31. Rank departments by completion rate
WITH x AS (SELECT d.department_name, COUNT(*) FILTER (WHERE p.current_status='Fulfilled')::numeric/NULLIF(COUNT(*),0) rate FROM openloop.promise p JOIN openloop.department d ON d.department_id=p.owner_department_id GROUP BY d.department_name) SELECT department_name,rate,DENSE_RANK() OVER(ORDER BY rate DESC) AS completion_rank FROM x;


-- Q32. Rank employees by fulfilled commitments with context
SELECT e.employee_name,d.department_name,COUNT(*) FILTER (WHERE p.current_status='Fulfilled') AS fulfilled,DENSE_RANK() OVER(PARTITION BY d.department_name ORDER BY COUNT(*) FILTER (WHERE p.current_status='Fulfilled') DESC) AS dept_rank FROM openloop.employee e JOIN openloop.department d ON d.department_id=e.department_id LEFT JOIN openloop.promise p ON p.owner_employee_id=e.employee_id GROUP BY e.employee_name,d.department_name;


-- Q33. Running monthly promise total
WITH m AS (SELECT date_trunc('month',created_ts)::date month,COUNT(*) cnt FROM openloop.promise GROUP BY 1) SELECT month,cnt,SUM(cnt) OVER(ORDER BY month) AS running_total FROM m ORDER BY month;


-- Q34. Monthly completion trend with lag
WITH m AS (SELECT date_trunc('month',created_ts)::date month,COUNT(*) FILTER(WHERE current_status='Fulfilled')::numeric/NULLIF(COUNT(*),0) rate FROM openloop.promise GROUP BY 1) SELECT month,rate,LAG(rate) OVER(ORDER BY month) prior_month_rate,rate-LAG(rate) OVER(ORDER BY month) change FROM m ORDER BY month;


-- ---- ANALYTICS ----


-- Q35. Promise aging buckets
SELECT promise_id,current_status,EXTRACT(DAY FROM (COALESCE(completed_ts,CURRENT_TIMESTAMP)-created_ts)) AS age_days,CASE WHEN COALESCE(completed_ts,CURRENT_TIMESTAMP)-created_ts<INTERVAL '3 days' THEN '0-2' WHEN COALESCE(completed_ts,CURRENT_TIMESTAMP)-created_ts<INTERVAL '8 days' THEN '3-7' WHEN COALESCE(completed_ts,CURRENT_TIMESTAMP)-created_ts<INTERVAL '15 days' THEN '8-14' WHEN COALESCE(completed_ts,CURRENT_TIMESTAMP)-created_ts<INTERVAL '31 days' THEN '15-30' ELSE '31+' END aging_bucket FROM openloop.promise;


-- ---- WINDOW ----


-- Q36. Percentile resolution time by department
SELECT d.department_name,percentile_cont(0.5) WITHIN GROUP(ORDER BY EXTRACT(EPOCH FROM(p.completed_ts-p.created_ts))/3600) median_hours,percentile_cont(0.9) WITHIN GROUP(ORDER BY EXTRACT(EPOCH FROM(p.completed_ts-p.created_ts))/3600) p90_hours FROM openloop.promise p JOIN openloop.department d ON d.department_id=p.owner_department_id WHERE p.completed_ts IS NOT NULL GROUP BY d.department_name;


-- Q37. Latest status event per promise
SELECT * FROM (SELECT h.*,ROW_NUMBER() OVER(PARTITION BY promise_id ORDER BY event_ts DESC,history_id DESC) rn FROM openloop.promise_status_history h) x WHERE rn=1;


-- Q38. Time between lifecycle events
SELECT promise_id,event_ts,to_status,LAG(event_ts) OVER(PARTITION BY promise_id ORDER BY event_ts) prior_event_ts,EXTRACT(EPOCH FROM(event_ts-LAG(event_ts) OVER(PARTITION BY promise_id ORDER BY event_ts)))/3600 AS hours_since_prior FROM openloop.promise_status_history;


-- Q39. First notification after creation
SELECT * FROM (SELECT n.*,ROW_NUMBER() OVER(PARTITION BY n.promise_id ORDER BY n.sent_ts) rn FROM openloop.notification n WHERE sent_ts IS NOT NULL) x WHERE rn=1;


-- ---- CTE ----


-- Q40. Repeated overdue employees
WITH monthly AS (SELECT owner_employee_id,date_trunc('month',due_ts)::date month,COUNT(*) FILTER(WHERE current_status IN('Overdue','Escalated')) overdue_count FROM openloop.promise GROUP BY 1,2) SELECT owner_employee_id,COUNT(*) FILTER(WHERE overdue_count>0) months_with_overdue,SUM(overdue_count) overdue_total FROM monthly GROUP BY owner_employee_id HAVING COUNT(*) FILTER(WHERE overdue_count>0)>=2;


-- ---- RECURSIVE CTE ----


-- Q41. Recursive management hierarchy
WITH RECURSIVE org AS (SELECT employee_id,employee_name,manager_employee_id,0 depth,employee_name::text path FROM openloop.employee WHERE manager_employee_id IS NULL UNION ALL SELECT e.employee_id,e.employee_name,e.manager_employee_id,o.depth+1,o.path||' > '||e.employee_name FROM openloop.employee e JOIN org o ON e.manager_employee_id=o.employee_id) SELECT * FROM org ORDER BY path;


-- Q42. Recursive escalation chain for one owner
WITH RECURSIVE chain AS (SELECT e.employee_id,e.employee_name,e.manager_employee_id,0 level FROM openloop.employee e WHERE e.employee_id=:owner_id UNION ALL SELECT m.employee_id,m.employee_name,m.manager_employee_id,c.level+1 FROM openloop.employee m JOIN chain c ON m.employee_id=c.manager_employee_id) SELECT * FROM chain ORDER BY level;


-- ---- WINDOW ----


-- Q43. Consecutive inactivity gaps
WITH x AS (SELECT conversation_id,message_ts,LAG(message_ts) OVER(PARTITION BY conversation_id ORDER BY message_ts) prev_ts FROM openloop.message) SELECT conversation_id,message_ts,prev_ts,message_ts-prev_ts gap FROM x WHERE message_ts-prev_ts>INTERVAL '7 days' ORDER BY gap DESC;


-- Q44. Top risk promise per project
SELECT * FROM (SELECT c.project_name,p.promise_id,p.risk_score,p.current_status,ROW_NUMBER() OVER(PARTITION BY c.project_name ORDER BY p.risk_score DESC,p.due_ts) rn FROM openloop.promise p JOIN openloop.conversation c ON c.conversation_id=p.conversation_id) x WHERE rn<=3;


-- ---- PREDICTIVE ----


-- Q45. Cumulative overdue share
WITH x AS (SELECT p.promise_id,p.risk_score,CASE WHEN current_status IN('Overdue','Escalated') THEN 1 ELSE 0 END broken FROM openloop.promise p), y AS (SELECT *,SUM(broken) OVER(ORDER BY risk_score DESC) cumulative_broken,SUM(broken) OVER() total_broken,ROW_NUMBER() OVER(ORDER BY risk_score DESC) row_num,COUNT(*) OVER() total_rows FROM x) SELECT *,cumulative_broken::numeric/NULLIF(total_broken,0) cumulative_capture,row_num::numeric/total_rows population_share FROM y ORDER BY risk_score DESC;


-- ---- PIVOT ----


-- Q46. PostgreSQL status pivot by department
SELECT d.department_name,COUNT(*) FILTER(WHERE p.current_status='Open') open_count,COUNT(*) FILTER(WHERE p.current_status='In Progress') in_progress_count,COUNT(*) FILTER(WHERE p.current_status='Fulfilled') fulfilled_count,COUNT(*) FILTER(WHERE p.current_status='Overdue') overdue_count,COUNT(*) FILTER(WHERE p.current_status='Escalated') escalated_count FROM openloop.department d LEFT JOIN openloop.promise p ON p.owner_department_id=d.department_id GROUP BY d.department_name ORDER BY d.department_name;


-- ---- SQL SERVER PIVOT ----


-- Q47. SQL Server PIVOT status by department
SELECT department_name,[Open],[In Progress],[Fulfilled],[Overdue],[Escalated] FROM (SELECT d.department_name,p.current_status,p.promise_id FROM openloop.department d LEFT JOIN openloop.promise p ON p.owner_department_id=d.department_id) src PIVOT (COUNT(promise_id) FOR current_status IN ([Open],[In Progress],[Fulfilled],[Overdue],[Escalated])) p;


-- ---- PIVOT ----


-- Q48. Monthly source pivot using conditional aggregation
SELECT date_trunc('month',p.created_ts)::date month,COUNT(*) FILTER(WHERE s.source_name='Slack') slack,COUNT(*) FILTER(WHERE s.source_name='Microsoft Teams') teams,COUNT(*) FILTER(WHERE s.source_name='Gmail') gmail,COUNT(*) FILTER(WHERE s.source_name='Zoom') zoom FROM openloop.promise p JOIN openloop.conversation c ON c.conversation_id=p.conversation_id JOIN openloop.source_system s ON s.source_id=c.source_id GROUP BY 1 ORDER BY 1;


-- Q49. Priority by status matrix
SELECT priority,COUNT(*) FILTER(WHERE current_status='Open') open,COUNT(*) FILTER(WHERE current_status='In Progress') in_progress,COUNT(*) FILTER(WHERE current_status='Fulfilled') fulfilled,COUNT(*) FILTER(WHERE current_status='Overdue') overdue,COUNT(*) FILTER(WHERE current_status='Escalated') escalated FROM openloop.promise GROUP BY priority ORDER BY priority;


-- Q50. Notification channel matrix
SELECT notification_type,COUNT(*) FILTER(WHERE channel='Email') email,COUNT(*) FILTER(WHERE channel='Slack') slack,COUNT(*) FILTER(WHERE channel='Teams') teams,COUNT(*) FILTER(WHERE channel='In-App') in_app FROM openloop.notification GROUP BY notification_type;


-- ---- SQL SERVER UNPIVOT ----


-- Q51. SQL Server UNPIVOT departmental KPI columns
SELECT department_name,kpi_name,kpi_value FROM department_kpi_snapshot UNPIVOT (kpi_value FOR kpi_name IN (completion_rate,broken_promise_rate,escalation_rate,sla_compliance)) u;


-- ---- UNPIVOT ----


-- Q52. PostgreSQL unpivot KPI JSON
WITH k AS (SELECT d.department_name,jsonb_build_object('completion_rate',COUNT(*) FILTER(WHERE p.current_status='Fulfilled')::numeric/NULLIF(COUNT(*),0),'broken_rate',COUNT(*) FILTER(WHERE p.current_status IN('Overdue','Escalated'))::numeric/NULLIF(COUNT(*),0),'avg_risk',AVG(p.risk_score)) metrics FROM openloop.promise p JOIN openloop.department d ON d.department_id=p.owner_department_id GROUP BY d.department_name) SELECT department_name,m.key AS metric,m.value::numeric AS metric_value FROM k CROSS JOIN LATERAL jsonb_each_text(metrics) m;


-- ---- PIVOT ----


-- Q53. Quarterly status matrix
SELECT date_trunc('quarter',created_ts)::date quarter,COUNT(*) FILTER(WHERE current_status='Fulfilled') fulfilled,COUNT(*) FILTER(WHERE current_status='Overdue') overdue,COUNT(*) FILTER(WHERE current_status='Escalated') escalated FROM openloop.promise GROUP BY 1 ORDER BY 1;


-- Q54. Promise type completion matrix
SELECT promise_type,COUNT(*) total,COUNT(*) FILTER(WHERE current_status='Fulfilled') fulfilled,COUNT(*) FILTER(WHERE current_status IN('Overdue','Escalated')) broken FROM openloop.promise GROUP BY promise_type ORDER BY total DESC;


-- Q55. Region by priority matrix
SELECT e.region,COUNT(*) FILTER(WHERE p.priority='Critical') critical,COUNT(*) FILTER(WHERE p.priority='High') high,COUNT(*) FILTER(WHERE p.priority='Medium') medium,COUNT(*) FILTER(WHERE p.priority='Low') low FROM openloop.promise p JOIN openloop.employee e ON e.employee_id=p.owner_employee_id GROUP BY e.region;


-- ---- VIEW ----


-- Q56. Create active promise view
CREATE OR REPLACE VIEW openloop.v_active_promise AS SELECT p.*,e.employee_name,d.department_name,c.project_name,s.source_name FROM openloop.promise p LEFT JOIN openloop.employee e ON e.employee_id=p.owner_employee_id LEFT JOIN openloop.department d ON d.department_id=p.owner_department_id JOIN openloop.conversation c ON c.conversation_id=p.conversation_id JOIN openloop.source_system s ON s.source_id=c.source_id WHERE p.current_status IN('Open','In Progress','Overdue','Escalated');


-- Q57. Create promise lifecycle view
CREATE OR REPLACE VIEW openloop.v_promise_lifecycle AS SELECT p.promise_id,p.created_ts,p.due_ts,p.completed_ts,p.current_status,COUNT(h.history_id) event_count,MIN(h.event_ts) first_event,MAX(h.event_ts) last_event FROM openloop.promise p LEFT JOIN openloop.promise_status_history h ON h.promise_id=p.promise_id GROUP BY p.promise_id;


-- Q58. Create department KPI view
CREATE OR REPLACE VIEW openloop.v_department_kpi AS SELECT d.department_id,d.department_name,COUNT(p.promise_id) total_promises,COUNT(*) FILTER(WHERE p.current_status='Fulfilled') fulfilled,COUNT(*) FILTER(WHERE p.current_status IN('Overdue','Escalated')) broken,AVG(p.risk_score) avg_risk FROM openloop.department d LEFT JOIN openloop.promise p ON p.owner_department_id=d.department_id GROUP BY d.department_id,d.department_name;


-- Q59. Create employee accountability view
CREATE OR REPLACE VIEW openloop.v_employee_accountability AS SELECT e.employee_id,e.employee_name,e.department_id,COUNT(p.promise_id) total,COUNT(*) FILTER(WHERE p.current_status='Fulfilled') fulfilled,COUNT(*) FILTER(WHERE p.current_status IN('Overdue','Escalated')) broken,AVG(EXTRACT(EPOCH FROM(p.completed_ts-p.created_ts))/3600) FILTER(WHERE p.completed_ts IS NOT NULL) avg_resolution_hours FROM openloop.employee e LEFT JOIN openloop.promise p ON p.owner_employee_id=e.employee_id GROUP BY e.employee_id,e.employee_name,e.department_id;


-- ---- MATERIALIZED VIEW ----


-- Q60. Create monthly materialized KPI view
CREATE MATERIALIZED VIEW IF NOT EXISTS openloop.mv_monthly_kpi AS SELECT date_trunc('month',created_ts)::date month,owner_department_id,COUNT(*) total,COUNT(*) FILTER(WHERE current_status='Fulfilled') fulfilled,COUNT(*) FILTER(WHERE current_status IN('Overdue','Escalated')) broken,AVG(risk_score) avg_risk FROM openloop.promise GROUP BY 1,2 WITH DATA;


-- Q61. Refresh monthly materialized KPI view
REFRESH MATERIALIZED VIEW CONCURRENTLY openloop.mv_monthly_kpi;


-- ---- VIEW ----


-- Q62. Create search-friendly promise view
CREATE OR REPLACE VIEW openloop.v_promise_search AS SELECT p.promise_id,p.promise_text,p.current_status,p.priority,p.due_ts,e.employee_name,d.department_name,c.project_name,c.conversation_title,s.source_name FROM openloop.promise p LEFT JOIN openloop.employee e ON e.employee_id=p.owner_employee_id LEFT JOIN openloop.department d ON d.department_id=p.owner_department_id JOIN openloop.conversation c ON c.conversation_id=p.conversation_id JOIN openloop.source_system s ON s.source_id=c.source_id;


-- ---- STORED FUNCTION ----


-- Q63. PostgreSQL function to transition promise status
CREATE OR REPLACE FUNCTION openloop.transition_promise(p_promise_id varchar,p_to_status varchar,p_actor varchar,p_reason text) RETURNS void LANGUAGE plpgsql AS $$ DECLARE v_from varchar; BEGIN SELECT current_status INTO v_from FROM openloop.promise WHERE promise_id=p_promise_id FOR UPDATE; IF v_from IS NULL THEN RAISE EXCEPTION 'Promise not found'; END IF; UPDATE openloop.promise SET current_status=p_to_status,completed_ts=CASE WHEN p_to_status='Fulfilled' THEN CURRENT_TIMESTAMP ELSE completed_ts END WHERE promise_id=p_promise_id; INSERT INTO openloop.promise_status_history(history_id,promise_id,event_ts,from_status,to_status,changed_by_employee_id,change_reason) VALUES('H'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'),p_promise_id,CURRENT_TIMESTAMP,v_from,p_to_status,p_actor,p_reason); END $$;


-- Q64. PostgreSQL function to reassign owner
CREATE OR REPLACE FUNCTION openloop.reassign_promise(p_promise_id varchar,p_new_owner varchar,p_actor varchar,p_reason text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN UPDATE openloop.promise p SET owner_employee_id=p_new_owner,owner_department_id=e.department_id,current_status='Reassigned' FROM openloop.employee e WHERE p.promise_id=p_promise_id AND e.employee_id=p_new_owner; INSERT INTO openloop.promise_status_history(history_id,promise_id,event_ts,from_status,to_status,changed_by_employee_id,change_reason) SELECT 'H'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'),p_promise_id,CURRENT_TIMESTAMP,current_status,'Reassigned',p_actor,p_reason FROM openloop.promise WHERE promise_id=p_promise_id; END $$;


-- ---- STORED PROCEDURE ----


-- Q65. PostgreSQL procedure to mark overdue
CREATE OR REPLACE PROCEDURE openloop.mark_overdue_promises() LANGUAGE plpgsql AS $$ BEGIN UPDATE openloop.promise SET current_status='Overdue' WHERE current_status IN('Open','In Progress') AND due_ts<CURRENT_TIMESTAMP; END $$;


-- ---- STORED FUNCTION ----


-- Q66. PostgreSQL function for manager hierarchy
CREATE OR REPLACE FUNCTION openloop.manager_chain(p_employee_id varchar) RETURNS TABLE(employee_id varchar,employee_name varchar,level integer) LANGUAGE sql AS $$ WITH RECURSIVE c AS (SELECT e.employee_id,e.employee_name,e.manager_employee_id,0 level FROM openloop.employee e WHERE e.employee_id=p_employee_id UNION ALL SELECT m.employee_id,m.employee_name,m.manager_employee_id,c.level+1 FROM openloop.employee m JOIN c ON m.employee_id=c.manager_employee_id) SELECT employee_id,employee_name,level FROM c $$;


-- ---- SQL SERVER PROCEDURE ----


-- Q67. SQL Server procedure to complete promise
CREATE OR ALTER PROCEDURE openloop.usp_complete_promise @promise_id varchar(20),@actor_id varchar(10),@reason nvarchar(500) AS BEGIN SET NOCOUNT ON; BEGIN TRAN; DECLARE @from_status varchar(30); SELECT @from_status=current_status FROM openloop.promise WITH(UPDLOCK,ROWLOCK) WHERE promise_id=@promise_id; UPDATE openloop.promise SET current_status='Fulfilled',completed_ts=SYSUTCDATETIME() WHERE promise_id=@promise_id; INSERT openloop.promise_status_history(history_id,promise_id,event_ts,from_status,to_status,changed_by_employee_id,change_reason) VALUES(CONCAT('H',FORMAT(SYSUTCDATETIME(),'yyyyMMddHHmmssfff')),@promise_id,SYSUTCDATETIME(),@from_status,'Fulfilled',@actor_id,@reason); COMMIT; END;


-- ---- STORED PROCEDURE ----


-- Q68. Procedure to rebuild daily KPI snapshot
CREATE OR REPLACE PROCEDURE openloop.refresh_reporting_objects() LANGUAGE plpgsql AS $$ BEGIN REFRESH MATERIALIZED VIEW openloop.mv_monthly_kpi; ANALYZE openloop.promise; ANALYZE openloop.promise_status_history; END $$;


-- ---- INDEX ----


-- Q69. Partial index for actionable queue
CREATE INDEX IF NOT EXISTS ix_promise_actionable ON openloop.promise(owner_department_id,due_ts,risk_score DESC) WHERE current_status IN('Open','In Progress','Overdue','Escalated');


-- Q70. Covering index for employee dashboard
CREATE INDEX IF NOT EXISTS ix_promise_employee_dashboard ON openloop.promise(owner_employee_id,current_status,due_ts) INCLUDE(priority,risk_score,promise_type);


-- Q71. BRIN index for large history table
CREATE INDEX IF NOT EXISTS ix_history_event_brin ON openloop.promise_status_history USING brin(event_ts);


-- Q72. Full-text search index
ALTER TABLE openloop.promise ADD COLUMN IF NOT EXISTS search_vector tsvector GENERATED ALWAYS AS (to_tsvector('english',coalesce(promise_text,''))) STORED; CREATE INDEX IF NOT EXISTS ix_promise_search_vector ON openloop.promise USING gin(search_vector);


-- ---- EXECUTION PLAN ----


-- Q73. Explain actionable queue
EXPLAIN (ANALYZE,BUFFERS,FORMAT TEXT) SELECT promise_id,due_ts,risk_score FROM openloop.promise WHERE owner_department_id='D002' AND current_status IN('Open','In Progress','Overdue','Escalated') ORDER BY due_ts,risk_score DESC LIMIT 100;


-- Q74. Explain department KPI aggregation
EXPLAIN (ANALYZE,BUFFERS) SELECT owner_department_id,COUNT(*),AVG(risk_score) FROM openloop.promise WHERE created_ts>=CURRENT_DATE-INTERVAL '90 days' GROUP BY owner_department_id;


-- ---- OPTIMIZATION ----


-- Q75. Index health and usage
SELECT schemaname,relname,indexrelname,idx_scan,idx_tup_read,idx_tup_fetch FROM pg_stat_user_indexes WHERE schemaname='openloop' ORDER BY idx_scan ASC;


-- ---- DATA QUALITY ----


-- Q76. Duplicate message content hashes
SELECT content_hash,COUNT(*) FROM openloop.message GROUP BY content_hash HAVING COUNT(*)>1;


-- Q77. Orphan promise-message references
SELECT p.promise_id FROM openloop.promise p LEFT JOIN openloop.message m ON m.message_id=p.message_id WHERE m.message_id IS NULL;


-- Q78. Owner department mismatch
SELECT p.promise_id,p.owner_department_id,e.department_id actual_department FROM openloop.promise p JOIN openloop.employee e ON e.employee_id=p.owner_employee_id WHERE p.owner_department_id<>e.department_id;


-- Q79. Invalid completion timestamp
SELECT promise_id,created_ts,completed_ts FROM openloop.promise WHERE completed_ts<created_ts;


-- Q80. Fulfilled promises missing completion timestamp
SELECT promise_id FROM openloop.promise WHERE current_status='Fulfilled' AND completed_ts IS NULL;


-- Q81. Open promises with completion timestamp
SELECT promise_id,current_status,completed_ts FROM openloop.promise WHERE current_status<>'Fulfilled' AND completed_ts IS NOT NULL;


-- Q82. Status current-state mismatch
WITH latest AS (SELECT promise_id,to_status,ROW_NUMBER() OVER(PARTITION BY promise_id ORDER BY event_ts DESC,history_id DESC) rn FROM openloop.promise_status_history) SELECT p.promise_id,p.current_status,l.to_status latest_history_status FROM openloop.promise p JOIN latest l ON l.promise_id=p.promise_id AND l.rn=1 WHERE p.current_status<>l.to_status;


-- Q83. Impossible SLA values and scores
SELECT promise_id,sla_hours,ai_confidence_score,risk_score FROM openloop.promise WHERE sla_hours<=0 OR ai_confidence_score NOT BETWEEN 0 AND 1 OR risk_score NOT BETWEEN 0 AND 1;


-- ---- EXECUTIVE ----


-- Q84. Enterprise KPI scorecard
SELECT COUNT(*) total_promises,COUNT(*) FILTER(WHERE current_status='Fulfilled')::numeric/NULLIF(COUNT(*),0) completion_rate,COUNT(*) FILTER(WHERE current_status IN('Overdue','Escalated'))::numeric/NULLIF(COUNT(*),0) broken_promise_rate,COUNT(*) FILTER(WHERE current_status='Escalated')::numeric/NULLIF(COUNT(*),0) escalation_rate,COUNT(*) FILTER(WHERE current_status='Reassigned')::numeric/NULLIF(COUNT(*),0) ownership_change_rate,AVG(EXTRACT(EPOCH FROM(completed_ts-created_ts))/3600) FILTER(WHERE completed_ts IS NOT NULL) avg_resolution_hours FROM openloop.promise;


-- Q85. Executive monthly trend
SELECT date_trunc('month',created_ts)::date month,COUNT(*) total,COUNT(*) FILTER(WHERE current_status='Fulfilled') fulfilled,COUNT(*) FILTER(WHERE current_status IN('Overdue','Escalated')) broken,AVG(risk_score) avg_risk FROM openloop.promise GROUP BY 1 ORDER BY 1;


-- Q86. Commitment aging and exposure
SELECT CASE WHEN CURRENT_TIMESTAMP-created_ts<INTERVAL '3 days' THEN '0-2 days' WHEN CURRENT_TIMESTAMP-created_ts<INTERVAL '8 days' THEN '3-7 days' WHEN CURRENT_TIMESTAMP-created_ts<INTERVAL '15 days' THEN '8-14 days' WHEN CURRENT_TIMESTAMP-created_ts<INTERVAL '31 days' THEN '15-30 days' ELSE '31+ days' END age_bucket,COUNT(*) active_count,SUM(CASE priority WHEN 'Critical' THEN 4 WHEN 'High' THEN 3 WHEN 'Medium' THEN 2 ELSE 1 END) weighted_exposure FROM openloop.promise WHERE current_status IN('Open','In Progress','Overdue','Escalated') GROUP BY 1 ORDER BY MIN(CURRENT_TIMESTAMP-created_ts);


-- Q87. Abandoned conversation indicator
SELECT c.conversation_id,c.conversation_title,c.project_name,c.last_activity_ts,COUNT(p.promise_id) FILTER(WHERE p.current_status IN('Open','In Progress','Overdue','Escalated')) unresolved_promises FROM openloop.conversation c LEFT JOIN openloop.promise p ON p.conversation_id=c.conversation_id GROUP BY c.conversation_id,c.conversation_title,c.project_name,c.last_activity_ts HAVING c.last_activity_ts<CURRENT_TIMESTAMP-INTERVAL '14 days' AND COUNT(p.promise_id) FILTER(WHERE p.current_status IN('Open','In Progress','Overdue','Escalated'))>0 ORDER BY unresolved_promises DESC;


-- ---- KPI ----


-- Q88. Conversation reopen rate
WITH events AS (SELECT p.conversation_id,h.promise_id,h.to_status,h.event_ts,LAG(h.to_status) OVER(PARTITION BY h.promise_id ORDER BY h.event_ts) prior_status FROM openloop.promise_status_history h JOIN openloop.promise p ON p.promise_id=h.promise_id), x AS (SELECT conversation_id,COUNT(*) FILTER(WHERE prior_status IN('Fulfilled','Cancelled') AND to_status IN('Open','In Progress')) reopened FROM events GROUP BY conversation_id) SELECT COUNT(*) FILTER(WHERE reopened>0)::numeric/NULLIF(COUNT(*),0) conversation_reopen_rate FROM x;


-- ---- PREDICTIVE ----


-- Q89. Risk prediction decile performance
WITH s AS (SELECT promise_id,risk_score,CASE WHEN current_status IN('Overdue','Escalated') THEN 1 ELSE 0 END actual_broken,NTILE(10) OVER(ORDER BY risk_score DESC) decile FROM openloop.promise) SELECT decile,COUNT(*) population,SUM(actual_broken) broken,AVG(actual_broken::numeric) observed_broken_rate,AVG(risk_score) avg_predicted_risk FROM s GROUP BY decile ORDER BY decile;


-- ---- EXECUTIVE ----


-- Q90. CEO exception report
SELECT d.department_name,c.project_name,e.employee_name,p.promise_id,p.promise_text,p.priority,p.current_status,p.due_ts,p.risk_score FROM openloop.promise p JOIN openloop.department d ON d.department_id=p.owner_department_id LEFT JOIN openloop.employee e ON e.employee_id=p.owner_employee_id JOIN openloop.conversation c ON c.conversation_id=p.conversation_id WHERE p.current_status IN('Overdue','Escalated') OR (p.current_status IN('Open','In Progress') AND p.risk_score>=0.75) ORDER BY CASE p.priority WHEN 'Critical' THEN 1 WHEN 'High' THEN 2 ELSE 3 END,p.risk_score DESC,p.due_ts;
