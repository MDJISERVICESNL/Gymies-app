-- Trainer jamai1210@live.nl op Pro-abonnement zetten
-- Uitvoeren op server:
--   mysql ... < database/alter_gymies_user_jamai1210_pro.sql
-- of: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_user_jamai1210_pro.sql

SET @email := 'jamai1210@live.nl';
SET @uid := (SELECT id FROM gymies_users WHERE LOWER(TRIM(email)) = LOWER(TRIM(@email)) LIMIT 1);

-- 1) User als trainer (indien nog klant)
UPDATE gymies_users
SET role = 'trainer',
    email_verified_at = COALESCE(email_verified_at, NOW()),
    updated_at = NOW()
WHERE id = @uid AND @uid IS NOT NULL;

-- 2) Trainerprofiel: subscription_plan pro
INSERT INTO gymies_trainer_profiles (
  user_id, bio, specialty, hourly_rate_cents, region, is_available,
  subscription_plan, mollie_onboarding_status,
  created_at, updated_at
)
SELECT
  u.id,
  'Trainer — Pro abonnement.',
  'Personal training',
  5000,
  'Nederland',
  1,
  'pro',
  'not_started',
  NOW(),
  NOW()
FROM gymies_users u
WHERE u.id = @uid
  AND @uid IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_trainer_profiles p WHERE p.user_id = u.id);

UPDATE gymies_trainer_profiles
SET subscription_plan = 'pro',
    updated_at = NOW()
WHERE user_id = @uid AND @uid IS NOT NULL;

-- 3) Abonnement op Pro-plan (actief)
SET @plan_id := (SELECT id FROM gymies_plans WHERE slug = 'pro' LIMIT 1);

INSERT INTO gymies_subscriptions (
  trainer_user_id, plan_id, status,
  current_period_start, current_period_end, created_at, updated_at
)
SELECT @uid, @plan_id, 'active', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 1 MONTH), NOW(), NOW()
FROM gymies_users u
WHERE u.id = @uid AND @uid IS NOT NULL AND @plan_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM gymies_subscriptions s
    WHERE s.trainer_user_id = @uid AND s.status IN ('active','trialing')
  );

UPDATE gymies_subscriptions s
INNER JOIN gymies_plans p ON p.slug = 'pro'
SET s.plan_id = p.id, s.status = 'active', s.updated_at = NOW(),
    s.current_period_start = COALESCE(s.current_period_start, CURDATE()),
    s.current_period_end = COALESCE(s.current_period_end, DATE_ADD(CURDATE(), INTERVAL 1 MONTH))
WHERE s.trainer_user_id = @uid AND @uid IS NOT NULL;

-- Controle
SELECT @uid AS user_id, @email AS email, @plan_id AS pro_plan_id;
