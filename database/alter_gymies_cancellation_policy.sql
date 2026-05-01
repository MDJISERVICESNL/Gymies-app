-- Annuleringsbeleid Gymies: trainerbalans (boetes €25) en audit penalty-transacties.
-- Platformregel: 48u / 24u / <24u (zie Cursor assets/annuleringsbeleid-gymies.md).
-- Trainerbalans: eenmalig draaien. Bij Duplicate column negeren.

ALTER TABLE gymies_users
  ADD COLUMN trainer_balance_cents INT NOT NULL DEFAULT 0
  COMMENT 'Trainer-saldo in centen. Negatief = boete (bv. -2500 = €25). Wordt verrekend bij volgende uitbetaling.';

-- Penalty-audit (elke €25 boete wordt hier gelogd)
CREATE TABLE IF NOT EXISTS gymies_trainer_penalties (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  amount_cents INT NOT NULL COMMENT 'Negatief, bijv. -2500 voor €25 boete',
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  reason VARCHAR(64) NOT NULL DEFAULT 'late_cancellation' COMMENT 'late_cancellation, trainer_no_show',
  balance_after_cents INT NOT NULL COMMENT 'trainer_balance_cents na deze transactie',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_trainer_penalties_trainer (trainer_user_id),
  KEY gymies_trainer_penalties_booking (booking_id),
  KEY gymies_trainer_penalties_created (created_at),
  CONSTRAINT gymies_trainer_penalties_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_trainer_penalties_booking_fk FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
