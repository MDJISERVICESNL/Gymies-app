-- Direct Boeken (PT): reserved status, 10 min betaal-lock, lead time per trainer.
-- Zie Cursor assets/direct-boeken-ecosysteem.md

-- Boeking: status 'reserved' voor betaal-lock (10 min). Bij Duplicate column/modify negeren.
ALTER TABLE gymies_bookings
  MODIFY COLUMN status ENUM('pending','confirmed','cancelled','completed','no_show','reserved') NOT NULL DEFAULT 'pending';

ALTER TABLE gymies_bookings
  ADD COLUMN reserved_until TIMESTAMP NULL DEFAULT NULL
  COMMENT 'Einde betaal-lock (10 min). Alleen bij status reserved.';

-- Lead time: minimaal X minuten van tevoren direct boekbaar (standaard 4 uur = 240).
ALTER TABLE gymies_trainer_profiles
  ADD COLUMN lead_time_minutes INT UNSIGNED NOT NULL DEFAULT 240
  COMMENT 'Slots korter dan X min voor start zijn niet direct boekbaar. Standaard 240 (4u).';
