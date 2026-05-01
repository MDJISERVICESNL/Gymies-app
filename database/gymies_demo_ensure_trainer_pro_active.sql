-- ============================================================
-- Minimaal: demo@gymies.nl — account actief + trainer Pro + actieve subscription
-- (Geen nieuwe users/boekingen; gebruik seed_gymies_demo_account_full.sql voor volledige demo.)
-- ============================================================
-- Server (vanaf Laravel-root):
--   php scripts/run_migrate_gymies_sql_server.php database/gymies_demo_ensure_trainer_pro_active.sql
-- Of na upload naar gymies_deploy:
--   mysql -u USER -p DB < gymies_demo_ensure_trainer_pro_active.sql
-- ============================================================

SET NAMES utf8mb4;

SET @demo_trainer_id := (SELECT id FROM gymies_users WHERE email = 'demo@gymies.nl' LIMIT 1);

UPDATE gymies_users SET
  is_suspended = 0,
  suspended_reason = NULL,
  suspended_at = NULL,
  role = 'trainer',
  email_verified_at = COALESCE(email_verified_at, NOW()),
  phone_verified_at = COALESCE(phone_verified_at, NOW()),
  trainer_approved_at = COALESCE(trainer_approved_at, NOW())
WHERE id = @demo_trainer_id AND @demo_trainer_id IS NOT NULL;

UPDATE gymies_trainer_profiles SET
  subscription_plan = 'pro',
  mollie_onboarding_status = 'completed'
WHERE user_id = @demo_trainer_id AND @demo_trainer_id IS NOT NULL;

-- Zelfde logica als seed_gymies_demo_account_full.sql §7
SET @demo_sub_id := (SELECT MAX(id) FROM gymies_subscriptions WHERE trainer_user_id = @demo_trainer_id);

UPDATE gymies_subscriptions
SET status = 'cancelled',
    cancelled_at = COALESCE(cancelled_at, NOW()),
    updated_at = NOW()
WHERE trainer_user_id = @demo_trainer_id
  AND @demo_trainer_id IS NOT NULL
  AND (@demo_sub_id IS NULL OR id <> @demo_sub_id);

INSERT INTO gymies_subscriptions (trainer_user_id, plan_id, status, current_period_start, current_period_end, created_at, updated_at)
SELECT @demo_trainer_id, p.id, 'active', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 12 MONTH), NOW(), NOW()
FROM gymies_plans p
WHERE p.slug = 'pro'
  AND @demo_trainer_id IS NOT NULL
  AND @demo_sub_id IS NULL;

SET @demo_sub_active_id := COALESCE(
  @demo_sub_id,
  (SELECT MAX(id) FROM gymies_subscriptions WHERE trainer_user_id = @demo_trainer_id)
);

UPDATE gymies_subscriptions s
INNER JOIN gymies_plans p ON p.slug = 'pro'
SET s.plan_id = p.id,
    s.status = 'active',
    s.current_period_start = CURDATE(),
    s.current_period_end = DATE_ADD(CURDATE(), INTERVAL 12 MONTH),
    s.cancelled_at = NULL,
    s.updated_at = NOW()
WHERE s.trainer_user_id = @demo_trainer_id
  AND @demo_trainer_id IS NOT NULL
  AND @demo_sub_active_id IS NOT NULL
  AND s.id = @demo_sub_active_id;
