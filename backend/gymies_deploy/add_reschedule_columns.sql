-- Migration: Add reschedule proposal columns to gymies_bookings
-- Run on server: mysql -u root gymies < add_reschedule_columns.sql
-- Or via: ssh gymies "cd /var/www/gymies && php artisan tinker" and paste the PHP version below.

-- 1. proposed_scheduled_at: de voorgestelde nieuwe datum/tijd
ALTER TABLE gymies_bookings
  ADD COLUMN IF NOT EXISTS proposed_scheduled_at TIMESTAMP NULL DEFAULT NULL AFTER scheduled_at;

-- 2. proposed_duration_minutes: de voorgestelde duur
ALTER TABLE gymies_bookings
  ADD COLUMN IF NOT EXISTS proposed_duration_minutes SMALLINT UNSIGNED NULL DEFAULT NULL AFTER proposed_scheduled_at;

-- 3. proposed_by_user_id: wie het verzoek indiende
ALTER TABLE gymies_bookings
  ADD COLUMN IF NOT EXISTS proposed_by_user_id BIGINT UNSIGNED NULL DEFAULT NULL AFTER proposed_duration_minutes;

-- 4. proposed_at: wanneer het verzoek is ingediend
ALTER TABLE gymies_bookings
  ADD COLUMN IF NOT EXISTS proposed_at TIMESTAMP NULL DEFAULT NULL AFTER proposed_by_user_id;

-- Verificatie:
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'gymies_bookings'
  AND COLUMN_NAME IN ('proposed_scheduled_at', 'proposed_duration_minutes', 'proposed_by_user_id', 'proposed_at')
ORDER BY ORDINAL_POSITION;
