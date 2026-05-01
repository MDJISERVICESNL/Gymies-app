-- Groepslessen Crowdfund: wachtlijst claim-deadline (15 min), trainer penalty via gymies_trainer_penalties (group_session_id optioneel).
-- Zie Cursor assets/direct-boeken-ecosysteem.md

-- Claim-deadline voor wachtlijst: eerste op wachtlijst krijgt 15 min om te betalen.
ALTER TABLE gymies_group_session_participants
  ADD COLUMN claim_deadline_at TIMESTAMP NULL DEFAULT NULL
  COMMENT 'Einde 15 min claimtijd na vrijgekomen plek (alleen bij payment_pending uit wachtlijst).';

-- Optioneel: trainer_penalties kunnen gekoppeld zijn aan groepsles (booking_id blijft NULL).
-- Draai alleen als gymies_trainer_penalties bestaat (na alter_gymies_cancellation_policy).
ALTER TABLE gymies_trainer_penalties
  ADD COLUMN group_session_id BIGINT UNSIGNED DEFAULT NULL AFTER booking_id;

ALTER TABLE gymies_trainer_penalties
  ADD KEY gymies_trainer_penalties_group_session (group_session_id);

ALTER TABLE gymies_trainer_penalties
  ADD CONSTRAINT gymies_trainer_penalties_group_session_fk
    FOREIGN KEY (group_session_id) REFERENCES gymies_group_sessions (id) ON DELETE SET NULL;
