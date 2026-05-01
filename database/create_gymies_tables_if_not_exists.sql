SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ========== GEBRUIKERS (klant en trainer) ==========
CREATE TABLE IF NOT EXISTS gymies_users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('klant', 'trainer') NOT NULL DEFAULT 'klant',
  display_name VARCHAR(255) DEFAULT NULL,
  first_name VARCHAR(255) DEFAULT NULL COMMENT 'Voornaam (facturatie, formele mails)',
  last_name VARCHAR(255) DEFAULT NULL COMMENT 'Achternaam',
  phone VARCHAR(32) DEFAULT NULL COMMENT 'Telefoonnummer voor contact',
  email_verified_at TIMESTAMP NULL DEFAULT NULL,
  phone_verified_at TIMESTAMP NULL DEFAULT NULL,
  date_of_birth DATE DEFAULT NULL COMMENT 'Optioneel, bijv. voor 18+ of doelgroep',
  preferred_language VARCHAR(10) DEFAULT 'nl' COMMENT 'nl, en voor e-mails en app',
  avatar_url VARCHAR(512) DEFAULT NULL COMMENT 'Profielfoto (klant en trainer)',
  is_admin TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Platform-admin',
  is_suspended TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Gebruiker (tijdelijk) geblokkeerd',
  suspended_reason VARCHAR(255) DEFAULT NULL,
  suspended_at TIMESTAMP NULL DEFAULT NULL,
  trainer_approved_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Trainer pas live na goedkeuring',
  business_name VARCHAR(255) DEFAULT NULL COMMENT 'Zakelijke klant/facturatie',
  vat_number VARCHAR(64) DEFAULT NULL COMMENT 'BTW-nummer',
  coc_number VARCHAR(64) DEFAULT NULL COMMENT 'KvK-nummer',
  parent_guardian_name VARCHAR(255) DEFAULT NULL COMMENT 'Voor minderjarigen',
  parent_guardian_email VARCHAR(255) DEFAULT NULL COMMENT 'Voor minderjarigen',
  parent_consent_at TIMESTAMP NULL DEFAULT NULL,
  accessibility_needs TEXT DEFAULT NULL COMMENT 'Bijv. rolstoeltoegankelijkheid',
  -- Postadres (waar woont de klant/trainer)
  address_line1 VARCHAR(255) DEFAULT NULL COMMENT 'Straat en huisnummer',
  postcode VARCHAR(20) DEFAULT NULL COMMENT 'Postcode',
  city VARCHAR(255) DEFAULT NULL COMMENT 'Plaats',
  country VARCHAR(2) DEFAULT 'NL' COMMENT 'Landcode ISO 2 (NL, BE, …)',
  latitude DECIMAL(10,7) DEFAULT NULL COMMENT 'Voor afstand/radius zoekfilter',
  longitude DECIMAL(10,7) DEFAULT NULL COMMENT 'Voor afstand/radius zoekfilter',
  data_export_requested_at TIMESTAMP NULL DEFAULT NULL COMMENT 'AVG data-export aanvraag',
  data_export_completed_at TIMESTAMP NULL DEFAULT NULL COMMENT 'AVG data-export afgerond',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_users_email_unique (email),
  KEY gymies_users_role (role),
  KEY gymies_users_postcode (postcode),
  KEY gymies_users_city (city)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== TRAINERPROFIEL (1-op-1 met user als role = trainer) ==========
CREATE TABLE IF NOT EXISTS gymies_trainer_profiles (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  bio TEXT DEFAULT NULL COMMENT 'Beschrijving van de trainer',
  specialty VARCHAR(255) DEFAULT NULL COMMENT 'Specialisatie(s), bijv. Kracht, Conditie, Revalidatie',
  hourly_rate_cents INT UNSIGNED DEFAULT NULL,
  avatar_url VARCHAR(512) DEFAULT NULL COMMENT 'Foto van de trainer',
  intro_video_url VARCHAR(512) DEFAULT NULL COMMENT 'Korte pitchvideo',
  target_audiences VARCHAR(255) DEFAULT NULL COMMENT 'Beginners, 50+, revalidatie, etc.',
  gender ENUM('female', 'male', 'non_binary', 'not_specified') DEFAULT 'not_specified',
  session_languages VARCHAR(255) DEFAULT NULL COMMENT 'Talen tijdens sessie, bijv. NL,EN',
  trial_session_cents INT UNSIGNED DEFAULT NULL COMMENT 'Proefsessie prijs',
  region VARCHAR(255) DEFAULT NULL COMMENT 'Regio(s) actief, bijv. Amsterdam, Noord-Holland, Online',
  service_radius_km INT UNSIGNED DEFAULT NULL COMMENT 'Radius voor zoeken op afstand',
  travels_to_client TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Trainer komt naar klant toe',
  address_visibility ENUM('always', 'after_confirmation', 'never') NOT NULL DEFAULT 'after_confirmation',
  trainer_verified_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Platform heeft trainer gecontroleerd',
  certifications TEXT DEFAULT NULL COMMENT 'Diploma’s/certificaten (NASM, Fitvak, etc.)',
  experience_years INT UNSIGNED DEFAULT NULL COMMENT 'Aantal jaar ervaring',
  since_year SMALLINT UNSIGNED DEFAULT NULL COMMENT 'Actief sinds jaar (alternatief voor ervaring)',
  languages VARCHAR(255) DEFAULT NULL COMMENT 'Talen, bijv. NL, EN',
  min_session_minutes INT UNSIGNED DEFAULT NULL COMMENT 'Minimale sessieduur in minuten',
  min_buffer_minutes INT UNSIGNED NOT NULL DEFAULT 15 COMMENT 'Pauze tussen sessies',
  is_available TINYINT(1) NOT NULL DEFAULT 1 COMMENT '1 = zichtbaar/boekbaar, 0 = tijdelijk uit',
  featured TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Uitgelicht op homepage',
  sort_order INT DEFAULT NULL COMMENT 'Handmatige volgorde (lager = eerder)',
  insurance_verified_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Verzekering gecontroleerd door platform',
  insurance_expires_at DATE DEFAULT NULL COMMENT 'Verloopdatum verzekering',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_trainer_profiles_user_id_unique (user_id),
  KEY gymies_trainer_profiles_available (is_available),
  KEY gymies_trainer_profiles_featured (featured),
  KEY gymies_trainer_profiles_sort (sort_order),
  CONSTRAINT gymies_trainer_profiles_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== SPECIALISMEN (vaste lijst voor zoekfilter) ==========
CREATE TABLE IF NOT EXISTS gymies_specialties (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL COMMENT 'Bijv. Kracht, Conditie, Revalidatie',
  sort_order INT DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_specialties_name_unique (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== TRAINER – MEERDERE SPECIALISMEN ==========
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

-- ========== TRAINER – VASTE LOCATIES (sportschool, adres) ==========
CREATE TABLE IF NOT EXISTS gymies_trainer_locations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL COMMENT 'Bijv. Gym X, Thuis, Online',
  address_line1 VARCHAR(255) DEFAULT NULL,
  postcode VARCHAR(20) DEFAULT NULL,
  city VARCHAR(255) DEFAULT NULL,
  latitude DECIMAL(10,7) DEFAULT NULL,
  longitude DECIMAL(10,7) DEFAULT NULL,
  location_type ENUM('gym', 'home', 'outdoor', 'online') DEFAULT 'gym',
  is_primary TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_trainer_locations_trainer (trainer_user_id),
  CONSTRAINT gymies_trainer_locations_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== BESCHIKBAARHEID – VASTE TIJDSLOTS PER TRAINER ==========
CREATE TABLE IF NOT EXISTS gymies_availability_slots (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  day_of_week TINYINT UNSIGNED NOT NULL COMMENT '1=maandag t/m 7=zondag',
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_availability_slots_trainer (trainer_user_id),
  KEY gymies_availability_slots_day (day_of_week),
  CONSTRAINT gymies_availability_slots_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== BESCHIKBAARHEID – UITZONDERINGEN (vakantie, vrije dag) ==========
CREATE TABLE IF NOT EXISTS gymies_availability_exceptions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  exception_date DATE NOT NULL,
  is_available TINYINT(1) NOT NULL DEFAULT 0 COMMENT '0=niet beschikbaar, 1=extra beschikbaar',
  start_time TIME DEFAULT NULL COMMENT 'Bij is_available=1: specifieke slot',
  end_time TIME DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_availability_exceptions_trainer (trainer_user_id),
  KEY gymies_availability_exceptions_date (exception_date),
  CONSTRAINT gymies_availability_exceptions_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== PAKKETTEN / STRIPPENKAARTEN (per trainer) ==========
CREATE TABLE IF NOT EXISTS gymies_packages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL COMMENT 'Bijv. 10 sessies',
  lesson_type ENUM('solo', 'duo', 'group') NOT NULL DEFAULT 'solo',
  sessions_count INT UNSIGNED NOT NULL,
  weeks_count INT UNSIGNED NOT NULL DEFAULT 1,
  total_cents INT UNSIGNED NOT NULL,
  valid_days INT UNSIGNED DEFAULT NULL COMMENT 'Geldig tot X dagen na aankoop',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_packages_trainer (trainer_user_id),
  CONSTRAINT gymies_packages_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== TRAINER MEDIA (GALERIJ / VIDEO) ==========
CREATE TABLE IF NOT EXISTS gymies_trainer_media (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  media_type ENUM('image', 'video') NOT NULL DEFAULT 'image',
  source_type ENUM('upload', 'external') NOT NULL DEFAULT 'external',
  file_path VARCHAR(1024) DEFAULT NULL,
  external_url VARCHAR(1024) DEFAULT NULL,
  thumbnail_url VARCHAR(1024) DEFAULT NULL,
  caption VARCHAR(500) DEFAULT NULL,
  is_public TINYINT(1) NOT NULL DEFAULT 1,
  sort_order INT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_trainer_media_trainer (trainer_user_id),
  CONSTRAINT gymies_trainer_media_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== BOEKINGEN (klant boekt sessie bij trainer) ==========
CREATE TABLE IF NOT EXISTS gymies_bookings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  scheduled_at DATETIME NOT NULL,
  duration_minutes INT UNSIGNED NOT NULL DEFAULT 60,
  status ENUM('pending', 'confirmed', 'cancelled', 'completed', 'no_show') NOT NULL DEFAULT 'pending',
  recurrence_parent_booking_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Bovenliggende boeking in reeks',
  recurrence_interval_weeks TINYINT UNSIGNED DEFAULT NULL COMMENT '1=wekelijks, 2=tweewekelijks',
  recurrence_count INT UNSIGNED DEFAULT NULL COMMENT 'Aantal sessies in reeks',
  amount_cents INT UNSIGNED DEFAULT NULL,
  payment_provider_id VARCHAR(255) DEFAULT NULL COMMENT 'Mollie/Stripe payment id',
  paid_at TIMESTAMP NULL DEFAULT NULL,
  split_payment_enabled TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Betaling in delen/deelnemers',
  split_paid_cents INT UNSIGNED DEFAULT NULL COMMENT 'Totaal betaald via delen',
  platform_fee_cents INT UNSIGNED DEFAULT NULL COMMENT 'Platform fee per boeking',
  trainer_payout_cents INT UNSIGNED DEFAULT NULL COMMENT 'Uitbetaling trainer na fee',
  auto_confirm_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Automatisch bevestigen na deadline',
  confirmation_expires_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Als niet gehaald: annuleren',
  reminder_24h_sent_at TIMESTAMP NULL DEFAULT NULL,
  reminder_1h_sent_at TIMESTAMP NULL DEFAULT NULL,
  cancellation_policy_id BIGINT UNSIGNED DEFAULT NULL,
  location_type ENUM('online', 'on_site', 'gym') DEFAULT NULL COMMENT 'Waar vindt de sessie plaats',
  location_notes TEXT DEFAULT NULL COMMENT 'Adres, Zoom-link, sportschoolnaam, etc.',
  client_notes TEXT DEFAULT NULL COMMENT 'Opmerking van klant bij boeken',
  trainer_notes TEXT DEFAULT NULL COMMENT 'Interne opmerking trainer (niet zichtbaar voor klant)',
  cancelled_at TIMESTAMP NULL DEFAULT NULL,
  cancelled_by_user_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Wie heeft geannuleerd (user_id)',
  package_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Indien boeking van strippenkaart',
  sessions_remaining INT UNSIGNED DEFAULT NULL COMMENT 'Resterende sessies van pakket na deze boeking',
  trainer_location_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Gekozen locatie van trainer',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_bookings_client (client_user_id),
  KEY gymies_bookings_trainer (trainer_user_id),
  KEY gymies_bookings_scheduled (scheduled_at),
  KEY gymies_bookings_status (status),
  KEY gymies_bookings_package (package_id),
  KEY gymies_bookings_recurrence_parent (recurrence_parent_booking_id),
  CONSTRAINT gymies_bookings_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_bookings_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_bookings_cancelled_by_fk
    FOREIGN KEY (cancelled_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL,
  CONSTRAINT gymies_bookings_recurrence_parent_fk
    FOREIGN KEY (recurrence_parent_booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL,
  CONSTRAINT gymies_bookings_package_fk
    FOREIGN KEY (package_id) REFERENCES gymies_packages (id) ON DELETE SET NULL,
  CONSTRAINT gymies_bookings_location_fk
    FOREIGN KEY (trainer_location_id) REFERENCES gymies_trainer_locations (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== BEOORDELINGEN (reviews na sessie) ==========
CREATE TABLE IF NOT EXISTS gymies_reviews (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL COMMENT 'Klant die de review schrijft',
  trainer_user_id BIGINT UNSIGNED NOT NULL COMMENT 'Trainer die beoordeeld wordt',
  rating TINYINT UNSIGNED NOT NULL COMMENT '1-5 sterren',
  review_text TEXT DEFAULT NULL,
  status ENUM('pending', 'approved', 'rejected') NOT NULL DEFAULT 'approved',
  moderated_at TIMESTAMP NULL DEFAULT NULL,
  moderated_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_reviews_booking_unique (booking_id) COMMENT 'Eén review per boeking',
  KEY gymies_reviews_trainer (trainer_user_id),
  KEY gymies_reviews_rating (rating),
  KEY gymies_reviews_status (status),
  CONSTRAINT gymies_reviews_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE CASCADE,
  CONSTRAINT gymies_reviews_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_reviews_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_reviews_moderator_fk
    FOREIGN KEY (moderated_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== SESSIES / API TOKENS ==========
CREATE TABLE IF NOT EXISTS gymies_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  token VARCHAR(255) NOT NULL,
  ip_address VARCHAR(45) DEFAULT NULL,
  user_agent VARCHAR(255) DEFAULT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_sessions_token_unique (token),
  KEY gymies_sessions_user (user_id),
  KEY gymies_sessions_expires (expires_at),
  CONSTRAINT gymies_sessions_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== IDEMPOTENCY KEYS (mutating endpoints) ==========
CREATE TABLE IF NOT EXISTS gymies_idempotency_keys (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED DEFAULT NULL,
  endpoint VARCHAR(255) NOT NULL,
  idempotency_key VARCHAR(255) NOT NULL,
  request_hash VARCHAR(128) NOT NULL,
  status_code INT NOT NULL,
  response_json JSON DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_idempotency_unique (user_id, endpoint, idempotency_key),
  KEY gymies_idempotency_expires (expires_at),
  CONSTRAINT gymies_idempotency_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== WACHTWOORD-RESET TOKENS ==========
CREATE TABLE IF NOT EXISTS gymies_password_reset_tokens (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  token VARCHAR(255) NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  used_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_password_reset_user (user_id),
  KEY gymies_password_reset_token (token),
  KEY gymies_password_reset_expires (expires_at),
  CONSTRAINT gymies_password_reset_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== FACTUREN ==========
CREATE TABLE IF NOT EXISTS gymies_invoices (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  invoice_number VARCHAR(64) NOT NULL COMMENT 'Uniek factuurnummer',
  user_id BIGINT UNSIGNED NOT NULL COMMENT 'Klant of trainer (aan wie/van wie)',
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
  KEY gymies_invoices_booking (booking_id),
  CONSTRAINT gymies_invoices_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_invoices_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== UITBETALINGEN AAN TRAINERS ==========
CREATE TABLE IF NOT EXISTS gymies_payouts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  amount_cents INT UNSIGNED NOT NULL,
  gross_cents INT UNSIGNED DEFAULT NULL,
  fee_cents INT UNSIGNED DEFAULT NULL,
  payout_frequency ENUM('weekly', 'biweekly', 'monthly') DEFAULT NULL,
  status ENUM('pending', 'paid', 'failed') NOT NULL DEFAULT 'pending',
  requested_at TIMESTAMP NULL DEFAULT NULL,
  paid_at TIMESTAMP NULL DEFAULT NULL,
  reference VARCHAR(255) DEFAULT NULL COMMENT 'Bank/Stripe reference',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_payouts_trainer (trainer_user_id),
  KEY gymies_payouts_status (status),
  CONSTRAINT gymies_payouts_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== KORTINGSCODES ==========
CREATE TABLE IF NOT EXISTS gymies_promo_codes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NULL DEFAULT NULL COMMENT 'Trainer die code bezit; NULL = legacy, niet geldig bij betaling',
  code VARCHAR(64) NOT NULL COMMENT 'Unieke code, bijv. INTRO20',
  discount_type ENUM('percent', 'fixed') NOT NULL,
  value_cents INT UNSIGNED NOT NULL COMMENT 'Percentage (1-100) of bedrag in centen',
  valid_from DATE DEFAULT NULL,
  valid_until DATE DEFAULT NULL,
  max_uses INT UNSIGNED DEFAULT NULL COMMENT 'Maximaal aantal keer inwisselen',
  use_count INT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_promo_codes_code_unique (code),
  KEY gymies_promo_codes_trainer (trainer_user_id),
  CONSTRAINT gymies_promo_codes_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== KORTINGSCODE OP BOEKING ==========
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

-- ========== CHAT – CONVERSATIES ==========
CREATE TABLE IF NOT EXISTS gymies_conversations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Optioneel: gesprek over een boeking',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_conversations_client (client_user_id),
  KEY gymies_conversations_trainer (trainer_user_id),
  KEY gymies_conversations_booking (booking_id),
  CONSTRAINT gymies_conversations_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_conversations_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_conversations_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== CHAT – BERICHTEN ==========
CREATE TABLE IF NOT EXISTS gymies_messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  conversation_id BIGINT UNSIGNED NOT NULL,
  from_user_id BIGINT UNSIGNED NOT NULL,
  body TEXT NOT NULL,
  read_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_messages_conversation (conversation_id),
  KEY gymies_messages_from (from_user_id),
  CONSTRAINT gymies_messages_conversation_fk
    FOREIGN KEY (conversation_id) REFERENCES gymies_conversations (id) ON DELETE CASCADE,
  CONSTRAINT gymies_messages_user_fk
    FOREIGN KEY (from_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== FAVORIETEN (klant slaat trainer op) ==========
CREATE TABLE IF NOT EXISTS gymies_favorites (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_favorites_unique (client_user_id, trainer_user_id),
  KEY gymies_favorites_client (client_user_id),
  KEY gymies_favorites_trainer (trainer_user_id),
  CONSTRAINT gymies_favorites_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_favorites_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== WACHTLIJST ==========
CREATE TABLE IF NOT EXISTS gymies_waitlist (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  requested_for_scheduled_at DATETIME DEFAULT NULL COMMENT 'Wachtlijst op specifiek tijdslot',
  availability_slot_id BIGINT UNSIGNED DEFAULT NULL,
  preferred_date_from DATE DEFAULT NULL,
  preferred_date_to DATE DEFAULT NULL,
  notes TEXT DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_waitlist_client (client_user_id),
  KEY gymies_waitlist_trainer (trainer_user_id),
  KEY gymies_waitlist_slot (availability_slot_id),
  CONSTRAINT gymies_waitlist_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_waitlist_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_waitlist_slot_fk
    FOREIGN KEY (availability_slot_id) REFERENCES gymies_availability_slots (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== AVG – TOESTEMMINGEN ==========
CREATE TABLE IF NOT EXISTS gymies_user_consents (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  consent_type VARCHAR(64) NOT NULL COMMENT 'terms, privacy, marketing',
  accepted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ip_address VARCHAR(45) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_user_consents_user (user_id),
  KEY gymies_user_consents_type (consent_type),
  CONSTRAINT gymies_user_consents_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== NOTIFICATIEVOORKEUREN ==========
CREATE TABLE IF NOT EXISTS gymies_notification_preferences (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  channel ENUM('email', 'push', 'sms') NOT NULL,
  type VARCHAR(64) NOT NULL COMMENT 'reminder, booking_confirmed, marketing, etc.',
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  priority_mode ENUM('all', 'important_only') NOT NULL DEFAULT 'all',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_notification_preferences_unique (user_id, channel, type),
  CONSTRAINT gymies_notification_preferences_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_notification_user_settings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  quiet_hours_enabled TINYINT(1) NOT NULL DEFAULT 0,
  quiet_hours_start VARCHAR(5) NOT NULL DEFAULT '22:00',
  quiet_hours_end VARCHAR(5) NOT NULL DEFAULT '07:00',
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_notification_user_settings_user_unique (user_id),
  CONSTRAINT gymies_notification_user_settings_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== COMMUNICATIE – AUTOMATISCHE MELDINGEN ==========
CREATE TABLE IF NOT EXISTS gymies_notification_queue (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  channel ENUM('email', 'push', 'sms', 'in_app') NOT NULL,
  event_type VARCHAR(64) NOT NULL COMMENT 'booking_created, booking_cancelled, review_received, etc.',
  payload_json JSON DEFAULT NULL,
  scheduled_for TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  sent_at TIMESTAMP NULL DEFAULT NULL,
  failed_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_notification_queue_user (user_id),
  KEY gymies_notification_queue_scheduled (scheduled_for),
  CONSTRAINT gymies_notification_queue_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== ABONNEMENTSPLANNEN ==========
CREATE TABLE IF NOT EXISTS gymies_plans (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  price_cents_per_month INT UNSIGNED NOT NULL,
  sessions_included INT UNSIGNED DEFAULT NULL COMMENT 'Aantal sessies per maand',
  discount_percent_on_extra DECIMAL(5,2) DEFAULT NULL COMMENT 'Korting op extra sessies',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== ABONNEMENTEN (klant) ==========
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
  KEY gymies_subscriptions_status (status),
  CONSTRAINT gymies_subscriptions_user_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_subscriptions_plan_fk
    FOREIGN KEY (plan_id) REFERENCES gymies_plans (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== AUDITLOG ==========
CREATE TABLE IF NOT EXISTS gymies_audit_log (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Wie (nullable bij systeem)',
  action VARCHAR(64) NOT NULL COMMENT 'created, updated, cancelled, etc.',
  entity_type VARCHAR(64) NOT NULL COMMENT 'booking, user, invoice, etc.',
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

-- ========== TRAINER AANBOD – GALERIJ ==========
CREATE TABLE IF NOT EXISTS gymies_trainer_gallery (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  media_type ENUM('image', 'video') NOT NULL DEFAULT 'image',
  media_url VARCHAR(512) NOT NULL,
  caption VARCHAR(255) DEFAULT NULL,
  sort_order INT DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_trainer_gallery_trainer (trainer_user_id),
  CONSTRAINT gymies_trainer_gallery_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== TRAINER AANBOD – PRIJS PER TYPE/LOCATIE ==========
CREATE TABLE IF NOT EXISTS gymies_trainer_session_pricing (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  location_id BIGINT UNSIGNED DEFAULT NULL,
  session_type ENUM('one_on_one', 'duo', 'group') NOT NULL DEFAULT 'one_on_one',
  duration_minutes INT UNSIGNED NOT NULL DEFAULT 60,
  price_cents INT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_trainer_session_pricing_trainer (trainer_user_id),
  CONSTRAINT gymies_trainer_session_pricing_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_trainer_session_pricing_location_fk
    FOREIGN KEY (location_id) REFERENCES gymies_trainer_locations (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== ANNULERINGSBELEID ==========
CREATE TABLE IF NOT EXISTS gymies_cancellation_policies (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'NULL = globaal platformbeleid',
  name VARCHAR(255) NOT NULL,
  hours_before INT UNSIGNED NOT NULL COMMENT 'Minimaal X uur van tevoren annuleren',
  refund_percent TINYINT UNSIGNED NOT NULL COMMENT '0-100',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_cancellation_policies_trainer (trainer_user_id),
  CONSTRAINT gymies_cancellation_policies_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Koppel annuleerbeleid aan bestaande boekingen
ALTER TABLE gymies_bookings
  ADD CONSTRAINT gymies_bookings_cancellation_policy_fk
    FOREIGN KEY (cancellation_policy_id) REFERENCES gymies_cancellation_policies (id) ON DELETE SET NULL;

-- ========== BOEKING DEELNEMERS (voor split payments / duo) ==========
CREATE TABLE IF NOT EXISTS gymies_booking_participants (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Kan leeg zijn totdat invite geaccepteerd is',
  invited_email VARCHAR(255) DEFAULT NULL,
  participant_role ENUM('initiator', 'invitee') NOT NULL DEFAULT 'invitee',
  amount_cents INT UNSIGNED NOT NULL,
  payment_status ENUM('pending', 'paid', 'failed', 'expired') NOT NULL DEFAULT 'pending',
  paid_at TIMESTAMP NULL DEFAULT NULL,
  invite_token VARCHAR(128) DEFAULT NULL,
  invite_expires_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_booking_participants_booking_user_unique (booking_id, user_id),
  KEY gymies_booking_participants_booking (booking_id),
  KEY gymies_booking_participants_invited_email (invited_email),
  CONSTRAINT gymies_booking_participants_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE CASCADE,
  CONSTRAINT gymies_booking_participants_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== GROEPSLESSEN ==========
CREATE TABLE IF NOT EXISTS gymies_group_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  title VARCHAR(255) NOT NULL,
  description TEXT DEFAULT NULL,
  scheduled_at DATETIME NOT NULL,
  duration_minutes INT UNSIGNED NOT NULL DEFAULT 60,
  max_participants INT UNSIGNED NOT NULL DEFAULT 10,
  price_cents INT UNSIGNED NOT NULL,
  location_type ENUM('online', 'on_site', 'gym') DEFAULT 'gym',
  trainer_location_id BIGINT UNSIGNED DEFAULT NULL,
  recurrence_interval_weeks TINYINT UNSIGNED DEFAULT NULL COMMENT '1=wekelijks,2=tweewekelijks',
  recurrence_count INT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_group_sessions_trainer (trainer_user_id),
  KEY gymies_group_sessions_scheduled (scheduled_at),
  CONSTRAINT gymies_group_sessions_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_group_sessions_location_fk
    FOREIGN KEY (trainer_location_id) REFERENCES gymies_trainer_locations (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_group_session_participants (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  group_session_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  status ENUM('pending', 'confirmed', 'cancelled', 'waitlist') NOT NULL DEFAULT 'pending',
  amount_cents INT UNSIGNED DEFAULT NULL,
  paid_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_group_session_participants_unique (group_session_id, client_user_id),
  CONSTRAINT gymies_group_session_participants_session_fk
    FOREIGN KEY (group_session_id) REFERENCES gymies_group_sessions (id) ON DELETE CASCADE,
  CONSTRAINT gymies_group_session_participants_user_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== REFERRAL & LOYALITEIT ==========
CREATE TABLE IF NOT EXISTS gymies_referrals (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  referrer_user_id BIGINT UNSIGNED NOT NULL,
  referred_user_id BIGINT UNSIGNED DEFAULT NULL,
  referred_email VARCHAR(255) DEFAULT NULL,
  referral_code VARCHAR(64) NOT NULL,
  status ENUM('pending', 'completed', 'expired') NOT NULL DEFAULT 'pending',
  reward_cents INT UNSIGNED DEFAULT NULL,
  rewarded_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_referrals_code_unique (referral_code),
  KEY gymies_referrals_referrer (referrer_user_id),
  CONSTRAINT gymies_referrals_referrer_fk
    FOREIGN KEY (referrer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_referrals_referred_fk
    FOREIGN KEY (referred_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_loyalty_points_ledger (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  source_type VARCHAR(64) NOT NULL COMMENT 'booking, referral, admin_adjustment',
  source_id BIGINT UNSIGNED DEFAULT NULL,
  points_delta INT NOT NULL COMMENT 'Kan + of - zijn',
  notes VARCHAR(255) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_loyalty_points_user (user_id),
  CONSTRAINT gymies_loyalty_points_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_reward_redemptions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  reward_type ENUM('discount', 'free_session', 'wallet_credit') NOT NULL,
  points_spent INT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT gymies_reward_redemptions_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_reward_redemptions_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== WALLET / TEGOED ==========
CREATE TABLE IF NOT EXISTS gymies_user_wallets (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  balance_cents INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_user_wallets_user_unique (user_id),
  CONSTRAINT gymies_user_wallets_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_wallet_transactions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  wallet_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  tx_type ENUM('topup', 'debit', 'refund', 'adjustment') NOT NULL,
  amount_cents INT NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_wallet_transactions_wallet (wallet_id),
  CONSTRAINT gymies_wallet_transactions_wallet_fk
    FOREIGN KEY (wallet_id) REFERENCES gymies_user_wallets (id) ON DELETE CASCADE,
  CONSTRAINT gymies_wallet_transactions_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== BETALING & COMPLIANCE ==========
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

CREATE TABLE IF NOT EXISTS gymies_user_direct_debit_mandates (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  provider VARCHAR(64) NOT NULL COMMENT 'Mollie/Stripe',
  mandate_id VARCHAR(128) NOT NULL,
  status ENUM('active', 'revoked', 'failed') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_user_direct_debit_mandates_unique (provider, mandate_id),
  CONSTRAINT gymies_user_direct_debit_mandates_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_vat_rates (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  country_code VARCHAR(2) NOT NULL,
  rate_percent DECIMAL(5,2) NOT NULL,
  valid_from DATE NOT NULL,
  valid_until DATE DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_vat_rates_country (country_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_document_uploads (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  type ENUM('insurance', 'id', 'contract', 'certificate', 'other') NOT NULL,
  file_url VARCHAR(512) NOT NULL,
  verified_at TIMESTAMP NULL DEFAULT NULL,
  verified_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  expires_at DATE DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_document_uploads_user (user_id),
  CONSTRAINT gymies_document_uploads_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_document_uploads_verifier_fk
    FOREIGN KEY (verified_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_invoice_batches (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  period_year SMALLINT UNSIGNED NOT NULL,
  period_month TINYINT UNSIGNED NOT NULL,
  total_cents INT UNSIGNED NOT NULL,
  vat_cents INT UNSIGNED NOT NULL DEFAULT 0,
  status ENUM('draft', 'issued', 'paid') NOT NULL DEFAULT 'draft',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_invoice_batches_unique (user_id, period_year, period_month),
  CONSTRAINT gymies_invoice_batches_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== TEVREDENHEID / GESCHILLEN ==========
CREATE TABLE IF NOT EXISTS gymies_review_responses (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  review_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_review_responses_review_unique (review_id),
  CONSTRAINT gymies_review_responses_review_fk
    FOREIGN KEY (review_id) REFERENCES gymies_reviews (id) ON DELETE CASCADE,
  CONSTRAINT gymies_review_responses_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_review_reports (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  review_id BIGINT UNSIGNED NOT NULL,
  reported_by_user_id BIGINT UNSIGNED NOT NULL,
  reason VARCHAR(255) DEFAULT NULL,
  status ENUM('open', 'resolved', 'rejected') NOT NULL DEFAULT 'open',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT gymies_review_reports_review_fk
    FOREIGN KEY (review_id) REFERENCES gymies_reviews (id) ON DELETE CASCADE,
  CONSTRAINT gymies_review_reports_user_fk
    FOREIGN KEY (reported_by_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_disputes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  raised_by_user_id BIGINT UNSIGNED NOT NULL,
  reason VARCHAR(255) DEFAULT NULL,
  details TEXT DEFAULT NULL,
  status ENUM('open', 'in_progress', 'resolved', 'rejected') NOT NULL DEFAULT 'open',
  resolution_notes TEXT DEFAULT NULL,
  closed_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_disputes_booking (booking_id),
  CONSTRAINT gymies_disputes_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE CASCADE,
  CONSTRAINT gymies_disputes_user_fk
    FOREIGN KEY (raised_by_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== ANALYTICS & RAPPORTAGE ==========
CREATE TABLE IF NOT EXISTS gymies_report_cache (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  report_type VARCHAR(64) NOT NULL,
  period_key VARCHAR(32) NOT NULL COMMENT 'Bijv. 2026-02 of week-2026-08',
  data_json JSON NOT NULL,
  generated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_report_cache_unique (report_type, period_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_dashboard_widgets (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  widget_type VARCHAR(64) NOT NULL,
  position INT UNSIGNED NOT NULL DEFAULT 0,
  config_json JSON DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_dashboard_widgets_user (user_id),
  CONSTRAINT gymies_dashboard_widgets_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== ZOEKEN & FILTERS ==========
CREATE TABLE IF NOT EXISTS gymies_search_recommendations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Voor personalisatie, NULL = algemeen',
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  reason VARCHAR(64) DEFAULT NULL COMMENT 'also_viewed, popular_nearby, etc.',
  score DECIMAL(8,4) NOT NULL DEFAULT 0.0000,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_search_recommendations_user (user_id),
  KEY gymies_search_recommendations_trainer (trainer_user_id),
  CONSTRAINT gymies_search_recommendations_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_search_recommendations_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== JURIDISCH & AVG ==========
CREATE TABLE IF NOT EXISTS gymies_legal_documents (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  doc_type ENUM('terms', 'privacy', 'cookie') NOT NULL,
  version VARCHAR(32) NOT NULL,
  content_url VARCHAR(512) DEFAULT NULL,
  published_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_legal_documents_unique (doc_type, version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_user_legal_acceptances (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  legal_document_id BIGINT UNSIGNED NOT NULL,
  accepted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ip_address VARCHAR(45) DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_user_legal_acceptances_unique (user_id, legal_document_id),
  CONSTRAINT gymies_user_legal_acceptances_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_user_legal_acceptances_doc_fk
    FOREIGN KEY (legal_document_id) REFERENCES gymies_legal_documents (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_cookie_preferences (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  analytics_enabled TINYINT(1) NOT NULL DEFAULT 0,
  marketing_enabled TINYINT(1) NOT NULL DEFAULT 0,
  functional_enabled TINYINT(1) NOT NULL DEFAULT 1,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_cookie_preferences_user_unique (user_id),
  CONSTRAINT gymies_cookie_preferences_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ========== TECHNISCH & SCHAAL ==========
CREATE TABLE IF NOT EXISTS gymies_system_settings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  setting_key VARCHAR(128) NOT NULL,
  setting_value TEXT DEFAULT NULL,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_system_settings_key_unique (setting_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_app_versions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  platform ENUM('web', 'ios', 'android', 'api') NOT NULL,
  version VARCHAR(32) NOT NULL,
  build_number VARCHAR(32) DEFAULT NULL,
  released_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_app_versions_platform (platform)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_backup_runs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at TIMESTAMP NULL DEFAULT NULL,
  status ENUM('running', 'success', 'failed') NOT NULL DEFAULT 'running',
  backup_location VARCHAR(512) DEFAULT NULL,
  notes TEXT DEFAULT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_rate_limit_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ip_address VARCHAR(45) DEFAULT NULL,
  user_id BIGINT UNSIGNED DEFAULT NULL,
  endpoint VARCHAR(255) NOT NULL,
  blocked_until TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_rate_limit_events_user (user_id),
  CONSTRAINT gymies_rate_limit_events_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_api_error_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED DEFAULT NULL,
  endpoint VARCHAR(255) DEFAULT NULL,
  error_code VARCHAR(64) DEFAULT NULL,
  message TEXT DEFAULT NULL,
  context_json JSON DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_api_error_logs_user (user_id),
  CONSTRAINT gymies_api_error_logs_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
