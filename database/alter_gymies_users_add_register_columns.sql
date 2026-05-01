-- Voeg ontbrekende kolommen toe aan minimale gymies_users (voor registratie).
-- Draai op de server: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_users_add_register_columns.sql
-- Of: mysql -u ... -p mdjiservices < alter_gymies_users_add_register_columns.sql
ALTER TABLE gymies_users ADD COLUMN display_name VARCHAR(255) DEFAULT NULL;
ALTER TABLE gymies_users ADD COLUMN phone VARCHAR(32) DEFAULT NULL;
