-- Elite: Trainer ↔ Team koppeling

CREATE TABLE IF NOT EXISTS gym_team_members (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  team_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  role ENUM('lead', 'member') NOT NULL DEFAULT 'member',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gym_team_members_unique (team_id, trainer_user_id),
  KEY gym_team_members_trainer (trainer_user_id),
  CONSTRAINT gym_team_members_team_fk FOREIGN KEY (team_id) REFERENCES gym_teams (id) ON DELETE CASCADE,
  CONSTRAINT gym_team_members_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
