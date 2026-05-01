-- ============================================================
-- QR-testboeking: demo-klant + demo-trainer
-- Boeking gepland over 10 minuten – QR wordt direct zichtbaar (15 min vóór aanvang).
-- Voer uit vóór je de QR-functie wilt testen:
--   cd /var/www/gymies && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/seed_gymies_demo_qr_test_booking.sql
-- Daarna: log in als demo-klant (QR tonen) én demo-trainer (scannen) op twee apparaten.
-- ============================================================

SET NAMES utf8mb4;

SET @demo_trainer_id := (SELECT id FROM gymies_users WHERE email = 'demo@gymies.nl' LIMIT 1);
SET @demo_client_id := (SELECT id FROM gymies_users WHERE email = 'demo-klant@gymies.nl' LIMIT 1);
SET @loc_id := (SELECT id FROM gymies_trainer_locations WHERE trainer_user_id = @demo_trainer_id LIMIT 1);

INSERT INTO gymies_bookings (
  client_user_id, trainer_user_id, scheduled_at, duration_minutes, status,
  amount_cents, trainer_location_id, payment_method, location_notes, created_at, updated_at
)
SELECT @demo_client_id, @demo_trainer_id, DATE_ADD(NOW(), INTERVAL 10 MINUTE), 60, 'confirmed',
  6500, @loc_id, 'mollie_connect', 'QR-test sessie', NOW(), NOW()
FROM DUAL
WHERE @demo_client_id IS NOT NULL AND @demo_trainer_id IS NOT NULL AND @loc_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM gymies_bookings b
    WHERE b.client_user_id = @demo_client_id AND b.trainer_user_id = @demo_trainer_id
      AND b.scheduled_at > NOW() AND b.scheduled_at < DATE_ADD(NOW(), INTERVAL 30 MINUTE)
      AND b.status = 'confirmed'
  );
