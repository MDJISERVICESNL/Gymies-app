-- Trainer dossier v2: session entries + goals + progress points
-- First-class resources for trainer CRM timeline.

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS gymies_client_session_entries (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  session_at DATETIME NOT NULL,
  session_type VARCHAR(64) NOT NULL,
  attendance_status ENUM('attended','no_show','cancelled','unknown') NOT NULL DEFAULT 'unknown',
  focus TEXT DEFAULT NULL,
  positive_notes TEXT DEFAULT NULL,
  improve_notes TEXT DEFAULT NULL,
  homework TEXT DEFAULT NULL,
  energy_score TINYINT UNSIGNED DEFAULT NULL,
  performance_score DECIMAL(10,2) DEFAULT NULL,
  visibility ENUM('shared','internal') NOT NULL DEFAULT 'internal',
  deleted_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_client_session_entries_trainer_client_session (trainer_user_id, client_user_id, session_at, id),
  KEY gymies_client_session_entries_client_visibility (client_user_id, visibility, session_at, id),
  KEY gymies_client_session_entries_booking (booking_id),
  CONSTRAINT gymies_client_session_entries_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_client_session_entries_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_client_session_entries_booking_fk FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_client_goals (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  title VARCHAR(255) NOT NULL,
  target_value DECIMAL(10,2) DEFAULT NULL,
  current_value DECIMAL(10,2) DEFAULT NULL,
  unit VARCHAR(40) DEFAULT NULL,
  status ENUM('active','done','paused','cancelled') NOT NULL DEFAULT 'active',
  due_date DATE DEFAULT NULL,
  deleted_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_client_goals_trainer_client (trainer_user_id, client_user_id, created_at, id),
  KEY gymies_client_goals_client_status (client_user_id, status),
  CONSTRAINT gymies_client_goals_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_client_goals_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_client_goal_progress_points (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  goal_id BIGINT UNSIGNED NOT NULL,
  value_numeric DECIMAL(10,2) DEFAULT NULL,
  note VARCHAR(1000) DEFAULT NULL,
  measured_at DATETIME NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_client_goal_progress_points_goal_measured (goal_id, measured_at, id),
  CONSTRAINT gymies_client_goal_progress_points_goal_fk FOREIGN KEY (goal_id) REFERENCES gymies_client_goals (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

