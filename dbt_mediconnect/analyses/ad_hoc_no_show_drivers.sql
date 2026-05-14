-- ad_hoc_no_show_drivers.sql
-- Exploratory analysis of no-show drivers across channels, specialties and countries.

-- 1. No-show rate breakdown: channel × specialty × country
SELECT
    channel,
    specialty_id,
    country_id,
    COUNT(*)                                AS total_appointments,
    COUNTIF(status = 'no_show')             AS no_shows,
    SAFE_DIVIDE(
        COUNTIF(status = 'no_show'), COUNT(*)
    )                                       AS no_show_rate
FROM {{ ref('fct_appointments') }}
GROUP BY channel, specialty_id, country_id
HAVING total_appointments >= 10     -- filter out low-volume combinations
ORDER BY no_show_rate DESC
LIMIT 30;


-- 2. Worst channel per specialty by no-show rate
SELECT
    specialty_id,
    channel,
    no_shows,
    total_appointments,
    no_show_rate
FROM (
    SELECT
        specialty_id,
        channel,
        COUNTIF(status = 'no_show')         AS no_shows,
        COUNT(*)                            AS total_appointments,
        SAFE_DIVIDE(
            COUNTIF(status = 'no_show'), COUNT(*)
        )                                   AS no_show_rate
    FROM {{ ref('fct_appointments') }}
    GROUP BY specialty_id, channel
    HAVING total_appointments >= 10
)
QUALIFY RANK() OVER (PARTITION BY specialty_id ORDER BY no_show_rate DESC) = 1
ORDER BY no_show_rate DESC;


-- 3. No-show trend over time
SELECT
    DATE_TRUNC(appointment_date, MONTH)     AS month,
    COUNT(*)                                AS total_appointments,
    COUNTIF(status = 'no_show')             AS no_shows,
    SAFE_DIVIDE(
        COUNTIF(status = 'no_show'), COUNT(*)
    )                                       AS no_show_rate,
    AVG(SAFE_DIVIDE(
        COUNTIF(status = 'no_show'), COUNT(*)
    )) OVER (
        ORDER BY DATE_TRUNC(appointment_date, MONTH)
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    )                                       AS no_show_rate_3m_avg
FROM {{ ref('fct_appointments') }}
GROUP BY month
ORDER BY month;


-- 4. Doctor rating vs no-show rate (do higher-rated doctors have fewer no-shows?)
SELECT
    ROUND(avg_doctor_rating, 1)             AS rating_bucket,
    COUNT(*)                                AS total_appointments,
    SAFE_DIVIDE(
        COUNTIF(status = 'no_show'), COUNT(*)
    )                                       AS no_show_rate
FROM {{ ref('mart_appointment_quality') }}
GROUP BY rating_bucket
ORDER BY rating_bucket DESC;


-- 5. Days between booking and appointment vs no-show probability
WITH booking_lead_time AS (
    SELECT
        appointment_id,
        status,
        DATE_DIFF(
            DATE(appointment_start_at),
            DATE(appointment_created_at),
            DAY
        )                                   AS days_advance_booking
    FROM {{ ref('fct_appointments') }}
)
SELECT
    CASE
        WHEN days_advance_booking = 0 THEN 'same_day'
        WHEN days_advance_booking <= 3  THEN '1-3_days'
        WHEN days_advance_booking <= 7  THEN '4-7_days'
        WHEN days_advance_booking <= 14 THEN '8-14_days'
        ELSE '15+_days'
    END                                     AS booking_window,
    COUNT(*)                                AS appointments,
    SAFE_DIVIDE(
        COUNTIF(status = 'no_show'), COUNT(*)
    )                                       AS no_show_rate
FROM booking_lead_time
GROUP BY booking_window
ORDER BY no_show_rate DESC;
