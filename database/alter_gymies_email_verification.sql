-- Emailverificatie bij registratie: code sturen naar e-mail, gebruiker vult code in.
-- Voer uit op de server: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_email_verification.sql

CREATE TABLE IF NOT EXISTS gymies_email_verification_codes (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    code VARCHAR(10) NOT NULL COMMENT '6-cijferige code',
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY gymies_email_verification_user (user_id),
    KEY gymies_email_verification_expires (expires_at),
    CONSTRAINT gymies_email_verification_user_fk FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
