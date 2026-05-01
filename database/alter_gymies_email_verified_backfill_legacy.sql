-- ============================================================================
-- Bestaande accounts als geverifieerd markeren (geen code meer nodig bij login)
-- ============================================================================
-- Situatie:
-- - Nieuwe registraties krijgen email_verified_at = NULL + code per mail (zoals nu).
-- - Login blokkeert als email_verified_at leeg is (GymiesAuthController::isEmailVerifiedUser).
-- - Oude users hadden vaak al een account vóór verificatie; kolom email_verified_at
--   is daarna toegevoegd met NULL → die krijgen nu ten onrechte steeds een code-flow.
--
-- Oplossing (eenmalig op de server):
-- 1) Alleen users zonder actieve (niet-verlopen) verificatiecode als legacy beschouwen:
--    die hebben nooit de nieuwe flow gestart of alleen verlopen codes → grandfather.
-- 2) Users mét nog geldige code blijven NULL tot ze de code invullen (nieuwe registraties).
--
-- Uitvoeren:
--   php gymies_deploy/run_migrate_gymies_sql_server.php database/alter_gymies_email_verified_backfill_legacy.sql
--   (of pad naar dit bestand op de server)
-- ============================================================================

-- Optioneel: verlopen codes opruimen (voorkomt rommel; CASCADE/user blijft ongewijzigd)
DELETE FROM gymies_email_verification_codes
WHERE expires_at < NOW();

-- Grandfather: NULL email_verified_at EN geen geldige code meer → zet verified op created_at
UPDATE gymies_users u
LEFT JOIN gymies_email_verification_codes c
  ON c.user_id = u.id AND c.expires_at > NOW()
SET
  u.email_verified_at = COALESCE(u.created_at, NOW()),
  u.updated_at = NOW()
WHERE
  u.email_verified_at IS NULL
  AND c.id IS NULL;

-- Codes verwijderen voor users die nu wél verified zijn (geen dubbele mails/resend-rariteit)
DELETE c FROM gymies_email_verification_codes c
INNER JOIN gymies_users u ON u.id = c.user_id
WHERE u.email_verified_at IS NOT NULL;

-- ============================================================================
-- ALTERNATIEF (alleen als je zeker weet dat er geen "net geregistreerd nog niet
-- geverifieerde" users met NULL zijn): alles met NULL in één keer vullen.
-- Uncomment alleen na overleg — overslaat code voor iedereen die nog NULL had.
--
-- UPDATE gymies_users
-- SET email_verified_at = COALESCE(created_at, NOW()), updated_at = NOW()
-- WHERE email_verified_at IS NULL;
-- DELETE FROM gymies_email_verification_codes;
-- ============================================================================
