-- Dummy data voor admin-pagina (vault-console-portal): admin@trainmate.app, postvak, notitietemplates.
-- Zelfstandig: maakt ontbrekende tabellen aan en vult ze. Veilig opnieuw draaien.
-- Gebruik: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/seed_gymies_admin_dummy.sql

SET NAMES utf8mb4;

-- ---------- Tabellen voor werkbak + notities (als ze nog niet bestaan) ----------
CREATE TABLE IF NOT EXISTS gymies_admin_saved_views (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  name VARCHAR(120) NOT NULL,
  entity_type VARCHAR(32) NOT NULL,
  filters JSON NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_admin_saved_views_user_entity (user_id, entity_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_admin_note_templates (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(120) NOT NULL,
  body TEXT NOT NULL,
  category VARCHAR(32) NOT NULL DEFAULT 'general',
  sort_order SMALLINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_admin_note_templates_category (category),
  UNIQUE KEY gymies_admin_note_templates_name_category (name, category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_support_tickets (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  subject VARCHAR(255) NOT NULL,
  category VARCHAR(80) NOT NULL DEFAULT 'general',
  priority VARCHAR(20) NOT NULL DEFAULT 'medium',
  status VARCHAR(40) NOT NULL DEFAULT 'new',
  assigned_to_user_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  resolved_at TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY gymies_support_tickets_user_idx (user_id),
  KEY gymies_support_tickets_status_idx (status),
  KEY gymies_support_tickets_priority_idx (priority)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_support_ticket_messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ticket_id BIGINT UNSIGNED NOT NULL,
  author_user_id BIGINT UNSIGNED NOT NULL,
  message TEXT NOT NULL,
  is_internal TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_support_ticket_messages_ticket_idx (ticket_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------- Notitietemplates (bij ticket/booking: "Sjabloon"-chips) ----------
INSERT IGNORE INTO gymies_admin_note_templates (name, body, category, sort_order) VALUES
('KYC check pending', 'KYC-check loopt. Klant is geïnformeerd.', 'ticket', 10),
('Client contacted', 'Klant is gecontacteerd; wacht op reactie.', 'ticket', 20),
('Refund approved', 'Terugbetaling goedgekeurd. Verwerkt binnen 5 werkdagen.', 'ticket', 30),
('Escalated to specialist', 'Doorgestuurd naar specialist voor verdere afhandeling.', 'ticket', 40),
('Booking incident – no-show', 'No-show geregistreerd. Trainer heeft klant proberen te bereiken.', 'booking', 10),
('Booking incident – dispute', 'Geschil gemeld. Beide partijen gehoord; follow-up volgt.', 'booking', 20),
('Payout blocked – verification', 'Uitbetaling gepauzeerd tot verificatie is afgerond.', 'general', 10),
('Fraude review in progress', 'Fraudecheck loopt. Geen actie tot conclusie.', 'general', 20);

-- ---------- Dummy klanten (voor boekingen in vault-test) ----------
INSERT INTO gymies_users (email, password_hash, role, display_name, created_at, updated_at)
VALUES
  ('klant.jan@example.com',  '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'klant', 'Jan Jansen',   NOW(), NOW()),
  ('klant.marie@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'klant', 'Marie de Boer', NOW(), NOW())
ON DUPLICATE KEY UPDATE
  display_name = VALUES(display_name),
  updated_at = NOW();

-- ---------- Admin-gebruiker: admin@trainmate.app (wachtwoord: password) ----------
INSERT INTO gymies_users (email, password_hash, role, display_name, is_admin, created_at, updated_at)
VALUES (
  'admin@trainmate.app',
  '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',
  'klant',
  'Admin TrainMate',
  1,
  NOW(),
  NOW()
)
ON DUPLICATE KEY UPDATE
  is_admin = 1,
  password_hash = VALUES(password_hash),
  display_name = VALUES(display_name),
  updated_at = NOW();

-- Anne ook admin houden (backup-inlog)
UPDATE gymies_users SET is_admin = 1 WHERE email = 'trainer.anne@example.com' LIMIT 1;

-- ---------- Saved views (werkbak) ----------
INSERT IGNORE INTO gymies_admin_saved_views (user_id, name, entity_type, filters) VALUES
(NULL, 'Nieuwe tickets', 'tickets', '{"status":"new"}'),
(NULL, 'In behandeling', 'tickets', '{"status":"in_progress"}'),
(NULL, 'Wacht op klant', 'tickets', '{"status":"waiting_customer"}'),
(NULL, 'Hoge prioriteit', 'tickets', '{"priority":"high"}'),
(NULL, 'Open boekingen', 'bookings', '{"status":"pending"}'),
(NULL, 'Bevestigde boekingen', 'bookings', '{"status":"confirmed"}'),
(NULL, 'Onbetaalde boekingen', 'bookings', '{"payment_status":"unpaid"}'),
(NULL, 'Actieve trainers', 'users', '{"role":"trainer"}'),
(NULL, 'Klanten', 'users', '{"role":"klant"}'),
(NULL, 'E-mail niet geverifieerd', 'users', '{"email_verified":false}'),
(NULL, 'Pending payouts', 'payouts', '{"status":"pending"}'),
(NULL, 'Uitbetaald', 'payouts', '{"status":"paid"}'),
(NULL, 'Mislukte payouts', 'payouts', '{"status":"failed"}');

-- ---------- Postvak: meerdere voorbeeldtickets (status new / in_progress / waiting_customer) ----------
INSERT INTO gymies_support_tickets (user_id, subject, category, priority, status)
SELECT id, 'Vraag over account – verificatie', 'general', 'medium', 'new'
FROM gymies_users ORDER BY id ASC LIMIT 1;

INSERT INTO gymies_support_tickets (user_id, subject, category, priority, status)
SELECT id, 'Betaling mislukt – klant meldt fout', 'general', 'high', 'in_progress'
FROM (SELECT id FROM gymies_users ORDER BY id ASC LIMIT 1 OFFSET 1) u;

INSERT INTO gymies_support_tickets (user_id, subject, category, priority, status)
SELECT id, 'Boeking annuleren – wijziging datum', 'general', 'medium', 'waiting_customer'
FROM (SELECT id FROM gymies_users ORDER BY id ASC LIMIT 1 OFFSET 2) u;

INSERT INTO gymies_support_tickets (user_id, subject, category, priority, status)
SELECT id, 'Dummy ticket – postvak test', 'general', 'low', 'new'
FROM gymies_users ORDER BY id ASC LIMIT 1;

-- ---------- Eén ticket met een interne notitie (toont in Timeline & interne notities) ----------
INSERT INTO gymies_support_ticket_messages (ticket_id, author_user_id, message, is_internal)
SELECT (SELECT MIN(id) FROM gymies_support_tickets), (SELECT id FROM gymies_users WHERE is_admin = 1 LIMIT 1), 'Interne notitie: voorbeeld voor admin-pagina.', 1;

-- ---------- Organisaties (gyms) voor tab Organisaties – alleen als tabel bestaat ----------
CREATE TABLE IF NOT EXISTS gymies_organisations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  type ENUM('gym', 'company') NOT NULL DEFAULT 'gym',
  status ENUM('active', 'inactive', 'suspended') NOT NULL DEFAULT 'active',
  contact_email VARCHAR(255) DEFAULT NULL,
  invoice_prefix VARCHAR(32) DEFAULT NULL,
  payout_frequency ENUM('weekly', 'biweekly', 'monthly') NOT NULL DEFAULT 'weekly',
  payout_iban_masked VARCHAR(64) DEFAULT NULL,
  payout_minimum_cents INT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_organisations_type (type),
  KEY gymies_organisations_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO gymies_organisations (id, name, type, status, contact_email, payout_frequency) VALUES
(1, 'Demo Gym Amsterdam', 'gym', 'active', 'demo@trainmate.app', 'weekly'),
(2, 'Test Sportschool Utrecht', 'gym', 'active', 'sport@trainmate.app', 'biweekly');

-- ---------- Dummy boekingen (Overzicht + tab Boekingen + postvak bij payment_failed) ----------
-- Gebruikt bestaande users: klant.jan, klant.marie, trainer.anne. Alleen als gymies_bookings bestaat.
INSERT IGNORE INTO gymies_bookings (client_user_id, trainer_user_id, scheduled_at, duration_minutes, status, amount_cents, paid_at, created_at, updated_at)
SELECT c.id, t.id, NOW() + INTERVAL 1 DAY, 60, 'pending', 6500, NULL, NOW(), NOW()
FROM (SELECT id FROM gymies_users WHERE email = 'klant.jan@example.com' LIMIT 1) c
CROSS JOIN (SELECT id FROM gymies_users WHERE email = 'trainer.anne@example.com' LIMIT 1) t
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_bookings');

INSERT IGNORE INTO gymies_bookings (client_user_id, trainer_user_id, scheduled_at, duration_minutes, status, amount_cents, paid_at, created_at, updated_at)
SELECT c.id, t.id, NOW() - INTERVAL 2 DAY, 60, 'completed', 6500, NOW() - INTERVAL 2 DAY, NOW() - INTERVAL 3 DAY, NOW()
FROM (SELECT id FROM gymies_users WHERE email = 'klant.jan@example.com' LIMIT 1) c
CROSS JOIN (SELECT id FROM gymies_users WHERE email = 'trainer.anne@example.com' LIMIT 1) t
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_bookings');

INSERT IGNORE INTO gymies_bookings (client_user_id, trainer_user_id, scheduled_at, duration_minutes, status, amount_cents, paid_at, created_at, updated_at)
SELECT c.id, t.id, NOW() + INTERVAL 3 DAY, 45, 'confirmed', 5000, NOW(), NOW(), NOW()
FROM (SELECT id FROM gymies_users WHERE email = 'klant.marie@example.com' LIMIT 1) c
CROSS JOIN (SELECT id FROM gymies_users WHERE email = 'trainer.anne@example.com' LIMIT 1) t
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_bookings');

-- ---------- Dummy uitbetalingen (tab Betalingen / Payouts + postvak) ----------
INSERT INTO gymies_payouts (trainer_user_id, amount_cents, gross_cents, fee_cents, status, requested_at, created_at, updated_at)
SELECT u.id, 12500, 13000, 500, 'pending', NOW(), NOW(), NOW()
FROM gymies_users u
WHERE u.email = 'trainer.anne@example.com'
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_payouts')
LIMIT 1;

INSERT INTO gymies_payouts (trainer_user_id, amount_cents, gross_cents, fee_cents, status, paid_at, requested_at, created_at, updated_at)
SELECT u.id, 19500, 20000, 500, 'paid', NOW() - INTERVAL 1 DAY, NOW() - INTERVAL 2 DAY, NOW() - INTERVAL 2 DAY, NOW()
FROM gymies_users u
WHERE u.email = 'trainer.anne@example.com'
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_payouts')
LIMIT 1;

-- ---------- Auditlog (tab Audit) – acties van admin@trainmate.app ----------
INSERT INTO gymies_audit_log (user_id, action, entity_type, entity_id, new_values, ip_address, created_at)
SELECT u.id, 'admin_login', 'user', u.id, '{"source":"vault-console"}', '127.0.0.1', NOW() - INTERVAL 1 HOUR
FROM gymies_users u
WHERE u.email = 'admin@trainmate.app'
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_audit_log')
LIMIT 1;

INSERT INTO gymies_audit_log (user_id, action, entity_type, entity_id, new_values, ip_address, created_at)
SELECT (SELECT id FROM gymies_users WHERE email = 'admin@trainmate.app' LIMIT 1), 'admin_user_status_updated', 'user', (SELECT id FROM gymies_users WHERE email = 'klant.jan@example.com' LIMIT 1), '{"status":"active","reason":"Dummy audit"}', '127.0.0.1', NOW() - INTERVAL 2 HOUR
FROM DUAL
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_audit_log');

INSERT INTO gymies_audit_log (user_id, action, entity_type, entity_id, new_values, ip_address, created_at)
SELECT (SELECT id FROM gymies_users WHERE email = 'admin@trainmate.app' LIMIT 1), 'gym_settings_updated', 'organisation', 1, '{"name":"Demo Gym Amsterdam"}', '127.0.0.1', NOW() - INTERVAL 3 HOUR
FROM DUAL
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_audit_log');
