-- Migratie: beschikbaarheid, facturatie, chat, favorieten, specialismen, pakketten, kortingen, AVG, notificaties, abonnementen, auditlog
-- Alleen uitvoeren op een bestaande TrainMaat-database (na create_gymies_tables + eventueel alter_gymies_all_additions).
-- Bij "Duplicate column" of "Duplicate table": die stap overslaan.

SET NAMES utf8mb4;

-- ========== Trainerprofiel: verzekering ==========
ALTER TABLE gymies_trainer_profiles
  ADD COLUMN insurance_verified_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Verzekering gecontroleerd' AFTER sort_order,
  ADD COLUMN insurance_expires_at DATE DEFAULT NULL COMMENT 'Verloopdatum verzekering' AFTER insurance_verified_at;

-- ========== Specialismen (vaste lijst) ==========
CREATE TABLE IF NOT EXISTS gymies_specialties (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL,
  sort_order INT DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_specialties_name_unique (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Trainer – meerdere specialismen ==========
CREATE TABLE IF NOT EXISTS gymies_trainer_specialties (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_profile_id BIGINT UNSIGNED NOT NULL,
  specialty_id INT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_trainer_specialties_unique (trainer_profile_id, specialty_id),
  CONSTRAINT gymies_trainer_specialties_profile_fk
    FOREIGN KEY (trainer_profile_id) REFERENCES gymies_trainer_profiles (id) ON DELETE CASCADE,
  CONSTRAINT gymies_trainer_specialties_specialty_fk
    FOREIGN KEY (specialty_id) REFERENCES gymies_specialties (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Trainer – vaste locaties ==========
CREATE TABLE IF NOT EXISTS gymies_trainer_locations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL,
  address_line1 VARCHAR(255) DEFAULT NULL,
  postcode VARCHAR(20) DEFAULT NULL,
  city VARCHAR(255) DEFAULT NULL,
  is_primary TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_trainer_locations_trainer (trainer_user_id),
  CONSTRAINT gymies_trainer_locations_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Beschikbaarheid – vaste slots ==========
CREATE TABLE IF NOT EXISTS gymies_availability_slots (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  day_of_week TINYINT UNSIGNED NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_availability_slots_trainer (trainer_user_id),
  CONSTRAINT gymies_availability_slots_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Beschikbaarheid – uitzonderingen ==========
CREATE TABLE IF NOT EXISTS gymies_availability_exceptions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  exception_date DATE NOT NULL,
  is_available TINYINT(1) NOT NULL DEFAULT 0,
  start_time TIME DEFAULT NULL,
  end_time TIME DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_availability_exceptions_trainer (trainer_user_id),
  CONSTRAINT gymies_availability_exceptions_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Pakketten ==========
CREATE TABLE IF NOT EXISTS gymies_packages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL,
  sessions_count INT UNSIGNED NOT NULL,
  total_cents INT UNSIGNED NOT NULL,
  valid_days INT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_packages_trainer (trainer_user_id),
  CONSTRAINT gymies_packages_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Bookings: package + locatie ==========
ALTER TABLE gymies_bookings
  ADD COLUMN package_id BIGINT UNSIGNED DEFAULT NULL AFTER cancelled_by_user_id,
  ADD COLUMN sessions_remaining INT UNSIGNED DEFAULT NULL AFTER package_id,
  ADD COLUMN trainer_location_id BIGINT UNSIGNED DEFAULT NULL AFTER sessions_remaining;

ALTER TABLE gymies_bookings
  ADD CONSTRAINT gymies_bookings_package_fk
    FOREIGN KEY (package_id) REFERENCES gymies_packages (id) ON DELETE SET NULL;
ALTER TABLE gymies_bookings
  ADD CONSTRAINT gymies_bookings_location_fk
    FOREIGN KEY (trainer_location_id) REFERENCES gymies_trainer_locations (id) ON DELETE SET NULL;

-- ========== Facturen ==========
CREATE TABLE IF NOT EXISTS gymies_invoices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  invoice_number VARCHAR(64) NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  amount_cents INT UNSIGNED NOT NULL,
  vat_cents INT UNSIGNED DEFAULT 0,
  status ENUM('draft', 'sent', 'paid', 'cancelled') NOT NULL DEFAULT 'draft',
  pdf_url VARCHAR(512) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_invoices_number_unique (invoice_number),
  KEY gymies_invoices_user (user_id),
  CONSTRAINT gymies_invoices_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_invoices_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Uitbetalingen ==========
CREATE TABLE IF NOT EXISTS gymies_payouts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  amount_cents INT UNSIGNED NOT NULL,
  status ENUM('pending', 'paid', 'failed') NOT NULL DEFAULT 'pending',
  paid_at TIMESTAMP NULL DEFAULT NULL,
  reference VARCHAR(255) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_payouts_trainer (trainer_user_id),
  CONSTRAINT gymies_payouts_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Kortingscodes ==========
CREATE TABLE IF NOT EXISTS gymies_promo_codes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(64) NOT NULL,
  discount_type ENUM('percent', 'fixed') NOT NULL,
  value_cents INT UNSIGNED NOT NULL,
  valid_from DATE DEFAULT NULL,
  valid_until DATE DEFAULT NULL,
  max_uses INT UNSIGNED DEFAULT NULL,
  use_count INT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_promo_codes_code_unique (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Kortingscode op boeking ==========
CREATE TABLE IF NOT EXISTS gymies_booking_promo (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  promo_code_id BIGINT UNSIGNED NOT NULL,
  discount_applied_cents INT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_booking_promo_booking_unique (booking_id),
  CONSTRAINT gymies_booking_promo_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE CASCADE,
  CONSTRAINT gymies_booking_promo_code_fk
    FOREIGN KEY (promo_code_id) REFERENCES gymies_promo_codes (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Chat ==========
CREATE TABLE IF NOT EXISTS gymies_conversations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_conversations_client (client_user_id),
  KEY gymies_conversations_trainer (trainer_user_id),
  CONSTRAINT gymies_conversations_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_conversations_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_conversations_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  conversation_id BIGINT UNSIGNED NOT NULL,
  from_user_id BIGINT UNSIGNED NOT NULL,
  body TEXT NOT NULL,
  read_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_messages_conversation (conversation_id),
  CONSTRAINT gymies_messages_conversation_fk
    FOREIGN KEY (conversation_id) REFERENCES gymies_conversations (id) ON DELETE CASCADE,
  CONSTRAINT gymies_messages_user_fk
    FOREIGN KEY (from_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Favorieten ==========
CREATE TABLE IF NOT EXISTS gymies_favorites (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_favorites_unique (client_user_id, trainer_user_id),
  CONSTRAINT gymies_favorites_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_favorites_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Wachtlijst ==========
CREATE TABLE IF NOT EXISTS gymies_waitlist (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  preferred_date_from DATE DEFAULT NULL,
  preferred_date_to DATE DEFAULT NULL,
  notes TEXT DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_waitlist_client (client_user_id),
  KEY gymies_waitlist_trainer (trainer_user_id),
  CONSTRAINT gymies_waitlist_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_waitlist_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== AVG toestemmingen ==========
CREATE TABLE IF NOT EXISTS gymies_user_consents (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  consent_type VARCHAR(64) NOT NULL,
  accepted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ip_address VARCHAR(45) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_user_consents_user (user_id),
  CONSTRAINT gymies_user_consents_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Notificatievoorkeuren ==========
CREATE TABLE IF NOT EXISTS gymies_notification_preferences (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  channel ENUM('email', 'push', 'sms') NOT NULL,
  type VARCHAR(64) NOT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_notification_preferences_unique (user_id, channel, type),
  CONSTRAINT gymies_notification_preferences_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Abonnementsplannen ==========
CREATE TABLE IF NOT EXISTS gymies_plans (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  price_cents_per_month INT UNSIGNED NOT NULL,
  sessions_included INT UNSIGNED DEFAULT NULL,
  discount_percent_on_extra DECIMAL(5,2) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Abonnementen ==========
CREATE TABLE IF NOT EXISTS gymies_subscriptions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  plan_id INT UNSIGNED NOT NULL,
  status ENUM('active', 'cancelled', 'expired') NOT NULL DEFAULT 'active',
  started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ends_at TIMESTAMP NULL DEFAULT NULL,
  stripe_subscription_id VARCHAR(255) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_subscriptions_client (client_user_id),
  KEY gymies_subscriptions_plan (plan_id),
  CONSTRAINT gymies_subscriptions_user_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_subscriptions_plan_fk
    FOREIGN KEY (plan_id) REFERENCES gymies_plans (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== Auditlog ==========
CREATE TABLE IF NOT EXISTS gymies_audit_log (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED DEFAULT NULL,
  action VARCHAR(64) NOT NULL,
  entity_type VARCHAR(64) NOT NULL,
  entity_id BIGINT UNSIGNED DEFAULT NULL,
  old_values JSON DEFAULT NULL,
  new_values JSON DEFAULT NULL,
  ip_address VARCHAR(45) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_audit_log_user (user_id),
  KEY gymies_audit_log_entity (entity_type, entity_id),
  KEY gymies_audit_log_created (created_at),
  CONSTRAINT gymies_audit_log_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
