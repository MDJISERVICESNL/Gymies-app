-- Verplaatsingsverzoek door klant: voorgestelde datum/tijd tot trainer reageert.
-- Als betaald en geen conflict: kan auto-geaccepteerd worden, trainer kan nog locatie/notitie toevoegen.
-- Draai eenmalig, negeer fout als kolommen al bestaan.

ALTER TABLE gymies_bookings
  ADD COLUMN proposed_scheduled_at DATETIME NULL DEFAULT NULL COMMENT 'Door klant voorgestelde nieuwe datum/tijd' AFTER scheduled_at;
ALTER TABLE gymies_bookings
  ADD COLUMN proposed_duration_minutes INT UNSIGNED NULL DEFAULT NULL COMMENT 'Voorgestelde duur' AFTER duration_minutes;
