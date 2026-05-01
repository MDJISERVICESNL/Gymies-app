-- Women's Safety Ecosysteem: gender op users, women_only toggle, fraude-rapportage, SOS

-- 1. Gender op gebruikers (klanten + trainers)
ALTER TABLE gymies_users
  ADD COLUMN gender ENUM('female', 'male', 'non_binary', 'not_specified') NOT NULL DEFAULT 'not_specified' COMMENT 'Gender voor women-only filtering';

-- 2. Women-only toggle op trainer profiel
ALTER TABLE gymies_trainer_profiles
  ADD COLUMN women_only TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Trainer traint uitsluitend vrouwen';

-- 3. Banknaam-check: naam afwijking opslaan bij betaling
ALTER TABLE gymies_payment_transactions
  ADD COLUMN mollie_payer_name VARCHAR(255) DEFAULT NULL COMMENT 'Naam rekeninghouder van Mollie',
  ADD COLUMN payer_name_mismatch TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1=naam betaler wijkt af van klantnaam';

-- 4. Identiteitsfraude-rapportage tabel
CREATE TABLE IF NOT EXISTS gymies_identity_fraud_reports (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  reporter_user_id BIGINT UNSIGNED NOT NULL COMMENT 'De trainer die rapporteert',
  reported_user_id BIGINT UNSIGNED NOT NULL COMMENT 'Het account van de klant',
  reason VARCHAR(500) NOT NULL,
  evidence_url VARCHAR(1000) DEFAULT NULL COMMENT 'Optionele foto als bewijs',
  status VARCHAR(32) NOT NULL DEFAULT 'pending' COMMENT 'pending, confirmed_fraud, dismissed',
  admin_notes TEXT DEFAULT NULL,
  resolved_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  resolved_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_fraud_reports_booking (booking_id),
  KEY gymies_fraud_reports_reported (reported_user_id),
  KEY gymies_fraud_reports_status (status),
  CONSTRAINT gymies_fraud_reports_booking_fk FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE CASCADE,
  CONSTRAINT gymies_fraud_reports_reporter_fk FOREIGN KEY (reporter_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_fraud_reports_reported_fk FOREIGN KEY (reported_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. SOS-meldingen tabel
CREATE TABLE IF NOT EXISTS gymies_sos_alerts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL COMMENT 'Trainer die SOS stuurt',
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  latitude DECIMAL(10,7) NOT NULL,
  longitude DECIMAL(10,7) NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'active' COMMENT 'active, resolved, false_alarm',
  resolved_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  resolved_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_sos_alerts_user (user_id),
  KEY gymies_sos_alerts_status (status),
  CONSTRAINT gymies_sos_alerts_user_fk FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. Safe-Session tracking
ALTER TABLE gymies_bookings
  ADD COLUMN safe_session_active TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1=safe-session timer loopt',
  ADD COLUMN safe_session_started_at TIMESTAMP NULL DEFAULT NULL,
  ADD COLUMN check_out_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Tijdstip trainer uitcheckt na sessie';
