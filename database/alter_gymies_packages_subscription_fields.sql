-- Uitbreiding pakketten voor trainer-abonnementen in profiel.
SET NAMES utf8mb4;

ALTER TABLE gymies_packages
  ADD COLUMN lesson_type ENUM('solo', 'duo', 'group') NOT NULL DEFAULT 'solo' AFTER name,
  ADD COLUMN weeks_count INT UNSIGNED NOT NULL DEFAULT 1 AFTER sessions_count;
