-- Public Profile CMS: success stories, video-pitch, SEO (trainer storefront editor).
CREATE TABLE IF NOT EXISTS gymies_trainer_storefront (
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  success_stories_json TEXT DEFAULT NULL COMMENT 'JSON array {title,body,image_url}',
  video_pitch_url VARCHAR(512) DEFAULT NULL,
  specializations_display TEXT DEFAULT NULL COMMENT 'Vrije tekst/indeling specialisaties',
  seo_title VARCHAR(255) DEFAULT NULL,
  seo_description VARCHAR(500) DEFAULT NULL,
  seo_keywords VARCHAR(500) DEFAULT NULL,
  layout_json TEXT DEFAULT NULL COMMENT 'Optioneel: sectie-volgorde etc.',
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (trainer_user_id),
  CONSTRAINT gymies_trainer_storefront_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
