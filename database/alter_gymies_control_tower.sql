-- Control Tower: Profitability Guard, Retention, Revenue Leakage, Trainer Tiers & Bulk Marketing
-- Voer uit op de server na upload.
-- Vereisten: gymies_conversations en gymies_messages (chat) voor gymies_chat_leakage_flags.
-- Als die tabellen ontbreken, voer het bestand in twee stappen uit (eerst zonder leakage-tabel).

-- 1) Profitability: min prijs en transactiekosten via system_settings (bestaande tabel)
-- Keys: profitability_min_booking_price_cents, profitability_mollie_fee_cents, profitability_btw_percent

-- 2) Trainer tier (brons/zilver/goud) voor leaderboards
ALTER TABLE gymies_trainer_profiles
  ADD COLUMN tier VARCHAR(20) DEFAULT 'bronze' COMMENT 'bronze, silver, gold';

-- 3) Revenue Leakage: chatberichten die keywords triggeren (shadow flagging)
CREATE TABLE IF NOT EXISTS gymies_chat_leakage_flags (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  conversation_id BIGINT UNSIGNED NOT NULL,
  message_id BIGINT UNSIGNED NOT NULL,
  from_user_id BIGINT UNSIGNED NOT NULL,
  keywords_found VARCHAR(255) NOT NULL COMMENT 'Comma-separated matched keywords',
  message_snippet TEXT,
  reviewed_at TIMESTAMP NULL DEFAULT NULL,
  reviewed_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  action_taken VARCHAR(80) DEFAULT NULL COMMENT 'warning, fine, dismissed',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_chat_leakage_conversation (conversation_id),
  KEY gymies_chat_leakage_reviewed (reviewed_at),
  CONSTRAINT gymies_chat_leakage_conversation_fk FOREIGN KEY (conversation_id) REFERENCES gymies_conversations (id) ON DELETE CASCADE,
  CONSTRAINT gymies_chat_leakage_message_fk FOREIGN KEY (message_id) REFERENCES gymies_messages (id) ON DELETE CASCADE,
  CONSTRAINT gymies_chat_leakage_user_fk FOREIGN KEY (from_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_chat_leakage_reviewer_fk FOREIGN KEY (reviewed_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4) Payout reconciliation: Mollie payout id opslaan om te vergelijken
ALTER TABLE gymies_payouts
  ADD COLUMN mollie_payout_id VARCHAR(64) DEFAULT NULL COMMENT 'Mollie payout id voor reconciliation',
  ADD KEY gymies_payouts_mollie (mollie_payout_id);

-- 5) Bulk campaigns (segment + bericht, verstuurd status)
CREATE TABLE IF NOT EXISTS gymies_bulk_campaigns (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  segment_filters JSON COMMENT 'e.g. {"tier":"silver","city":"Amsterdam"}',
  message_text TEXT NOT NULL,
  message_type VARCHAR(40) DEFAULT 'push' COMMENT 'push, email, discount_code',
  discount_code VARCHAR(64) DEFAULT NULL,
  discount_percent INT UNSIGNED DEFAULT NULL,
  sent_at TIMESTAMP NULL DEFAULT NULL,
  created_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_bulk_campaigns_created (created_at),
  CONSTRAINT gymies_bulk_campaigns_creator_fk FOREIGN KEY (created_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6) Admin nudge log (push of kortingscode verstuurd naar gebruiker)
CREATE TABLE IF NOT EXISTS gymies_admin_nudges (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  nudge_type VARCHAR(40) NOT NULL COMMENT 'push, discount_code',
  title VARCHAR(255) DEFAULT NULL,
  body TEXT DEFAULT NULL,
  discount_code VARCHAR(64) DEFAULT NULL,
  created_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_admin_nudges_user (user_id),
  KEY gymies_admin_nudges_created (created_at),
  CONSTRAINT gymies_admin_nudges_user_fk FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_admin_nudges_creator_fk FOREIGN KEY (created_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 7) Demand heatmap: zoeklog (waar zoeken klanten) voor Demand vs. Supply / Gap Detection
CREATE TABLE IF NOT EXISTS gymies_search_log (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Optioneel: ingelogde gebruiker',
  location_query VARCHAR(255) NOT NULL COMMENT 'Zoekterm zoals getypt (stad/regio)',
  city_normalized VARCHAR(100) DEFAULT NULL COMMENT 'Genormaliseerde stad voor aggregatie',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_search_log_created (created_at),
  KEY gymies_search_log_city (city_normalized),
  CONSTRAINT gymies_search_log_user_fk FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
