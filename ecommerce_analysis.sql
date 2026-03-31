SELECT COUNT(*) AS total_rows FROM events_clean 

SELECT 
	event_type, 
	COUNT(*) AS total_rows 
FROM events_clean 
GROUP BY event_type

-- conversation rate
WITH funnel AS (
SELECT
    user_id,
    MAX(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS viewed,
    MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS added,
    MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS purchased
FROM events_clean
GROUP BY user_id
)
SELECT
    COUNT(*) AS total_users,
    SUM(viewed) AS viewed_users,
    SUM(added) AS added_users,
    SUM(purchased) AS purchased_users,

    ROUND(SUM(added) * 100.0 / NULLIF(SUM(viewed), 0), 2) AS view_to_cart_cr,
	ROUND(SUM(purchased) * 100.0 / NULLIF(SUM(added), 0), 2) AS cart_to_purchase_cr
FROM funnel

-- retention
WITH first_event AS (
  SELECT
    user_id,
    DATE_TRUNC('day', MIN(event_time)) AS cohort_day
  FROM events_clean
  GROUP BY user_id
),
cohort_activity AS (
  SELECT
    fe.user_id,
    fe.cohort_day,
    DATE_TRUNC('day', e.event_time) AS activity_day,
    EXTRACT(DAY FROM DATE_TRUNC('day', e.event_time) - fe.cohort_day) AS day_since_signup
  FROM first_event fe
  JOIN events_clean e ON fe.user_id = e.user_id
)
SELECT
  cohort_day,
  day_since_signup,
  COUNT(DISTINCT user_id) AS active_users
FROM cohort_activity
WHERE day_since_signup >= 0
GROUP BY cohort_day, day_since_signup
ORDER BY cohort_day, day_since_signup

-- RFM segmentation
WITH max_date AS (
SELECT MAX(event_time)::date AS last_date
FROM events_clean
),
rfm AS (
SELECT
	user_id,
	MAX(event_time) AS last_purchase,
	COUNT(*) AS frequency,
	(SELECT last_date FROM max_date) - MAX(event_time)::date AS recency_days
FROM events_clean
WHERE event_type = 'purchase'
GROUP BY user_id
),
rfm_scored AS (
SELECT
	user_id,
	recency_days,
	frequency,
	NTILE(4) OVER (ORDER BY recency_days ASC)  AS r_score,
    NTILE(4) OVER (ORDER BY frequency DESC)    AS f_score
FROM rfm
)
SELECT
	user_id,
	recency_days,
	frequency,
	r_score,
	f_score,
	CASE
		WHEN r_score = 4 AND f_score = 4 THEN 'чемпіон'
		WHEN r_score = 3 AND f_score >= 3 THEN 'лояльний'
		WHEN r_score >= 3 AND f_score <= 2 THEN 'новий'
		WHEN r_score <= 2 AND f_score >= 3 THEN 'під ризиком'
	ELSE 'втрачений'
	END AS segment
FROM rfm_scored
ORDER BY r_score DESC, f_score DESC




