-- Content moderation: profielen (bio/foto) wachtrij + shadow ranking (kwaliteitsscore)

ALTER TABLE gymies_trainer_profiles
  ADD COLUMN moderation_status VARCHAR(32) DEFAULT 'approved' COMMENT 'pending_review, approved, rejected' AFTER sort_order,
  ADD COLUMN moderation_reviewed_at TIMESTAMP NULL DEFAULT NULL AFTER moderation_status,
  ADD COLUMN moderation_reviewed_by_user_id BIGINT UNSIGNED DEFAULT NULL AFTER moderation_reviewed_at,
  ADD COLUMN moderation_reject_reason VARCHAR(500) DEFAULT NULL AFTER moderation_reviewed_by_user_id,
  ADD COLUMN quality_score SMALLINT UNSIGNED DEFAULT NULL COMMENT '0-100, shadow ranking zoekresultaten' AFTER moderation_reject_reason,
  ADD KEY gymies_trainer_profiles_moderation (moderation_status),
  ADD KEY gymies_trainer_profiles_quality (quality_score);
