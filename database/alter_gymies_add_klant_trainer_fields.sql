-- Migratie: klant- en trainervelden toevoegen (telefoon, verified, regio)
-- Uitvoeren als de tabellen gymies_* al bestaan.
-- Nieuwe installaties: gebruik create_gymies_tables.sql (bevat deze velden al).
-- Voer elke ALTER één keer uit; bij opnieuw uitvoeren kun je "Duplicate column" krijgen.

SET NAMES utf8mb4;

-- gymies_users: telefoon en phone_verified_at
ALTER TABLE gymies_users
  ADD COLUMN phone VARCHAR(32) DEFAULT NULL COMMENT 'Telefoonnummer voor contact' AFTER display_name,
  ADD COLUMN phone_verified_at TIMESTAMP NULL DEFAULT NULL AFTER email_verified_at;

-- gymies_trainer_profiles: regio en trainer_verified_at
ALTER TABLE gymies_trainer_profiles
  ADD COLUMN region VARCHAR(255) DEFAULT NULL COMMENT 'Regio(s) actief' AFTER avatar_url,
  ADD COLUMN trainer_verified_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Platform heeft trainer gecontroleerd' AFTER region;
