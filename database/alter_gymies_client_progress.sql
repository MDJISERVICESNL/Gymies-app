-- Transformation Log / Lock-in engine: per client per trainer progressie (gewicht, PR, foto-URL, etc.)
-- Run op bestaande DB na deploy backend.

CREATE TABLE IF NOT EXISTS gymies_client_progress (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  type VARCHAR(32) NOT NULL COMMENT 'foto, gewicht, vetpercentage, pr_oefening',
  value TEXT NOT NULL COMMENT 'getal als string of image_url',
  note VARCHAR(500) DEFAULT NULL,
  is_private TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1 = alleen trainer (Elite)',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_client_progress_client_trainer (client_user_id, trainer_user_id),
  KEY gymies_client_progress_trainer_created (trainer_user_id, created_at),
  CONSTRAINT gymies_client_progress_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_client_progress_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
