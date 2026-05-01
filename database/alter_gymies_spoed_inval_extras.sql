-- Spoed Inval extras: Live Locatie Check, Klant-Update, Lesplan, Priority Pool
-- Voer uit na alter_gymies_spoed_inval_standby.sql
-- Draai eenmalig. Bij herhaald draaien: duplicate column errors mogelijk.

-- 1. Lesplan + badge (aparte ALTERs i.v.m. idempotentie)
ALTER TABLE gymies_bookings ADD COLUMN lesson_plan_json TEXT NULL COMMENT 'Oefeningen, timer, muziek (JSON)';
ALTER TABLE gymies_bookings ADD COLUMN share_lesson_plan_with_substitute TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1=deel met invaller';
ALTER TABLE gymies_bookings ADD COLUMN spoed_inval_original_trainer_id BIGINT UNSIGNED NULL DEFAULT NULL COMMENT 'Bij spoed inval: originele trainer';

-- 2. Priority Pool: favoriete collega's
CREATE TABLE IF NOT EXISTS gymies_trainer_favorite_colleagues (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL COMMENT 'Trainer die de favorieten beheert',
  favorite_trainer_user_id BIGINT UNSIGNED NOT NULL COMMENT 'Favoriete collega',
  sort_order TINYINT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_trainer_fav_colleagues_unique (trainer_user_id, favorite_trainer_user_id),
  KEY gymies_trainer_fav_colleagues_trainer (trainer_user_id),
  CONSTRAINT gymies_trainer_fav_colleagues_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_trainer_fav_colleagues_favorite_fk
    FOREIGN KEY (favorite_trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Spoed inval offers: batch (0=favorieten eerst, 1=rest na 5 min)
ALTER TABLE gymies_spoed_inval_offers
  ADD COLUMN offer_batch TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0=favorieten, 1=rest';

-- 5. Spoed inval requests: of batch 1 al is verstuurd
ALTER TABLE gymies_spoed_inval_requests
  ADD COLUMN batch1_sent_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Wanneer batch 1 (rest) is verstuurd';
