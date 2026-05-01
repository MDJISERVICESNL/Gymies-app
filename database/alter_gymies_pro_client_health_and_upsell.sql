SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS gymies_trainer_client_health_snapshots (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  health_score TINYINT UNSIGNED NOT NULL DEFAULT 0,
  retention_risk ENUM('low','medium','high') NOT NULL DEFAULT 'low',
  no_show_risk ENUM('low','medium','high') NOT NULL DEFAULT 'low',
  churn_alert TINYINT(1) NOT NULL DEFAULT 0,
  signals_json JSON DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_trainer_client_health_unique (trainer_user_id, client_user_id),
  KEY gymies_trainer_client_health_risk (trainer_user_id, retention_risk, no_show_risk),
  CONSTRAINT gymies_trainer_client_health_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_trainer_client_health_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_trainer_upsell_suggestion_sends (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  suggestion_id VARCHAR(128) NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  package_id BIGINT UNSIGNED NOT NULL,
  reason VARCHAR(80) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_trainer_upsell_send_unique (trainer_user_id, suggestion_id),
  KEY gymies_trainer_upsell_send_client_idx (trainer_user_id, client_user_id),
  CONSTRAINT gymies_trainer_upsell_send_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_trainer_upsell_send_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

