-- Mollie betaalpagina: tabellen voor betalingen en webhook.
-- Eenmalig uitvoeren op de server, bijv.:
--   mysql -u USER -p DATABASE < alter_gymies_mollie_payment_tables.sql
-- Of via Laravel deploy: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_mollie_payment_tables.sql
-- Bij "Duplicate column name 'paid_at'" onderaan: kolom bestond al, verder niets doen.

SET NAMES utf8mb4;

-- Tabel voor payment-transacties (koppeling Mollie payment id → boeking, status paid)
CREATE TABLE IF NOT EXISTS gymies_payment_transactions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    booking_id BIGINT UNSIGNED DEFAULT NULL,
    group_participant_id BIGINT UNSIGNED DEFAULT NULL,
    user_id BIGINT UNSIGNED DEFAULT NULL,
    counterparty_user_id BIGINT UNSIGNED DEFAULT NULL,
    provider VARCHAR(64) NOT NULL DEFAULT 'mollie',
    provider_transaction_id VARCHAR(255) DEFAULT NULL,
    amount_cents INT NOT NULL DEFAULT 0,
    status VARCHAR(40) NOT NULL DEFAULT 'pending',
    payment_method VARCHAR(64) DEFAULT NULL,
    paid_at TIMESTAMP NULL DEFAULT NULL,
    promo_code_id BIGINT UNSIGNED DEFAULT NULL,
    discount_applied_cents INT UNSIGNED DEFAULT 0,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY gymies_payment_transactions_booking_idx (booking_id),
    KEY gymies_payment_transactions_status_idx (status),
    KEY gymies_payment_transactions_created_idx (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- paid_at op boekingen (voor webhook). Bij fout Duplicate column: kolom bestond al, negeren.
ALTER TABLE gymies_bookings ADD COLUMN paid_at TIMESTAMP NULL DEFAULT NULL;
