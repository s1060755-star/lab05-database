SELECT * FROM public.trainer_summary;

SELECT
    (SELECT COUNT(*) FROM members) AS members_count,
    (SELECT COUNT(*) FROM trainers) AS trainers_count,
    (SELECT COUNT(*) FROM workouts) AS workouts_count,
    (SELECT COUNT(*) FROM subscriptions) AS subscriptions_count,
    (SELECT COALESCE(SUM(price), 0.00) FROM subscriptions WHERE is_active) AS active_revenue;