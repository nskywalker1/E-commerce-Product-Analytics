# 🛒 E-commerce Product Analytics

Продуктовий аналіз поведінки користувачів на основі даних про події (view, cart, purchase).

---

## 📦 Дані

| Таблиця | Опис |
|---|---|
| `events` | Сирі дані подій користувачів |
| `events_clean` | Очищені дані  |

**Джерело:** [E-commerce Events History in Cosmetics Shop — Kaggle](https://www.kaggle.com/datasets/mkechinov/ecommerce-events-history-in-cosmetics-shop/code)

**Колонки:** `user_id`, `event_time`, `event_type`, `product_id`, `brand`, `category`

**Обсяг:** ~3.5 млн рядків, період — грудень 2019

---

## 🧹 Підготовка даних

### Очищення данних
Знайдено та видалено **185,220 дублікатів** по ключах `user_id`, `event_time`, `product_id`, `event_type`.

```sql
CREATE TABLE events_clean AS
SELECT DISTINCT ON (user_id, event_time, product_id, event_type) *
FROM events
ORDER BY user_id, event_time, product_id, event_type;
```

### Missing Data
Колонки `brand` і `category` мали пропуски. Оскільки вони не є критичними для основного аналізу — замінено на `'unknown'`.

```sql
UPDATE events_clean SET brand = 'unknown' WHERE brand IS NULL;
UPDATE events_clean SET category = 'unknown' WHERE category IS NULL;
```

---

## 🔻 Воронка конверсії

```sql
WITH funnel AS (
  SELECT
    user_id,
    MAX(CASE WHEN event_type = 'view'     THEN 1 ELSE 0 END) AS viewed,
    MAX(CASE WHEN event_type = 'cart'     THEN 1 ELSE 0 END) AS added,
    MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS purchased
  FROM events_clean
  GROUP BY user_id
)
SELECT
  COUNT(*)                                                        AS total_users,
  SUM(viewed)                                                     AS viewed_users,
  SUM(added)                                                      AS added_users,
  SUM(purchased)                                                  AS purchased_users,
  ROUND(SUM(added) * 100.0 / NULLIF(SUM(viewed), 0), 2)          AS view_to_cart_cr,
  ROUND(SUM(purchased) * 100.0 / NULLIF(SUM(added), 0), 2)       AS cart_to_purchase_cr
FROM funnel;
```

**Результат:**

| total_users | viewed | added | purchased | view→cart | cart→purchase |
|---|---|---|---|---|---|
| 370,154 | 358,212 | 83,458 | 25,613 | 23.30% | 30.69% |

**Висновки:**
- 97% юзерів переглядають товари — трафік якісний
- Конверсія view→cart лише 23% — головна точка втрат. Можлива причина: ціна, якість фото, опис товару
- 70% кидають кошик без покупки. Рішення: email-нагадування або знижка

---

## 📅 Когортний ретеншн

```sql
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
ORDER BY cohort_day, day_since_signup;
```

**Результат (когорта грудень 2019):**

| День | Активних юзерів | Ретеншн |
|---|---|---|
| 0 | 17,540 | 100% |
| 1 | 2,315 | 13.2% |
| 7 | 1,062 | 6.1% |
| 14 | 799 | 4.6% |

**Висновки:**
- День 1 ретеншн — лише 13%. Норма для e-commerce 20-30% — це критично низько
- Після дня 7 стабілізується на ~1000 юзерів — це лояльні
- Різкий обвал в перший день сигналізує про проблему з першим досвідом користувача

---

## 👥 RFM-сегментація

```sql
WITH max_date AS (
  SELECT MAX(event_time)::date AS last_date FROM events_clean
),
rfm AS (
  SELECT
    user_id,
    MAX(event_time)                                           AS last_purchase,
    COUNT(*)                                                  AS frequency,
    (SELECT last_date FROM max_date) - MAX(event_time)::date  AS recency_days
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
    WHEN r_score >= 3 AND f_score >= 3 THEN 'лояльний'
    WHEN r_score >= 3 AND f_score <= 2 THEN 'новий'
    WHEN r_score <= 2 AND f_score >= 3 THEN 'під ризиком'
    ELSE 'втрачений'
  END AS segment
FROM rfm_scored
ORDER BY r_score DESC, f_score DESC;
```

**Висновки:**
- Навіть "чемпіони" купують 1-3 рази — великий потенціал для збільшення частоти через персоналізацію
- Сегмент "під ризиком" потребує реактивації через знижки або нагадування
- RFM дозволяє маркетингу таргетувати кожен сегмент окремо

---

## 🛠 Стек

- **База даних:** PostgreSQL
- **Мова:** SQL
- **Інструменти:** DBeaver

---

## 📁 Структура проекту

```
├── README.md
├── ecommerce_analysis.sql
```
