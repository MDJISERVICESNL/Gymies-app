-- Fix: zaldion7@gmaill.com kan inloggen zonder vast te lopen op verificatiescherm.
-- Server: cd /var/www/gymies && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_user_zaldion7_login_fix.sql
--
-- Doet twee dingen:
-- 1) Zet email_verified_at = NU → login geeft direct token (na deploy isEmailVerifiedUser).
-- 2) Zet een bekende code 847291 (15 min geldig) als je tóch via verify-scherm wilt.

SET @email := 'zaldion7@gmaill.com';

-- Optioneel: ook zonder typo-domein als account daar staat
-- SET @email := 'zaldion7@gmail.com';

-- 1) Geverifieerd markeren
UPDATE gymies_users
SET email_verified_at = NOW(),
    updated_at = NOW()
WHERE LOWER(TRIM(email)) = LOWER(TRIM(@email))
LIMIT 1;

-- 2) Oude codes weg
DELETE FROM gymies_email_verification_codes
WHERE user_id = (SELECT id FROM (SELECT id FROM gymies_users WHERE LOWER(TRIM(email)) = LOWER(TRIM(@email)) LIMIT 1) t);

-- 3) Bekende code zodat verify-scherm ook werkt als login nog 422 geeft (oude controller)
--    Code: 847291 — 15 minuten geldig na uitvoeren script.
INSERT INTO gymies_email_verification_codes (user_id, code, expires_at)
SELECT id, '847291', DATE_ADD(NOW(), INTERVAL 15 MINUTE)
FROM gymies_users
WHERE LOWER(TRIM(email)) = LOWER(TRIM(@email))
LIMIT 1;

-- Geen rij toegevoegd? Dan bestaat dat e-mailadres niet in gymies_users — eerst registreren of e-mail controleren.
