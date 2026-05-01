-- Spoed Inval Stand-by: trainer geeft proactief aan beschikbaar te zijn voor spoed vandaag.
-- Kolom: spoed_inval_standby_date = vandaag (DATE) → trainer staat bovenaan bij kandidaat-selectie.
--
-- Voer uit na alter_gymies_spoed_inval.sql

ALTER TABLE gymies_trainer_profiles
  ADD COLUMN spoed_inval_standby_date DATE NULL DEFAULT NULL
  COMMENT 'Vandaag = beschikbaar voor spoed inval; NULL = niet in stand-by'
  AFTER is_available;
