ALTER TABLE gymies_group_sessions
  ADD COLUMN status ENUM('draft', 'collecting', 'confirmed_by_trainer', 'cancelled', 'completed') NOT NULL DEFAULT 'draft',
  ADD KEY gymies_group_sessions_status (status);
