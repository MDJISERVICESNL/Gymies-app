-- Migratie: alle voorgestelde toevoegingen (users, trainer_profiles, bookings, reviews)
-- Alleen uitvoeren als de tabellen gymies_* al bestaan (na create_gymies_tables of eerdere alter).
-- Bij "Duplicate column name" of "Duplicate table": die stap overslaan (staat er al).

SET NAMES utf8mb4;

-- ========== gymies_users: voornaam, achternaam, postadres, geboortedatum, taal, avatar ==========
ALTER TABLE gymies_users
  ADD COLUMN first_name VARCHAR(255) DEFAULT NULL COMMENT 'Voornaam' AFTER display_name,
  ADD COLUMN last_name VARCHAR(255) DEFAULT NULL COMMENT 'Achternaam' AFTER first_name;
-- (phone staat er mogelijk al; zo ja, volgende ALTER geeft duplicate column – dan weglaten of apart uitvoeren)

ALTER TABLE gymies_users
  ADD COLUMN date_of_birth DATE DEFAULT NULL COMMENT 'Optioneel' AFTER phone_verified_at,
  ADD COLUMN preferred_language VARCHAR(10) DEFAULT 'nl' COMMENT 'nl, en' AFTER date_of_birth,
  ADD COLUMN avatar_url VARCHAR(512) DEFAULT NULL COMMENT 'Profielfoto' AFTER preferred_language,
  ADD COLUMN address_line1 VARCHAR(255) DEFAULT NULL COMMENT 'Straat en huisnummer' AFTER avatar_url,
  ADD COLUMN postcode VARCHAR(20) DEFAULT NULL COMMENT 'Postcode' AFTER address_line1,
  ADD COLUMN city VARCHAR(255) DEFAULT NULL COMMENT 'Plaats' AFTER postcode,
  ADD COLUMN country VARCHAR(2) DEFAULT 'NL' COMMENT 'Landcode' AFTER city;

-- Index voor zoeken op postcode/plaats (optioneel)
ALTER TABLE gymies_users ADD KEY gymies_users_postcode (postcode);
ALTER TABLE gymies_users ADD KEY gymies_users_city (city);

-- ========== gymies_trainer_profiles: certificaten, ervaring, talen, min duur, beschikbaar, uitgelicht, volgorde ==========
ALTER TABLE gymies_trainer_profiles
  ADD COLUMN certifications TEXT DEFAULT NULL COMMENT 'Diploma’s/certificaten' AFTER trainer_verified_at,
  ADD COLUMN experience_years INT UNSIGNED DEFAULT NULL AFTER certifications,
  ADD COLUMN since_year SMALLINT UNSIGNED DEFAULT NULL AFTER experience_years,
  ADD COLUMN languages VARCHAR(255) DEFAULT NULL AFTER since_year,
  ADD COLUMN min_session_minutes INT UNSIGNED DEFAULT NULL AFTER languages,
  ADD COLUMN is_available TINYINT(1) NOT NULL DEFAULT 1 COMMENT '1=boekbaar' AFTER min_session_minutes,
  ADD COLUMN featured TINYINT(1) NOT NULL DEFAULT 0 AFTER is_available,
  ADD COLUMN sort_order INT DEFAULT NULL AFTER featured;

ALTER TABLE gymies_trainer_profiles ADD KEY gymies_trainer_profiles_available (is_available);
ALTER TABLE gymies_trainer_profiles ADD KEY gymies_trainer_profiles_featured (featured);
ALTER TABLE gymies_trainer_profiles ADD KEY gymies_trainer_profiles_sort (sort_order);

-- ========== gymies_bookings: locatie, notities, annulering ==========
ALTER TABLE gymies_bookings
  ADD COLUMN location_type ENUM('online', 'on_site', 'gym') DEFAULT NULL AFTER paid_at,
  ADD COLUMN location_notes TEXT DEFAULT NULL AFTER location_type,
  ADD COLUMN client_notes TEXT DEFAULT NULL AFTER location_notes,
  ADD COLUMN trainer_notes TEXT DEFAULT NULL AFTER client_notes,
  ADD COLUMN cancelled_at TIMESTAMP NULL DEFAULT NULL AFTER trainer_notes,
  ADD COLUMN cancelled_by_user_id BIGINT UNSIGNED DEFAULT NULL AFTER cancelled_at;

ALTER TABLE gymies_bookings
  ADD CONSTRAINT gymies_bookings_cancelled_by_fk
  FOREIGN KEY (cancelled_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL;

-- ========== gymies_reviews (nieuwe tabel) ==========
CREATE TABLE IF NOT EXISTS gymies_reviews (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  rating TINYINT UNSIGNED NOT NULL COMMENT '1-5 sterren',
  review_text TEXT DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_reviews_booking_unique (booking_id),
  KEY gymies_reviews_trainer (trainer_user_id),
  KEY gymies_reviews_rating (rating),
  CONSTRAINT gymies_reviews_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE CASCADE,
  CONSTRAINT gymies_reviews_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_reviews_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
