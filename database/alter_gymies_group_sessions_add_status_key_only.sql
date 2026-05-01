-- Alleen index toevoegen als kolom status al bestaat (na Duplicate column bij add_status.sql).
-- Voer uit: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_group_sessions_add_status_key_only.sql

ALTER TABLE gymies_group_sessions ADD KEY gymies_group_sessions_status (status);
