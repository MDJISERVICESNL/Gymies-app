-- Elite: Teams & sub-teams
-- parent_team_id NULL = top-level team

CREATE TABLE IF NOT EXISTS gym_teams (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organisation_id BIGINT UNSIGNED NOT NULL,
  parent_team_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'NULL = top-level',
  name VARCHAR(128) NOT NULL,
  description VARCHAR(500) DEFAULT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gym_teams_org (organisation_id),
  KEY gym_teams_parent (parent_team_id),
  CONSTRAINT gym_teams_org_fk FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE CASCADE,
  CONSTRAINT gym_teams_parent_fk FOREIGN KEY (parent_team_id) REFERENCES gym_teams (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
