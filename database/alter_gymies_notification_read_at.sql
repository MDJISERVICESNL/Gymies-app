-- Notificaties als gelezen markeren wanneer de gebruiker ze opent.
-- Draai eenmalig; negeer fout als kolom al bestaat.

ALTER TABLE gymies_notification_queue
  ADD COLUMN read_at TIMESTAMP NULL DEFAULT NULL COMMENT 'Wanneer de gebruiker de melding heeft gezien' AFTER created_at;
