CREATE TABLE IF NOT EXISTS gymies_mollie_oauth_states (
  state VARCHAR(64) NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  expires_at DATETIME NOT NULL,
  created_at DATETIME NOT NULL,
  PRIMARY KEY (state),
  KEY gymies_mollie_oauth_states_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
