-- Testgroepsles voor UX scherm "Groepslessen zoeken" (publieke lijst).
-- Vereist: kolom status op gymies_group_sessions (collecting).
-- Gebruikt demo-trainer demo@gymies.nl; zorgt zo nodig voor een locatie + Amsterdam lat/lng (radius-filter).
-- Idempotent: één rij met vaste titel [UX-test] Groepsles HIIT.
-- Uitvoeren op server: cd /var/www/gymies && sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/seed_gymies_test_group_session_ux.sql

SET @demo_trainer_id := (SELECT id FROM gymies_users WHERE email = 'demo@gymies.nl' LIMIT 1);

INSERT INTO gymies_trainer_locations (trainer_user_id, name, address_line1, postcode, city, latitude, longitude, location_type, is_primary, created_at, updated_at)
SELECT @demo_trainer_id, 'Gym Amsterdam (UX-test)', 'Damrak 1', '1012 LG', 'Amsterdam', 52.3727000, 4.8936000, 'gym', 1, NOW(), NOW()
FROM DUAL
WHERE @demo_trainer_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_trainer_locations')
  AND NOT EXISTS (SELECT 1 FROM gymies_trainer_locations WHERE trainer_user_id = @demo_trainer_id);

UPDATE gymies_trainer_locations
SET latitude = 52.3727000, longitude = 4.8936000
WHERE trainer_user_id = @demo_trainer_id
  AND @demo_trainer_id IS NOT NULL
  AND (location_type IS NULL OR location_type IN ('gym', 'home', 'outdoor'));

SET @loc_id := (
  SELECT id FROM gymies_trainer_locations
  WHERE trainer_user_id = @demo_trainer_id
  ORDER BY is_primary DESC, id ASC
  LIMIT 1
);

INSERT INTO gymies_group_sessions (trainer_user_id, title, description, scheduled_at, duration_minutes, max_participants, price_cents, trainer_location_id, status, created_at, updated_at)
SELECT
  @demo_trainer_id,
  '[UX-test] Groepsles HIIT',
  'Demo voor het zoekscherm: gepubliceerde groepsles met plek. Titel begint met [UX-test] zodat je hem herkent.',
  DATE_ADD(NOW(), INTERVAL 3 DAY),
  45,
  10,
  2500,
  @loc_id,
  'collecting',
  NOW(),
  NOW()
FROM DUAL
WHERE @demo_trainer_id IS NOT NULL
  AND @loc_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_group_sessions')
  AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'gymies_group_sessions' AND column_name = 'status'
  )
  AND NOT EXISTS (
    SELECT 1 FROM gymies_group_sessions
    WHERE trainer_user_id = @demo_trainer_id AND title = '[UX-test] Groepsles HIIT'
  );
