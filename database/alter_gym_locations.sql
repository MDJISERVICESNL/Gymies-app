-- Elite: Resource Management – locaties (zalen, buiten, studio)
-- Idempotent: CREATE TABLE IF NOT EXISTS
-- Run: php gymies_deploy/run_migrate_gymies_sql_server.php database/alter_gym_locations.sql

CREATE TABLE IF NOT EXISTS gym_locations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organisation_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(128) NOT NULL COMMENT 'Zaal 1, Buiten 1, etc.',
  location_type ENUM('zaal', 'buiten', 'studio', 'overig') NOT NULL DEFAULT 'zaal',
  capacity INT UNSIGNED DEFAULT NULL COMMENT 'Max personen, optioneel',
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gym_locations_org (organisation_id),
  CONSTRAINT gym_locations_org_fk FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
