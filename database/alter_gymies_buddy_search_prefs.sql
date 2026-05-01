-- Buddy Matcher: server-driven zoekstatus + voorkeur-trainer.
CREATE TABLE IF NOT EXISTS gymies_buddy_search_prefs (
  user_id BIGINT UNSIGNED NOT NULL,
  is_searching TINYINT(1) NOT NULL DEFAULT 0,
  preferred_trainer_id BIGINT UNSIGNED NULL DEFAULT NULL COMMENT 'Optioneel: match alleen met buddy bij deze trainer',
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  CONSTRAINT gymies_buddy_search_prefs_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_buddy_search_prefs_trainer_fk
    FOREIGN KEY (preferred_trainer_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
