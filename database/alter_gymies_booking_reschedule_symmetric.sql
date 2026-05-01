-- Symmetrische verplaatsingsverzoeken: wie heeft voorgesteld + wanneer (voor vervaldatum 24u).
-- Draai eenmalig, negeer fout als kolommen al bestaan.

ALTER TABLE gymies_bookings
  ADD COLUMN proposed_by_user_id BIGINT UNSIGNED NULL DEFAULT NULL COMMENT 'Wie heeft het verplaatsingsverzoek gedaan (trainer of klant)' AFTER proposed_duration_minutes;
ALTER TABLE gymies_bookings
  ADD COLUMN proposed_at DATETIME NULL DEFAULT NULL COMMENT 'Wanneer het verzoek is gedaan (verval 24u na proposed_at)' AFTER proposed_by_user_id;

-- Optioneel: FK naar users (zelfde DB)
-- ALTER TABLE gymies_bookings ADD CONSTRAINT gymies_bookings_proposed_by_fk
--   FOREIGN KEY (proposed_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL;
