ALTER TABLE gymies_trainer_profiles
  ADD COLUMN mollie_profile_id VARCHAR(64) DEFAULT NULL,
  ADD COLUMN mollie_onboarding_status ENUM('not_started','pending','completed','rejected') NOT NULL DEFAULT 'not_started',
  ADD COLUMN accepts_online TINYINT(1) NOT NULL DEFAULT 1,
  ADD COLUMN accepts_cash TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN subscription_plan VARCHAR(32) DEFAULT NULL;
ALTER TABLE gymies_bookings
  ADD COLUMN payment_method VARCHAR(32) DEFAULT NULL,
  ADD COLUMN cash_confirmed_at TIMESTAMP NULL DEFAULT NULL,
  ADD COLUMN cash_confirmed_by_user_id BIGINT UNSIGNED DEFAULT NULL;
ALTER TABLE gymies_document_uploads
  ADD COLUMN document_category VARCHAR(32) DEFAULT NULL,
  ADD COLUMN original_filename VARCHAR(255) DEFAULT NULL,
  ADD COLUMN mime_type VARCHAR(128) DEFAULT NULL,
  ADD COLUMN file_size_bytes INT UNSIGNED DEFAULT NULL,
  ADD COLUMN admin_notes VARCHAR(500) DEFAULT NULL,
  ADD COLUMN rejected_at TIMESTAMP NULL DEFAULT NULL,
  ADD COLUMN rejection_reason VARCHAR(500) DEFAULT NULL;
CREATE TABLE IF NOT EXISTS gymies_trainer_invoices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  group_session_id BIGINT UNSIGNED DEFAULT NULL,
  invoice_number VARCHAR(64) NOT NULL,
  amount_cents INT UNSIGNED NOT NULL,
  vat_percent DECIMAL(5,2) NOT NULL DEFAULT 21.00,
  vat_cents INT UNSIGNED NOT NULL DEFAULT 0,
  total_cents INT UNSIGNED NOT NULL,
  kvk_number VARCHAR(64) DEFAULT NULL,
  vat_number VARCHAR(64) DEFAULT NULL,
  business_name VARCHAR(255) DEFAULT NULL,
  trainer_iban_masked VARCHAR(34) DEFAULT NULL,
  description VARCHAR(500) DEFAULT NULL,
  status ENUM('generated','sent','paid','cancelled') NOT NULL DEFAULT 'generated',
  pdf_url VARCHAR(512) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_trainer_invoices_number (invoice_number),
  KEY gymies_trainer_invoices_trainer (trainer_user_id),
  KEY gymies_trainer_invoices_client (client_user_id),
  KEY gymies_trainer_invoices_booking (booking_id),
  CONSTRAINT gymies_trainer_invoices_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_trainer_invoices_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS gymies_subscription_payments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  subscription_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  mollie_payment_id VARCHAR(64) DEFAULT NULL,
  amount_cents INT UNSIGNED NOT NULL,
  status ENUM('pending','paid','failed','refunded') NOT NULL DEFAULT 'pending',
  failure_reason VARCHAR(500) DEFAULT NULL,
  paid_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_sub_payments_sub (subscription_id),
  KEY gymies_sub_payments_trainer (trainer_user_id),
  CONSTRAINT gymies_sub_payments_sub_fk FOREIGN KEY (subscription_id) REFERENCES gymies_subscriptions (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
