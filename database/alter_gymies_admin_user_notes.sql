-- Interne notities op gebruikers (alleen voor medewerkers, blijven bij het account).
-- Veilig meerdere keren uitvoerbaar: alleen aanmaken als tabel niet bestaat.

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS gymies_admin_user_notes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL COMMENT 'Gebruiker waar de notitie bij hoort',
  author_user_id BIGINT UNSIGNED NOT NULL COMMENT 'Medewerker die de notitie schreef',
  note TEXT NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_admin_user_notes_user (user_id),
  KEY gymies_admin_user_notes_author (author_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
