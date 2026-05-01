-- Elite: Koppeling groepsles en boeking aan gym-locatie
-- Run na alter_gym_locations.sql
-- Bij herhaald uitvoeren: Duplicate column/key wordt gelogd, script gaat door

SET NAMES utf8mb4;

-- Groepsles → locatie (voor conflict-check)
ALTER TABLE gymies_group_sessions
  ADD COLUMN gym_location_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Gym-locatie (zaal) voor Elite' AFTER trainer_location_id;

ALTER TABLE gymies_group_sessions
  ADD KEY gymies_group_sessions_gym_location (gym_location_id);

-- Boeking → locatie (voor gym-trainers)
ALTER TABLE gymies_bookings
  ADD COLUMN gym_location_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Gym-locatie voor Elite' AFTER trainer_location_id;

ALTER TABLE gymies_bookings
  ADD KEY gymies_bookings_gym_location (gym_location_id);
