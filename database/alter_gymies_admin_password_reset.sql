-- Zet wachtwoord voor admin-accounts op "password" (bcrypt).
-- Gebruik na een restore of als inloggen niet werkt:
--   php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_admin_password_reset.sql

SET NAMES utf8mb4;

-- bcrypt hash voor het wachtwoord "password"
UPDATE gymies_users
SET password_hash = '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',
    updated_at = NOW()
WHERE email IN ('admin@trainmate.app', 'trainer.anne@example.com');
