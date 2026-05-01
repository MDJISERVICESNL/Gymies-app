-- Eénmalig: zaldion75@gmail.com — e-mail geverifieerd + Starter-plan (trainer).
-- Server: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_user_zaldion_starter_verified.sql
-- Of: mysql ... < gymies_deploy/alter_gymies_user_zaldion_starter_verified.sql

SET @email := 'zaldion75@gmail.com';

-- 1) E-mail geverifieerd (kolom moet bestaan; anders stap overslaan)
UPDATE gymies_users
SET email_verified_at = COALESCE(email_verified_at, NOW()),
    updated_at = NOW()
WHERE LOWER(TRIM(email)) = LOWER(TRIM(@email))
LIMIT 1;

-- 2) Verificatiecodes opruimen voor die user
DELETE FROM gymies_email_verification_codes
WHERE user_id = (SELECT id FROM gymies_users WHERE LOWER(TRIM(email)) = LOWER(TRIM(@email)) LIMIT 1);

-- 3) Alleen als trainer: subscription_plan op profiel + actief abonnement Starter
SET @uid := (SELECT id FROM gymies_users WHERE LOWER(TRIM(email)) = LOWER(TRIM(@email)) LIMIT 1);
SET @plan_id := (SELECT id FROM gymies_plans WHERE slug = 'starter' LIMIT 1);

-- Trainerprofiel: subscription_plan slug
UPDATE gymies_trainer_profiles
SET subscription_plan = 'starter'
WHERE user_id = @uid
  AND @uid IS NOT NULL;

-- Abonnement: één rij active voor trainer (geen Mollie nodig voor handmatige grant)
-- Alleen als tabellen bestaan en user trainer is
INSERT INTO gymies_subscriptions (
  trainer_user_id,
  plan_id,
  status,
  current_period_start,
  current_period_end,
  created_at,
  updated_at
)
SELECT
  u.id,
  p.id,
  'active',
  CURDATE(),
  DATE_ADD(CURDATE(), INTERVAL 1 MONTH),
  NOW(),
  NOW()
FROM gymies_users u
CROSS JOIN gymies_plans p
WHERE LOWER(TRIM(u.email)) = LOWER(TRIM(@email))
  AND u.role = 'trainer'
  AND p.slug = 'starter'
  AND NOT EXISTS (
    SELECT 1 FROM gymies_subscriptions s
    WHERE s.trainer_user_id = u.id AND s.status IN ('active','trialing')
  )
LIMIT 1;

-- Als er al een subscription was maar ander plan: update naar starter
UPDATE gymies_subscriptions s
INNER JOIN gymies_users u ON u.id = s.trainer_user_id
INNER JOIN gymies_plans p ON p.slug = 'starter'
SET s.plan_id = p.id,
    s.status = 'active',
    s.updated_at = NOW()
WHERE LOWER(TRIM(u.email)) = LOWER(TRIM(@email))
  AND u.role = 'trainer';
