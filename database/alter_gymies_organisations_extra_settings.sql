-- Elite: Extra gym-instellingen (logo, openingstijden, standaard locatie)
-- Run na alter_gym_locations.sql (voor default_location_id FK)

SET NAMES utf8mb4;

ALTER TABLE gymies_organisations
  ADD COLUMN IF NOT EXISTS logo_url VARCHAR(512) DEFAULT NULL COMMENT 'Logo URL voor gym' AFTER payout_minimum_cents;

ALTER TABLE gymies_organisations
  ADD COLUMN IF NOT EXISTS opening_hours_json JSON DEFAULT NULL COMMENT 'Openingstijden per dag (bijv. {"mon":"09:00-18:00","tue":"09:00-18:00"})' AFTER logo_url;

ALTER TABLE gymies_organisations
  ADD COLUMN IF NOT EXISTS default_location_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Standaard gym-locatie' AFTER opening_hours_json;

ALTER TABLE gymies_organisations
  ADD KEY IF NOT EXISTS gymies_organisations_default_location (default_location_id);
