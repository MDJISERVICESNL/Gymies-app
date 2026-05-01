-- Master Spec additions: wallet expiry, check-in systeem, payout freeze, groepsles deadline

-- 1. Wallet credits expiry (1 jaar)
ALTER TABLE gymies_wallet_transactions
  ADD COLUMN expires_at DATE DEFAULT NULL COMMENT '1 jaar na credit-toekenning' AFTER created_at;

-- 2. QR Check-in systeem op boekingen
ALTER TABLE gymies_bookings
  ADD COLUMN checkin_token VARCHAR(64) DEFAULT NULL COMMENT 'QR-token, vernieuwt elke 120s',
  ADD COLUMN checkin_token_expires_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Verloopdatum huidig QR-token',
  ADD COLUMN checkin_backup_code VARCHAR(6) DEFAULT NULL COMMENT '6-cijferige handmatige code',
  ADD COLUMN check_in_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Tijdstip van check-in (QR of handmatig)',
  ADD COLUMN check_in_method VARCHAR(16) DEFAULT NULL COMMENT 'qr_scan, manual_code, admin_override',
  ADD COLUMN check_in_lat DECIMAL(10,7) DEFAULT NULL COMMENT 'GPS latitude bij check-in',
  ADD COLUMN check_in_lng DECIMAL(10,7) DEFAULT NULL COMMENT 'GPS longitude bij check-in',
  ADD COLUMN check_in_distance_meters INT UNSIGNED DEFAULT NULL COMMENT 'Afstand tot gym bij check-in',
  ADD COLUMN check_in_audit_flag TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1=handmatige code gebruikt, review nodig';

-- 3. Payout freeze bij dispuut
ALTER TABLE gymies_payouts
  ADD COLUMN is_held TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1=bevroren wegens dispuut',
  ADD COLUMN held_reason VARCHAR(255) DEFAULT NULL,
  ADD COLUMN held_at TIMESTAMP NULL DEFAULT NULL,
  ADD COLUMN released_at TIMESTAMP NULL DEFAULT NULL,
  ADD COLUMN dispute_id BIGINT UNSIGNED DEFAULT NULL;

-- 4. Groepsles: betaaldeadline na tipping point (60 min)
ALTER TABLE gymies_group_session_participants
  ADD COLUMN payment_deadline_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Deadline voor betaling na tipping point (60 min)';
