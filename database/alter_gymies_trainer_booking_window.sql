-- Trainer: hoe ver vooruit klanten mogen boeken (dagen). NULL = platformdefault (180).
-- lead_time_minutes bestaat al (alter_gymies_direct_book.sql).
ALTER TABLE gymies_trainer_profiles
  ADD COLUMN booking_max_days_ahead INT UNSIGNED NULL DEFAULT NULL
  COMMENT 'Max dagen vooruit boekbaar; NULL = platformlimiet (180). Min 1, max 365.';
