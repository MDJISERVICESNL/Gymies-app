-- Elite: Blokkades per locatie (onderhoud, privé)
-- Run na alter_gym_locations.sql

CREATE TABLE IF NOT EXISTS gym_location_blocks (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  location_id BIGINT UNSIGNED NOT NULL,
  start_at DATETIME NOT NULL,
  end_at DATETIME NOT NULL,
  reason VARCHAR(64) DEFAULT NULL COMMENT 'onderhoud, privé, overig',
  created_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gym_location_blocks_location (location_id),
  KEY gym_location_blocks_range (start_at, end_at),
  CONSTRAINT gym_location_blocks_location_fk FOREIGN KEY (location_id) REFERENCES gym_locations (id) ON DELETE CASCADE,
  CONSTRAINT gym_location_blocks_creator_fk FOREIGN KEY (created_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
