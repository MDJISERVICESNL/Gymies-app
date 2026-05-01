-- CRM dossier: interne notities, medische achtergrond, langetermijndoelen (per trainer+klant).
-- Sessienotities: korte note na afloop sessie gekoppeld aan booking.
CREATE TABLE IF NOT EXISTS gymies_client_dossier (
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  internal_notes TEXT DEFAULT NULL COMMENT 'Verslagen, gespreksnotities',
  medical_background TEXT DEFAULT NULL COMMENT 'Medische achtergrond (trainer-only)',
  goals_long_term TEXT DEFAULT NULL COMMENT 'Doelen op lange termijn',
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (trainer_user_id, client_user_id),
  KEY gymies_client_dossier_client (client_user_id),
  CONSTRAINT gymies_client_dossier_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_client_dossier_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_client_session_notes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  note TEXT NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_client_session_notes_booking_unique (booking_id),
  KEY gymies_client_session_notes_trainer (trainer_user_id),
  CONSTRAINT gymies_client_session_notes_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE CASCADE,
  CONSTRAINT gymies_client_session_notes_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
