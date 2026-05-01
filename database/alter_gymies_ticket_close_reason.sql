-- Sluitreden bij ticket afhandelen (voor statistiek/verbetering).
-- Veilig meerdere keren uitvoerbaar.

SET NAMES utf8mb4;

-- Alleen uitvoeren als de kolom nog niet bestaat (anders: duplicate column error negeren).
ALTER TABLE gymies_support_tickets
  ADD COLUMN close_reason VARCHAR(255) DEFAULT NULL COMMENT 'Optioneel: reden/redencode bij resolved'
  AFTER resolved_at;
