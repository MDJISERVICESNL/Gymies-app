-- Dispute & Resolution Center: resolution_type (client/trainer/split), resolved_by, dispute messages

ALTER TABLE gymies_disputes
  ADD COLUMN resolution_type VARCHAR(32) DEFAULT NULL COMMENT 'client=trainer/trainer=client/split' AFTER resolution_notes,
  ADD COLUMN resolved_by_user_id BIGINT UNSIGNED DEFAULT NULL AFTER resolution_type,
  ADD CONSTRAINT gymies_disputes_resolved_by_fk
    FOREIGN KEY (resolved_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS gymies_dispute_messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dispute_id BIGINT UNSIGNED NOT NULL,
  author_user_id BIGINT UNSIGNED NOT NULL,
  message TEXT NOT NULL,
  is_internal TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1=alleen admin zichtbaar',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_dispute_messages_dispute (dispute_id),
  CONSTRAINT gymies_dispute_messages_dispute_fk
    FOREIGN KEY (dispute_id) REFERENCES gymies_disputes (id) ON DELETE CASCADE,
  CONSTRAINT gymies_dispute_messages_author_fk
    FOREIGN KEY (author_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
