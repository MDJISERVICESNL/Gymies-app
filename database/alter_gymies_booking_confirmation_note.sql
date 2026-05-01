-- Notitie van trainer aan klant bij bevestiging (zichtbaar voor klant).
-- Voer uit op de server:
--   cd /var/www/mdjiservices.nl/laravel
--   php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_booking_confirmation_note.sql
--
-- Bij "duplicate column" kun je dit negeren (kolom bestaat al).

SET NAMES utf8mb4;

ALTER TABLE gymies_bookings
  ADD COLUMN confirmation_note TEXT DEFAULT NULL COMMENT 'Notitie van trainer aan klant bij bevestiging';

