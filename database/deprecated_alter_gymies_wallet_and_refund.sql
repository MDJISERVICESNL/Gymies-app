-- Wallet credits (Gymies-balans per gebruiker) en admin refund/credit-registratie

-- Saldo op gebruikers (cache). Bij "Duplicate column" al uitgevoerd.
ALTER TABLE gymies_users
  ADD COLUMN wallet_balance_cents INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Gymies-tegoed in centen';

-- Transacties voor audit (credits/toevoegingen)
CREATE TABLE IF NOT EXISTS gymies_wallet_transactions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  amount_cents INT NOT NULL COMMENT 'Positief = credit, negatief = gebruik',
  balance_after_cents INT NOT NULL DEFAULT 0,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  reason VARCHAR(500) DEFAULT NULL,
  reference_type VARCHAR(64) NOT NULL DEFAULT 'admin_credit' COMMENT 'admin_credit, admin_refund_credit, payment_use',
  admin_user_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_wallet_transactions_user (user_id),
  KEY gymies_wallet_transactions_booking (booking_id),
  KEY gymies_wallet_transactions_created (created_at),
  CONSTRAINT gymies_wallet_transactions_user_fk FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_wallet_transactions_booking_fk FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL,
  CONSTRAINT gymies_wallet_transactions_admin_fk FOREIGN KEY (admin_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admin refund/credit-verzoeken (voor rapportage en eventueel koppeling Mollie)
CREATE TABLE IF NOT EXISTS gymies_admin_refunds (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  type VARCHAR(32) NOT NULL COMMENT 'full_refund, partial_refund, wallet_credit',
  amount_cents INT UNSIGNED NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'pending' COMMENT 'pending, completed, failed',
  reason VARCHAR(500) NOT NULL,
  admin_user_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_admin_refunds_booking (booking_id),
  KEY gymies_admin_refunds_client (client_user_id),
  KEY gymies_admin_refunds_created (created_at),
  CONSTRAINT gymies_admin_refunds_booking_fk FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE CASCADE,
  CONSTRAINT gymies_admin_refunds_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_admin_refunds_admin_fk FOREIGN KEY (admin_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
