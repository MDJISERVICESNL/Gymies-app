-- Nieuwsbrief-aanmelding bij registratie (klantenbestand).
-- Draai op de server: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_users_newsletter.sql
ALTER TABLE gymies_users ADD COLUMN newsletter_subscribed TINYINT(1) NOT NULL DEFAULT 0;
