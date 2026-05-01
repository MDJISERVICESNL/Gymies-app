-- ============================================================
-- Fix: zaldion75 = klant, jamai1210 = trainer (was omgekeerd)
-- 1) zaldion75 terug naar klant (verwijder trainer-spul)
-- 2) Verkeerde boeking annuleren (zaldion75 trainer, jamai1210 klant)
-- 3) Nieuwe boeking: jamai1210 (trainer) geeft sessie aan zaldion75 (klant), zsm
--
-- Server: cd /var/www/gymies && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_fix_zaldion75_klant_jamai1210_trainer.sql
-- ============================================================

SET NAMES utf8mb4;

SET @jamai_id := (SELECT id FROM gymies_users WHERE email = 'jamai1210@live.nl' LIMIT 1);
SET @zaldion_id := (SELECT id FROM gymies_users WHERE email = 'zaldion75@gmail.com' LIMIT 1);

-- ========== 1) zaldion75 terug naar klant ==========
UPDATE gymies_users
SET role = 'klant',
    updated_at = NOW()
WHERE id = @zaldion_id AND @zaldion_id IS NOT NULL;

-- Verwijder trainer-subscription van zaldion75 (klanten hebben geen gymies_subscriptions als trainer)
DELETE FROM gymies_subscriptions WHERE trainer_user_id = @zaldion_id AND @zaldion_id IS NOT NULL;

-- ========== 2) Verkeerde boeking annuleren (zaldion75 trainer, jamai1210 klant) ==========
UPDATE gymies_bookings
SET status = 'cancelled',
    updated_at = NOW()
WHERE trainer_user_id = @zaldion_id
  AND client_user_id = @jamai_id
  AND @zaldion_id IS NOT NULL
  AND @jamai_id IS NOT NULL;

-- ========== 3) Locatie voor jamai1210 (indien nog geen) ==========
INSERT INTO gymies_trainer_locations (trainer_user_id, location_type, name, address_line1, postcode, city, is_primary)
SELECT @jamai_id, 'gym', 'Gym Amsterdam', 'Damrak 1', '1012 LG', 'Amsterdam', 1
FROM DUAL
WHERE @jamai_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_trainer_locations WHERE trainer_user_id = @jamai_id);

SET @loc_id := (SELECT id FROM gymies_trainer_locations WHERE trainer_user_id = @jamai_id LIMIT 1);

-- ========== 4) Nieuwe boeking: jamai1210 (trainer) + zaldion75 (klant), zsm ==========
INSERT INTO gymies_bookings (
  client_user_id, trainer_user_id, scheduled_at, duration_minutes, status,
  amount_cents, trainer_location_id, payment_method, location_notes, created_at, updated_at
)
SELECT @zaldion_id, @jamai_id, DATE_ADD(NOW(), INTERVAL 10 MINUTE), 60, 'confirmed',
  6700, @loc_id, 'mollie_connect', 'Sessie jamai1210 met zaldion75 (zsm)', NOW(), NOW()
FROM DUAL
WHERE @jamai_id IS NOT NULL AND @zaldion_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM gymies_bookings b
    WHERE b.client_user_id = @zaldion_id AND b.trainer_user_id = @jamai_id
      AND b.scheduled_at > NOW() AND b.scheduled_at < DATE_ADD(NOW(), INTERVAL 1 HOUR)
      AND b.status IN ('confirmed','pending')
  );
