-- Stickiness Features: Milestones, Emergency Sub, Corporate Wallets, Ghost-Rating

-- 1. Milestones: track completed sessions per client + pro badge voor trainers
ALTER TABLE gymies_users
  ADD COLUMN completed_sessions_count INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Totaal voltooide sessies (QR check-in)',
  ADD COLUMN milestone_tier VARCHAR(32) DEFAULT NULL COMMENT 'Klant milestone: bronze_10, silver_25, gold_50, diamond_100';

ALTER TABLE gymies_trainer_profiles
  ADD COLUMN consecutive_completed INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Opeenvolgend voltooide sessies zonder annulering',
  ADD COLUMN is_gymies_pro TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1=Gymies Pro status (50+ sessies zonder annulering)',
  ADD COLUMN gymies_pro_since TIMESTAMP NULL DEFAULT NULL;

-- 2. Emergency Sub (vervangingslogica groepslessen)
CREATE TABLE IF NOT EXISTS gymies_substitute_requests (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  group_session_id BIGINT UNSIGNED NOT NULL,
  original_trainer_id BIGINT UNSIGNED NOT NULL,
  substitute_trainer_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Wie neemt over (NULL = nog open)',
  status VARCHAR(32) NOT NULL DEFAULT 'open' COMMENT 'open, accepted, expired, cancelled',
  specialty_filter VARCHAR(255) DEFAULT NULL COMMENT 'Specialisatie om op te filteren',
  radius_km INT UNSIGNED DEFAULT 10,
  reason VARCHAR(500) DEFAULT NULL,
  accepted_at TIMESTAMP NULL DEFAULT NULL,
  expires_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Deadline voor acceptatie (bijv. 1u voor les)',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_sub_requests_session (group_session_id),
  KEY gymies_sub_requests_status (status),
  CONSTRAINT gymies_sub_requests_session_fk FOREIGN KEY (group_session_id) REFERENCES gymies_group_sessions (id) ON DELETE CASCADE,
  CONSTRAINT gymies_sub_requests_original_fk FOREIGN KEY (original_trainer_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Corporate Wallets
ALTER TABLE gymies_organisations
  ADD COLUMN wallet_balance_cents INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Bedrijfstegoed in centen';

CREATE TABLE IF NOT EXISTS gymies_corporate_wallet_transactions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organisation_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Werknemer die tegoed gebruikt',
  amount_cents INT NOT NULL COMMENT 'Positief = storting, negatief = gebruik',
  balance_after_cents INT NOT NULL DEFAULT 0,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  reason VARCHAR(500) DEFAULT NULL,
  reference_type VARCHAR(64) NOT NULL DEFAULT 'admin_deposit' COMMENT 'admin_deposit, employee_booking, admin_correction',
  admin_user_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_corp_wallet_org (organisation_id),
  KEY gymies_corp_wallet_user (user_id),
  CONSTRAINT gymies_corp_wallet_org_fk FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_corporate_invite_codes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organisation_id BIGINT UNSIGNED NOT NULL,
  code VARCHAR(32) NOT NULL UNIQUE COMMENT 'Unieke code voor werknemers',
  max_uses INT UNSIGNED DEFAULT NULL COMMENT 'NULL = onbeperkt',
  times_used INT UNSIGNED NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_corp_codes_org (organisation_id),
  CONSTRAINT gymies_corp_codes_org_fk FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Link werknemer aan bedrijf
ALTER TABLE gymies_users
  ADD COLUMN corporate_organisation_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Bedrijf waar werknemer aan gekoppeld is';

-- 4. Ghost-Rating (post-workout emoji-feedback)
CREATE TABLE IF NOT EXISTS gymies_ghost_ratings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  punctuality TINYINT UNSIGNED NOT NULL COMMENT '1-3 emoji score (slecht/ok/top)',
  energy TINYINT UNSIGNED NOT NULL COMMENT '1-3 emoji score',
  would_rebook TINYINT UNSIGNED NOT NULL COMMENT '1=nee, 2=misschien, 3=zeker',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_ghost_ratings_booking (booking_id),
  KEY gymies_ghost_ratings_trainer (trainer_user_id),
  CONSTRAINT gymies_ghost_ratings_booking_fk FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE CASCADE,
  CONSTRAINT gymies_ghost_ratings_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_ghost_ratings_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
