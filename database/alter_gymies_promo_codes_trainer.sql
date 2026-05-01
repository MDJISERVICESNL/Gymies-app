-- Trainer-eigen promo codes: koppeling aan trainer_user_id.
-- Na migratie: checkout accepteert alleen codes waar trainer_user_id = boeking.trainer_user_id
-- (platform-codes zonder trainer_user_id worden bij betaling geweigerd).
-- Voer uit op productie na deploy backend.

ALTER TABLE gymies_promo_codes
  ADD COLUMN trainer_user_id BIGINT UNSIGNED NULL DEFAULT NULL
    COMMENT 'NULL = legacy/platform; bij betaling niet meer geldig. Alleen codes van deze trainer mogen op zijn boekingen.'
    AFTER id;

ALTER TABLE gymies_promo_codes
  ADD KEY gymies_promo_codes_trainer (trainer_user_id),
  ADD CONSTRAINT gymies_promo_codes_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE;

-- Bestaande rijen blijven NULL → niet bruikbaar bij betaling tot trainer nieuwe code aanmaakt
-- of tot handmatig trainer_user_id gezet wordt.
