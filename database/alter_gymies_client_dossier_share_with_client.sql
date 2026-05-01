-- Dossier voor klant zichtbaar: trainer zet "open" en vult optioneel samenvatting.
-- internal_notes + medical_background blijven ALLEEN trainer (nooit in client-API).
ALTER TABLE gymies_client_dossier
  ADD COLUMN shared_with_client_at TIMESTAMP NULL DEFAULT NULL
    COMMENT 'Niet NULL = klant mag gedeelde stukken zien in app'
    AFTER goals_long_term;

ALTER TABLE gymies_client_dossier
  ADD COLUMN client_facing_summary TEXT DEFAULT NULL
    COMMENT 'Tekst die de klant mag lezen (afspraken, doelen in klant-taal)'
    AFTER shared_with_client_at;
