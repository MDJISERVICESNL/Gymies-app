-- Admin Control Tower: werkbak, saved views, note templates
-- Uitvoeren: mysql -u user -p database < alter_gymies_admin_werkbak.sql

SET NAMES utf8mb4;

-- Saved filters/views per admin (optioneel user_id = NULL = globale view)
CREATE TABLE IF NOT EXISTS gymies_admin_saved_views (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NULL DEFAULT NULL COMMENT 'NULL = globale view voor iedereen',
  name VARCHAR(120) NOT NULL,
  entity_type VARCHAR(32) NOT NULL COMMENT 'users, tickets, bookings, payouts',
  filters JSON NOT NULL COMMENT 'bijv. {"status":"new","priority":"high"}',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_admin_saved_views_user_entity (user_id, entity_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Standaard notitietemplates voor snelle reacties
CREATE TABLE IF NOT EXISTS gymies_admin_note_templates (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(120) NOT NULL,
  body TEXT NOT NULL,
  category VARCHAR(32) NOT NULL DEFAULT 'general' COMMENT 'ticket, booking, general',
  sort_order SMALLINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_admin_note_templates_category (category),
  UNIQUE KEY gymies_admin_note_templates_name_category (name, category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Default templates (INSERT IGNORE = veilig opnieuw draaien)
INSERT IGNORE INTO gymies_admin_note_templates (name, body, category, sort_order) VALUES
('KYC check pending', 'KYC-check loopt. Klant is geïnformeerd.', 'ticket', 10),
('Client contacted', 'Klant is gecontacteerd; wacht op reactie.', 'ticket', 20),
('Refund approved', 'Terugbetaling goedgekeurd. Verwerkt binnen 5 werkdagen.', 'ticket', 30),
('Escalated to specialist', 'Doorgestuurd naar specialist voor verdere afhandeling.', 'ticket', 40),
('Booking incident – no-show', 'No-show geregistreerd. Trainer heeft klant proberen te bereiken.', 'booking', 10),
('Booking incident – dispute', 'Geschil gemeld. Beide partijen gehoord; follow-up volgt.', 'booking', 20),
('Payout blocked – verification', 'Uitbetaling gepauzeerd tot verificatie is afgerond.', 'general', 10),
('Fraude review in progress', 'Fraudecheck loopt. Geen actie tot conclusie.', 'general', 20);
