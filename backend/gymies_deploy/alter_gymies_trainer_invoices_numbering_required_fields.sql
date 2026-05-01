-- Gymies factuurnummering + verplichte factuur snapshotvelden
-- Doel:
-- 1) Globaal uniek intern nummer: gymies_invoice_number
-- 2) Trainer-eigen nummering: trainer_invoice_number (uniek per trainer)
-- 3) Verplichte factuurvelden als snapshot op factuurmoment

SET NAMES utf8mb4;

ALTER TABLE gymies_trainer_invoices
  ADD COLUMN gymies_invoice_number VARCHAR(64) DEFAULT NULL,
  ADD COLUMN trainer_invoice_number VARCHAR(64) DEFAULT NULL,
  ADD COLUMN invoice_date DATE DEFAULT NULL,
  ADD COLUMN service_date DATE DEFAULT NULL,
  ADD COLUMN due_date DATE DEFAULT NULL,
  ADD COLUMN currency CHAR(3) NOT NULL DEFAULT 'EUR',
  ADD COLUMN service_type VARCHAR(120) DEFAULT NULL,
  ADD COLUMN price_ex_vat_cents INT UNSIGNED DEFAULT NULL,
  ADD COLUMN price_inc_vat_cents INT UNSIGNED DEFAULT NULL,
  ADD COLUMN company_name VARCHAR(255) DEFAULT NULL,
  ADD COLUMN trainer_name VARCHAR(255) DEFAULT NULL,
  ADD COLUMN trainer_address_line1 VARCHAR(255) DEFAULT NULL,
  ADD COLUMN trainer_postcode VARCHAR(20) DEFAULT NULL,
  ADD COLUMN trainer_city VARCHAR(255) DEFAULT NULL,
  ADD COLUMN trainer_country VARCHAR(2) DEFAULT 'NL',
  ADD COLUMN client_name VARCHAR(255) DEFAULT NULL,
  ADD COLUMN trainer_customer_number VARCHAR(64) DEFAULT NULL,
  ADD COLUMN client_address_line1 VARCHAR(255) DEFAULT NULL,
  ADD COLUMN client_postcode VARCHAR(20) DEFAULT NULL,
  ADD COLUMN client_city VARCHAR(255) DEFAULT NULL,
  ADD COLUMN client_country VARCHAR(2) DEFAULT 'NL';

-- Backfill trainer invoice nummer en datums
UPDATE gymies_trainer_invoices
SET trainer_invoice_number = invoice_number
WHERE trainer_invoice_number IS NULL OR trainer_invoice_number = '';

UPDATE gymies_trainer_invoices
SET invoice_date = DATE(COALESCE(created_at, NOW()))
WHERE invoice_date IS NULL;

UPDATE gymies_trainer_invoices
SET due_date = DATE_ADD(invoice_date, INTERVAL 14 DAY)
WHERE due_date IS NULL;

UPDATE gymies_trainer_invoices
SET service_date = invoice_date
WHERE service_date IS NULL;

UPDATE gymies_trainer_invoices
SET service_type = 'personal_training'
WHERE service_type IS NULL OR service_type = '';

UPDATE gymies_trainer_invoices
SET price_ex_vat_cents = amount_cents
WHERE price_ex_vat_cents IS NULL;

UPDATE gymies_trainer_invoices
SET price_inc_vat_cents = total_cents
WHERE price_inc_vat_cents IS NULL;

UPDATE gymies_trainer_invoices
SET company_name = COALESCE(NULLIF(business_name, ''), 'Gymies')
WHERE company_name IS NULL OR company_name = '';

UPDATE gymies_trainer_invoices
SET gymies_invoice_number = CONCAT('GYM-', DATE_FORMAT(COALESCE(created_at, NOW()), '%Y'), '-', LPAD(id, 8, '0'))
WHERE gymies_invoice_number IS NULL OR gymies_invoice_number = '';

CREATE TABLE IF NOT EXISTS gymies_trainer_client_numbers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_customer_number VARCHAR(64) NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_trainer_client_numbers_unique (trainer_user_id, client_user_id),
  UNIQUE KEY gymies_trainer_client_numbers_per_trainer_unique (trainer_user_id, trainer_customer_number),
  CONSTRAINT gymies_trainer_client_numbers_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_trainer_client_numbers_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Oude globale unique key op invoice_number verwijderen (maakt trainer-eigen duplicaten mogelijk)
SET @idx_exists := (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'gymies_trainer_invoices'
      AND index_name = 'gymies_trainer_invoices_number'
);
SET @drop_idx_sql := IF(@idx_exists > 0, 'ALTER TABLE gymies_trainer_invoices DROP INDEX gymies_trainer_invoices_number', 'SELECT 1');
PREPARE stmt_drop_idx FROM @drop_idx_sql;
EXECUTE stmt_drop_idx;
DEALLOCATE PREPARE stmt_drop_idx;

-- Nieuwe unieke indexen (idempotent)
SET @gym_idx_exists := (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'gymies_trainer_invoices'
      AND index_name = 'gymies_trainer_invoices_gymies_number_unique'
);
SET @create_gym_idx_sql := IF(
    @gym_idx_exists = 0,
    'CREATE UNIQUE INDEX gymies_trainer_invoices_gymies_number_unique ON gymies_trainer_invoices (gymies_invoice_number)',
    'SELECT 1'
);
PREPARE stmt_create_gym_idx FROM @create_gym_idx_sql;
EXECUTE stmt_create_gym_idx;
DEALLOCATE PREPARE stmt_create_gym_idx;

SET @trainer_idx_exists := (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'gymies_trainer_invoices'
      AND index_name = 'gymies_trainer_invoices_trainer_number_unique'
);
SET @create_trainer_idx_sql := IF(
    @trainer_idx_exists = 0,
    'CREATE UNIQUE INDEX gymies_trainer_invoices_trainer_number_unique ON gymies_trainer_invoices (trainer_user_id, trainer_invoice_number)',
    'SELECT 1'
);
PREPARE stmt_create_trainer_idx FROM @create_trainer_idx_sql;
EXECUTE stmt_create_trainer_idx;
DEALLOCATE PREPARE stmt_create_trainer_idx;

