-- Elite: Uitnodigingslinks voor trainers

CREATE TABLE IF NOT EXISTS gym_invites (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organisation_id BIGINT UNSIGNED NOT NULL,
  token VARCHAR(64) NOT NULL,
  created_by_user_id BIGINT UNSIGNED NOT NULL,
  expires_at DATETIME DEFAULT NULL,
  max_uses INT UNSIGNED DEFAULT NULL COMMENT 'NULL = onbeperkt',
  used_count INT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gym_invites_token (token),
  KEY gym_invites_org (organisation_id),
  CONSTRAINT gym_invites_org_fk FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE CASCADE,
  CONSTRAINT gym_invites_creator_fk FOREIGN KEY (created_by_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
