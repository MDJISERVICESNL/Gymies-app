-- Contactgegevens op het ticket (naam, e-mail, telefoon) voor weergave in admin en in ticketoverzicht.
-- Voer uit op de server: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_support_ticket_contact.sql
-- Bij "duplicate column" negeren (kolom bestaat al).

SET NAMES utf8mb4;

ALTER TABLE gymies_support_tickets
  ADD COLUMN submitter_name VARCHAR(255) DEFAULT NULL COMMENT 'Naam indiener (bij aanmaak)';
ALTER TABLE gymies_support_tickets
  ADD COLUMN submitter_email VARCHAR(255) DEFAULT NULL COMMENT 'E-mail indiener';
ALTER TABLE gymies_support_tickets
  ADD COLUMN submitter_phone VARCHAR(32) DEFAULT NULL COMMENT 'Telefoonnummer indiener';
