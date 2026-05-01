-- Dummy trainer + Pro-plan voor zaldion75@gmail.com
-- Server: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_user_zaldion75_dummy_starter.sql

SET @email := 'zaldion75@gmail.com';
SET @uid := (SELECT id FROM gymies_users WHERE LOWER(TRIM(email)) = LOWER(TRIM(@email)) LIMIT 1);

-- 1) User als trainer + zichtbare naam
UPDATE gymies_users
SET role = 'trainer',
    display_name = COALESCE(NULLIF(TRIM(display_name), ''), 'Demo Trainer Pro'),
    email_verified_at = COALESCE(email_verified_at, NOW()),
    phone = COALESCE(phone, '+31612345678'),
    updated_at = NOW()
WHERE id = @uid AND @uid IS NOT NULL;

-- 2) Trainerprofiel: pro + dummy velden (INSERT als nog geen rij)
INSERT INTO gymies_trainer_profiles (
  user_id, bio, specialty, hourly_rate_cents, region, is_available,
  subscription_plan, mollie_onboarding_status,
  created_at, updated_at
)
SELECT
  u.id,
  'Demo-profiel: Pro — groepslessen, Mollie, pakketten.',
  'Kracht & conditie',
  4500,
  'Amsterdam',
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
SET bio = COALESCE(NULLIF(TRIM(bio), ''), 'Demo-profiel: Pro — groepslessen, Mollie, pakketten.'),
    specialty = COALESCE(NULLIF(TRIM(specialty), ''), 'Kracht & conditie'),
    hourly_rate_cents = COALESCE(hourly_rate_cents, 4500),
    region = COALESCE(NULLIF(TRIM(region), ''), 'Amsterdam'),
    subscription_plan = 'pro',
    is_available = 1,
    updated_at = NOW()
WHERE user_id = @uid AND @uid IS NOT NULL;

-- 3) Verificatiecodes weg
DELETE FROM gymies_email_verification_codes WHERE user_id = @uid;

-- 4) Abonnement op Pro-plan
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
SET s.plan_id = p.id, s.status = 'active', s.updated_at = NOW()
WHERE s.trainer_user_id = @uid AND @uid IS NOT NULL;
