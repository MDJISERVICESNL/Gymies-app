-- Optionele toeslagen voor etalage-tarieven (eigen baas / dynamische prijslijst).
-- Na deploy: PUT trainer/me kan duo_surcharge_cents en travel_surcharge_cents meesturen.

-- Voer apart uit als één statement faalt (kolom bestaat al).
ALTER TABLE gymies_trainer_profiles
  ADD COLUMN duo_surcharge_cents INT NULL DEFAULT NULL COMMENT 'Vaste toeslag duo per sessie (cent)';

ALTER TABLE gymies_trainer_profiles
  ADD COLUMN travel_surcharge_cents INT NULL DEFAULT NULL COMMENT 'Vaste toeslag aan huis per sessie (cent)';
