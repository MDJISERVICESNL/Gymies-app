-- Groepslessen uitbreiding volgens docs/GROEPSLESSEN_DESIGN.md
-- Uitvoeren: mysql -u user -p database < alter_gymies_group_sessions.sql
-- Draai dit script eenmalig. Bij "Duplicate column" de betreffende regel overslaan of uitcommentariëren.

-- ========== gymies_group_sessions ==========
-- status: draft | collecting | confirmed_by_trainer | cancelled | completed
ALTER TABLE gymies_group_sessions
  ADD COLUMN status ENUM('draft', 'collecting', 'confirmed_by_trainer', 'cancelled', 'completed') NOT NULL DEFAULT 'draft' AFTER recurrence_count;

ALTER TABLE gymies_group_sessions
  ADD COLUMN min_participants INT UNSIGNED NOT NULL DEFAULT 1 AFTER max_participants;

ALTER TABLE gymies_group_sessions
  ADD COLUMN location_notes TEXT NULL AFTER trainer_location_id;

ALTER TABLE gymies_group_sessions
  ADD COLUMN organisation_id BIGINT UNSIGNED NULL AFTER location_notes;

ALTER TABLE gymies_group_sessions
  ADD COLUMN cancellation_policy_id BIGINT UNSIGNED NULL AFTER organisation_id;

ALTER TABLE gymies_group_sessions
  ADD COLUMN cancelled_at TIMESTAMP NULL DEFAULT NULL,
  ADD COLUMN cancelled_by_user_id BIGINT UNSIGNED NULL DEFAULT NULL;

ALTER TABLE gymies_group_sessions
  ADD KEY gymies_group_sessions_status (status);

-- ========== gymies_group_session_participants ==========
-- status: pending/registered (= ingeschreven), payment_pending, confirmed, cancelled, waitlist
ALTER TABLE gymies_group_session_participants
  MODIFY COLUMN status ENUM('pending', 'registered', 'payment_pending', 'confirmed', 'cancelled', 'waitlist') NOT NULL DEFAULT 'pending';

ALTER TABLE gymies_group_session_participants
  ADD COLUMN payment_provider_id VARCHAR(255) NULL AFTER paid_at;

ALTER TABLE gymies_group_session_participants
  ADD COLUMN platform_fee_cents INT UNSIGNED NULL,
  ADD COLUMN trainer_payout_cents INT UNSIGNED NULL;

ALTER TABLE gymies_group_session_participants
  ADD COLUMN cancelled_at TIMESTAMP NULL DEFAULT NULL,
  ADD COLUMN cancelled_by_user_id BIGINT UNSIGNED NULL DEFAULT NULL;

-- Aanwezigheid registreren (0=no-show, 1=aanwezig)
ALTER TABLE gymies_group_session_participants
  ADD COLUMN attended TINYINT(1) NULL DEFAULT NULL AFTER trainer_payout_cents;
