-- Payout instellingen voor trainer inkomstenpagina
-- Veilig om handmatig uit te voeren; bij duplicate column/table die stap overslaan.

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS gymies_trainer_bank_accounts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  iban_masked VARCHAR(64) NOT NULL,
  iban_last4 VARCHAR(4) DEFAULT NULL,
  bic VARCHAR(32) DEFAULT NULL,
  account_holder_name VARCHAR(255) DEFAULT NULL,
  account_holder_first_name VARCHAR(120) DEFAULT NULL,
  account_holder_last_name VARCHAR(120) DEFAULT NULL,
  payout_frequency ENUM('weekly', 'biweekly', 'monthly') NOT NULL DEFAULT 'monthly',
  minimum_payout_cents INT UNSIGNED NOT NULL DEFAULT 0,
  notify_payout_paid TINYINT(1) NOT NULL DEFAULT 1,
  notify_payout_failed TINYINT(1) NOT NULL DEFAULT 1,
  sepa_mandate_id VARCHAR(128) DEFAULT NULL,
  status ENUM('pending', 'verified', 'rejected') NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_trainer_bank_accounts_trainer_unique (trainer_user_id),
  CONSTRAINT gymies_trainer_bank_accounts_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE gymies_trainer_bank_accounts
  ADD COLUMN iban_last4 VARCHAR(4) DEFAULT NULL AFTER iban_masked,
  ADD COLUMN account_holder_first_name VARCHAR(120) DEFAULT NULL AFTER account_holder_name,
  ADD COLUMN account_holder_last_name VARCHAR(120) DEFAULT NULL AFTER account_holder_first_name,
  ADD COLUMN payout_frequency ENUM('weekly', 'biweekly', 'monthly') NOT NULL DEFAULT 'monthly' AFTER account_holder_last_name,
  ADD COLUMN minimum_payout_cents INT UNSIGNED NOT NULL DEFAULT 0 AFTER payout_frequency,
  ADD COLUMN notify_payout_paid TINYINT(1) NOT NULL DEFAULT 1 AFTER minimum_payout_cents,
  ADD COLUMN notify_payout_failed TINYINT(1) NOT NULL DEFAULT 1 AFTER notify_payout_paid;

ALTER TABLE gymies_payouts
  ADD COLUMN gross_cents INT UNSIGNED DEFAULT NULL AFTER amount_cents,
  ADD COLUMN fee_cents INT UNSIGNED DEFAULT NULL AFTER gross_cents,
  ADD COLUMN payout_frequency ENUM('weekly', 'biweekly', 'monthly') DEFAULT NULL AFTER fee_cents,
  ADD COLUMN requested_at TIMESTAMP NULL DEFAULT NULL AFTER status;
