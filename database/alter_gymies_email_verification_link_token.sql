-- Deeplink-token voor e-mailverificatie. Voer uit: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_email_verification_link_token.sql
ALTER TABLE gymies_email_verification_codes ADD COLUMN link_token VARCHAR(64) NULL AFTER expires_at, ADD KEY gymies_email_verification_link_token (link_token);
