-- Broadcast & Alert Center: in-app banners en onderhoudsmodus

CREATE TABLE IF NOT EXISTS gymies_broadcasts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  type VARCHAR(32) NOT NULL COMMENT 'banner, maintenance, push_draft',
  title VARCHAR(255) DEFAULT NULL,
  message TEXT NOT NULL,
  severity VARCHAR(32) NOT NULL DEFAULT 'info' COMMENT 'info, warning, critical',
  target_role VARCHAR(32) DEFAULT NULL COMMENT 'NULL=all, trainer, klant',
  target_region VARCHAR(64) DEFAULT NULL COMMENT 'e.g. amsterdam for segment',
  active_from TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  active_until TIMESTAMP NULL DEFAULT NULL,
  created_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_broadcasts_type (type),
  KEY gymies_broadcasts_active (active_until),
  CONSTRAINT gymies_broadcasts_created_by_fk FOREIGN KEY (created_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
