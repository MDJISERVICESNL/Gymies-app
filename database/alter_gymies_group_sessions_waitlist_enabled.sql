-- Wachtlijst aan/uit per groepsles (Studio). Uit = bij vol geen nieuwe inschrijving, aan = wachtlijst zoals nu.
-- Idempotent: bij duplicate column handmatig overslaan of runner negeert fout.
-- Geen puntkomma's in deze commentregels (migratie-splitter split op ;).
ALTER TABLE gymies_group_sessions
  ADD COLUMN waitlist_enabled TINYINT(1) NOT NULL DEFAULT 1 COMMENT '0=vol is vol, 1=wachtlijst toestaan' AFTER max_participants;
