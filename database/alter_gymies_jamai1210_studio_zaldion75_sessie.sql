-- ============================================================
-- jamai1210@live.nl → Studio/Elite + zaldion75 sessie met jamai1210 (zsm)
-- 1) jamai1210 op Studio-abonnement
-- 2) zaldion75 als trainer met locatie (indien nodig)
-- 3) Boeking: zaldion75 (trainer) geeft sessie aan jamai1210 (klant), over 10 min
--
-- Server: cd /var/www/gymies && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_jamai1210_studio_zaldion75_sessie.sql
-- ============================================================

SET NAMES utf8mb4;

-- ========== 1) jamai1210@live.nl → Studio/Elite ==========
SET @jamai_id := (SELECT id FROM gymies_users WHERE email = 'jamai1210@live.nl' LIMIT 1);

UPDATE gymies_trainer_profiles
SET subscription_plan = 'studio',
    updated_at = NOW()
WHERE user_id = @jamai_id AND @jamai_id IS NOT NULL;

SET @studio_plan_id := (SELECT id FROM gymies_plans WHERE slug = 'studio' LIMIT 1);

INSERT INTO gymies_subscriptions (
  trainer_user_id, plan_id, status,
  current_period_start, current_period_end, created_at, updated_at
)
SELECT @jamai_id, @studio_plan_id, 'active', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 1 MONTH), NOW(), NOW()
FROM gymies_users u
WHERE u.id = @jamai_id AND @jamai_id IS NOT NULL AND @studio_plan_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM gymies_subscriptions s
    WHERE s.trainer_user_id = @jamai_id AND s.status IN ('active','trialing')
  );

UPDATE gymies_subscriptions s
INNER JOIN gymies_plans p ON p.slug = 'studio'
SET s.plan_id = p.id, s.status = 'active', s.updated_at = NOW(),
    s.current_period_start = COALESCE(s.current_period_start, CURDATE()),
    s.current_period_end = COALESCE(s.current_period_end, DATE_ADD(CURDATE(), INTERVAL 1 MONTH))
WHERE s.trainer_user_id = @jamai_id AND @jamai_id IS NOT NULL;

-- ========== 2) zaldion75@gmail.com als trainer + locatie ==========
SET @zaldion_id := (SELECT id FROM gymies_users WHERE email = 'zaldion75@gmail.com' LIMIT 1);

UPDATE gymies_users
SET role = 'trainer',
    display_name = COALESCE(NULLIF(TRIM(display_name), ''), 'Demo Trainer'),
    email_verified_at = COALESCE(email_verified_at, NOW()),
    phone = COALESCE(phone, '+31612345678'),
    updated_at = NOW()
WHERE id = @zaldion_id AND @zaldion_id IS NOT NULL;

INSERT INTO gymies_trainer_profiles (
  user_id, bio, specialty, hourly_rate_cents, region, is_available,
  subscription_plan, mollie_onboarding_status,
  created_at, updated_at
)
SELECT u.id, 'Demo-trainer.', 'Kracht & conditie', 4500, 'Amsterdam', 1, 'pro', 'not_started', NOW(), NOW()
FROM gymies_users u
WHERE u.id = @zaldion_id AND @zaldion_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_trainer_profiles p WHERE p.user_id = u.id);

UPDATE gymies_trainer_profiles
SET subscription_plan = COALESCE(subscription_plan, 'pro'), is_available = 1, updated_at = NOW()
WHERE user_id = @zaldion_id AND @zaldion_id IS NOT NULL;

INSERT INTO gymies_trainer_locations (trainer_user_id, location_type, name, address_line1, postcode, city, is_primary)
SELECT @zaldion_id, 'gym', 'Gym Amsterdam', 'Damrak 1', '1012 LG', 'Amsterdam', 1
FROM DUAL WHERE @zaldion_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM gymies_trainer_locations WHERE trainer_user_id = @zaldion_id);

SET @pro_plan_id := (SELECT id FROM gymies_plans WHERE slug = 'pro' LIMIT 1);
INSERT INTO gymies_subscriptions (trainer_user_id, plan_id, status, current_period_start, current_period_end, created_at, updated_at)
SELECT @zaldion_id, @pro_plan_id, 'active', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 1 MONTH), NOW(), NOW()
FROM gymies_users u
WHERE u.id = @zaldion_id AND @zaldion_id IS NOT NULL AND @pro_plan_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_subscriptions s WHERE s.trainer_user_id = @zaldion_id AND s.status IN ('active','trialing'));

SET @loc_id := (SELECT id FROM gymies_trainer_locations WHERE trainer_user_id = @zaldion_id LIMIT 1);

-- ========== 3) Boeking: zaldion75 (trainer) + jamai1210 (klant), zsm (10 min) ==========
INSERT INTO gymies_bookings (
  client_user_id, trainer_user_id, scheduled_at, duration_minutes, status,
  amount_cents, trainer_location_id, payment_method, location_notes, created_at, updated_at
)
SELECT @jamai_id, @zaldion_id, DATE_ADD(NOW(), INTERVAL 10 MINUTE), 60, 'confirmed',
  5000, @loc_id, 'mollie_connect', 'Sessie zaldion75 met jamai1210 (zsm)', NOW(), NOW()
FROM DUAL
WHERE @jamai_id IS NOT NULL AND @zaldion_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM gymies_bookings b
    WHERE b.client_user_id = @jamai_id AND b.trainer_user_id = @zaldion_id
      AND b.scheduled_at > NOW() AND b.scheduled_at < DATE_ADD(NOW(), INTERVAL 1 HOUR)
      AND b.status IN ('confirmed','pending')
  );
