SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS gymies_trainer_media (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  media_type ENUM('image', 'video') NOT NULL DEFAULT 'image',
  source_type ENUM('upload', 'external') NOT NULL DEFAULT 'external',
  file_path VARCHAR(1024) DEFAULT NULL,
  external_url VARCHAR(1024) DEFAULT NULL,
  thumbnail_url VARCHAR(1024) DEFAULT NULL,
  caption VARCHAR(500) DEFAULT NULL,
  is_public TINYINT(1) NOT NULL DEFAULT 1,
  sort_order INT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_trainer_media_trainer (trainer_user_id),
  CONSTRAINT gymies_trainer_media_user_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
