SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS trainer_client_health_scores (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  health_score TINYINT UNSIGNED NOT NULL DEFAULT 0,
  retention_risk ENUM('low','medium','high') NOT NULL DEFAULT 'low',
  no_show_risk ENUM('low','medium','high') NOT NULL DEFAULT 'low',
  churn_alert TINYINT(1) NOT NULL DEFAULT 0,
  signals_json JSON DEFAULT NULL,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY trainer_client_health_scores_unique (trainer_user_id, client_user_id),
  KEY trainer_client_health_scores_risk_idx (trainer_user_id, retention_risk, no_show_risk),
  CONSTRAINT trainer_client_health_scores_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT trainer_client_health_scores_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS trainer_upsell_suggestions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  package_id BIGINT UNSIGNED NOT NULL,
  reason VARCHAR(120) DEFAULT NULL,
  confidence DECIMAL(5,4) DEFAULT NULL,
  status ENUM('pending','sent','dismissed','accepted','expired') NOT NULL DEFAULT 'pending',
  expires_at DATETIME DEFAULT NULL,
  sent_at DATETIME DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY trainer_upsell_suggestions_lookup_idx (trainer_user_id, client_user_id, status, created_at),
  KEY trainer_upsell_suggestions_package_idx (package_id),
  CONSTRAINT trainer_upsell_suggestions_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT trainer_upsell_suggestions_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT trainer_upsell_suggestions_package_fk FOREIGN KEY (package_id) REFERENCES gymies_packages (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS trainer_rebook_suggestions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  next_slot_at DATETIME DEFAULT NULL,
  reason VARCHAR(120) DEFAULT NULL,
  confidence DECIMAL(5,4) DEFAULT NULL,
  status ENUM('pending','sent','dismissed','accepted','expired') NOT NULL DEFAULT 'pending',
  sent_at DATETIME DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY trainer_rebook_suggestions_lookup_idx (trainer_user_id, client_user_id, status, next_slot_at),
  KEY trainer_rebook_suggestions_booking_idx (booking_id),
  CONSTRAINT trainer_rebook_suggestions_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT trainer_rebook_suggestions_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT trainer_rebook_suggestions_booking_fk FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO trainer_client_health_scores (
  trainer_user_id,
  client_user_id,
  health_score,
  retention_risk,
  no_show_risk,
  churn_alert,
  signals_json,
  created_at,
  updated_at
)
SELECT
  s.trainer_user_id,
  s.client_user_id,
  s.health_score,
  s.retention_risk,
  s.no_show_risk,
  s.churn_alert,
  s.signals_json,
  COALESCE(s.created_at, NOW()),
  COALESCE(s.updated_at, NOW())
FROM gymies_trainer_client_health_snapshots s
ON DUPLICATE KEY UPDATE
  health_score = VALUES(health_score),
  retention_risk = VALUES(retention_risk),
  no_show_risk = VALUES(no_show_risk),
  churn_alert = VALUES(churn_alert),
  signals_json = VALUES(signals_json),
  updated_at = VALUES(updated_at);

INSERT INTO trainer_upsell_suggestions (
  trainer_user_id,
  client_user_id,
  package_id,
  reason,
  confidence,
  status,
  expires_at,
  sent_at,
  created_at,
  updated_at
)
SELECT
  u.trainer_user_id,
  u.client_user_id,
  u.package_id,
  NULLIF(u.reason, ''),
  NULL,
  'sent',
  DATE_ADD(COALESCE(u.created_at, NOW()), INTERVAL 14 DAY),
  COALESCE(u.created_at, NOW()),
  COALESCE(u.created_at, NOW()),
  COALESCE(u.created_at, NOW())
FROM gymies_trainer_upsell_suggestion_sends u
LEFT JOIN trainer_upsell_suggestions t
  ON t.trainer_user_id = u.trainer_user_id
 AND t.client_user_id = u.client_user_id
 AND t.package_id = u.package_id
 AND t.status = 'sent'
WHERE t.id IS NULL;

