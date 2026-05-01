-- Ticket-Berichten sync: GYMIES user + support_ticket_id kolom.
-- Voer uit: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_ticket_berichten_sync.sql

-- 1) GYMIES system user (berichten als afzender GYMIES)
INSERT INTO gymies_users (email, password_hash, display_name, role, is_admin, created_at, updated_at)
SELECT 'support@gymies.internal', '$2y$10$NO_LOGIN', 'GYMIES', 'klant', 0, NOW(), NOW()
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM gymies_users WHERE email = 'support@gymies.internal' LIMIT 1);

-- 2) Kolom support_ticket_id op gymies_conversations
-- (Fout "Duplicate column" = kolom bestaat al, mag genegeerd worden)
ALTER TABLE gymies_conversations ADD COLUMN support_ticket_id BIGINT UNSIGNED NULL DEFAULT NULL AFTER booking_id;
