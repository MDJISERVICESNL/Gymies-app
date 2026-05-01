-- Spoed Inval: trainer vraagt invaller voor sessie(s) bij overmacht.
-- Flow: trainer kiest sessies → systeem zoekt beschikbare trainers → invaller krijgt melding → accepteert/weigert → betaling gaat naar invaller.
--
-- Voer uit: php gymies_deploy/run_migrate_gymies_sql_server.php database/alter_gymies_spoed_inval.sql

-- Hoofdverzoek: originele trainer vraagt spoed inval aan
CREATE TABLE IF NOT EXISTS gymies_spoed_inval_requests (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  original_trainer_user_id BIGINT UNSIGNED NOT NULL COMMENT 'Trainer die inval vraagt',
  status ENUM('pending', 'accepted', 'declined', 'cancelled', 'expired') NOT NULL DEFAULT 'pending',
  substitute_trainer_user_id BIGINT UNSIGNED NULL DEFAULT NULL COMMENT 'Invaller die heeft geaccepteerd',
  expires_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Deadline voor reactie invallers',
  support_ticket_id BIGINT UNSIGNED NULL DEFAULT NULL COMMENT 'Ticket voor betalingsafhandeling na acceptatie',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_spoed_inval_requests_original (original_trainer_user_id),
  KEY gymies_spoed_inval_requests_substitute (substitute_trainer_user_id),
  KEY gymies_spoed_inval_requests_status (status),
  CONSTRAINT gymies_spoed_inval_requests_original_fk
    FOREIGN KEY (original_trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_spoed_inval_requests_substitute_fk
    FOREIGN KEY (substitute_trainer_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Koppeling: welke boekingen horen bij dit verzoek
CREATE TABLE IF NOT EXISTS gymies_spoed_inval_booking_links (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  spoed_inval_request_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_spoed_inval_booking_links_unique (spoed_inval_request_id, booking_id),
  KEY gymies_spoed_inval_booking_links_booking (booking_id),
  CONSTRAINT gymies_spoed_inval_booking_links_request_fk
    FOREIGN KEY (spoed_inval_request_id) REFERENCES gymies_spoed_inval_requests (id) ON DELETE CASCADE,
  CONSTRAINT gymies_spoed_inval_booking_links_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Aanbiedingen aan potentiële invallers (één per trainer per verzoek)
CREATE TABLE IF NOT EXISTS gymies_spoed_inval_offers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  spoed_inval_request_id BIGINT UNSIGNED NOT NULL,
  substitute_trainer_user_id BIGINT UNSIGNED NOT NULL,
  status ENUM('pending', 'accepted', 'declined') NOT NULL DEFAULT 'pending',
  responded_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_spoed_inval_offers_unique (spoed_inval_request_id, substitute_trainer_user_id),
  KEY gymies_spoed_inval_offers_substitute (substitute_trainer_user_id),
  CONSTRAINT gymies_spoed_inval_offers_request_fk
    FOREIGN KEY (spoed_inval_request_id) REFERENCES gymies_spoed_inval_requests (id) ON DELETE CASCADE,
  CONSTRAINT gymies_spoed_inval_offers_substitute_fk
    FOREIGN KEY (substitute_trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Audit: spoed inval overdracht (voor support ticket body)
CREATE TABLE IF NOT EXISTS gymies_spoed_inval_audit (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  spoed_inval_request_id BIGINT UNSIGNED NOT NULL,
  action VARCHAR(64) NOT NULL COMMENT 'request_created, offer_sent, offer_accepted, offer_declined, transfer_completed',
  actor_user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  payload_json JSON DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_spoed_inval_audit_request (spoed_inval_request_id),
  CONSTRAINT gymies_spoed_inval_audit_request_fk
    FOREIGN KEY (spoed_inval_request_id) REFERENCES gymies_spoed_inval_requests (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
