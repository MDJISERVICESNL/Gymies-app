-- ============================================================
-- Gymies 2.0 SaaS Model Migration
-- Transformatie van commissie-marktplaats naar SaaS-abonnement
-- ============================================================

-- 1. Plans: uitbreiden met SaaS-specifieke kolommen + seed data
ALTER TABLE gymies_plans
  ADD COLUMN slug VARCHAR(32) NOT NULL DEFAULT '' COMMENT 'starter, pro, studio',
  ADD COLUMN description VARCHAR(500) DEFAULT NULL,
  ADD COLUMN max_sessions_per_month INT UNSIGNED DEFAULT NULL COMMENT 'NULL = onbeperkt',
  ADD COLUMN max_trainer_accounts INT UNSIGNED DEFAULT 1 COMMENT 'Voor Studio: meerdere trainers',
  ADD COLUMN has_invoicing TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN has_crm TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN has_womens_choice TINYINT(1) NOT NULL DEFAULT 1,
  ADD COLUMN is_active TINYINT(1) NOT NULL DEFAULT 1,
  ADD UNIQUE KEY gymies_plans_slug (slug);

INSERT INTO gymies_plans (name, slug, price_cents_per_month, description, max_sessions_per_month, max_trainer_accounts, has_invoicing, has_crm, has_womens_choice, is_active) VALUES
  ('Gymies Starter', 'starter', 2995, 'Alles om te kunnen starten + Women''s Choice.', NULL, 1, 0, 0, 1, 1),
  ('Gymies Pro', 'pro', 5995, 'Onbeperkte sessies + Facturatiemodule + Klant-CRM.', NULL, 1, 1, 1, 1, 1),
  ('Gymies Studio', 'studio', 9995, 'Meerdere trainers-accounts onder één beheer.', NULL, 5, 1, 1, 1, 1);

-- 2. Subscriptions: transformeren van klant-abonnement naar trainer-abonnement (Mollie)
ALTER TABLE gymies_subscriptions
  CHANGE COLUMN client_user_id trainer_user_id BIGINT UNSIGNED NOT NULL COMMENT 'Trainer die het abonnement heeft',
  ADD COLUMN mollie_customer_id VARCHAR(64) DEFAULT NULL COMMENT 'cst_xxx Mollie Customer ID',
  ADD COLUMN mollie_subscription_id VARCHAR(64) DEFAULT NULL COMMENT 'sub_xxx Mollie Subscription ID',
  ADD COLUMN mollie_mandate_id VARCHAR(64) DEFAULT NULL COMMENT 'mdt_xxx SEPA mandaat ID',
  ADD COLUMN current_period_start DATE DEFAULT NULL,
  ADD COLUMN current_period_end DATE DEFAULT NULL,
  ADD COLUMN trial_ends_at TIMESTAMP NULL DEFAULT NULL,
  ADD COLUMN cancelled_at TIMESTAMP NULL DEFAULT NULL,
  ADD COLUMN cancel_reason VARCHAR(500) DEFAULT NULL,
  MODIFY COLUMN status ENUM('trialing','active','past_due','cancelled','expired') NOT NULL DEFAULT 'active',
  DROP COLUMN stripe_subscription_id;

DROP INDEX gymies_subscriptions_client ON gymies_subscriptions;
CREATE INDEX gymies_subscriptions_trainer ON gymies_subscriptions (trainer_user_id);
CREATE INDEX gymies_subscriptions_mollie ON gymies_subscriptions (mollie_subscription_id);

-- 3. Trainer profiles: Mollie Connect + cash/online toggles
ALTER TABLE gymies_trainer_profiles
  ADD COLUMN mollie_profile_id VARCHAR(64) DEFAULT NULL COMMENT 'Mollie Connect profiel-ID van de trainer',
  ADD COLUMN mollie_onboarding_status ENUM('not_started','pending','completed','rejected') NOT NULL DEFAULT 'not_started',
  ADD COLUMN accepts_online TINYINT(1) NOT NULL DEFAULT 1 COMMENT 'Accepteert online betalingen via Mollie',
  ADD COLUMN accepts_cash TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Accepteert cash op locatie',
  ADD COLUMN subscription_plan VARCHAR(32) DEFAULT NULL COMMENT 'Huidig plan slug';

-- 4. Bookings: cash-betaling flow
ALTER TABLE gymies_bookings
  ADD COLUMN payment_method VARCHAR(32) DEFAULT NULL COMMENT 'mollie_connect, cash, NULL=legacy',
  ADD COLUMN cash_confirmed_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Trainer bevestigt cash ontvangen',
  ADD COLUMN cash_confirmed_by_user_id BIGINT UNSIGNED DEFAULT NULL;

-- 5. Document uploads: categorie toevoegen voor KvK/ID/cert
ALTER TABLE gymies_document_uploads
  ADD COLUMN document_category VARCHAR(32) DEFAULT NULL COMMENT 'kvk_extract, id_document, certification, insurance',
  ADD COLUMN original_filename VARCHAR(255) DEFAULT NULL,
  ADD COLUMN mime_type VARCHAR(128) DEFAULT NULL,
  ADD COLUMN file_size_bytes INT UNSIGNED DEFAULT NULL,
  ADD COLUMN admin_notes VARCHAR(500) DEFAULT NULL,
  ADD COLUMN rejected_at TIMESTAMP NULL DEFAULT NULL,
  ADD COLUMN rejection_reason VARCHAR(500) DEFAULT NULL;

-- 6. Trainer invoices: facturen namens trainer's KvK voor klanten
CREATE TABLE IF NOT EXISTS gymies_trainer_invoices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  group_session_id BIGINT UNSIGNED DEFAULT NULL,
  invoice_number VARCHAR(64) NOT NULL COMMENT 'Format: TRAINERNAME-2026-001',
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

-- 7. Subscription payment log (webhook events)
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
