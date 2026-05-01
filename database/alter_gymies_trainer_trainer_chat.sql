-- Trainer-trainer chat binnen dezelfde gym (Elite).
-- Trainers kunnen onderling snel communiceren via de app.

-- Conversaties tussen twee trainers binnen één organisatie.
-- Canonical order: trainer_a_user_id < trainer_b_user_id voor unieke paren.
CREATE TABLE IF NOT EXISTS gymies_trainer_trainer_conversations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_a_user_id BIGINT UNSIGNED NOT NULL COMMENT 'Kleinste user_id van het paar',
  trainer_b_user_id BIGINT UNSIGNED NOT NULL COMMENT 'Grootste user_id van het paar',
  organisation_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_tt_conv_unique (trainer_a_user_id, trainer_b_user_id, organisation_id),
  KEY gymies_tt_conv_org (organisation_id),
  KEY gymies_tt_conv_updated (updated_at),
  CONSTRAINT gymies_tt_conv_a_fk FOREIGN KEY (trainer_a_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_tt_conv_b_fk FOREIGN KEY (trainer_b_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_tt_conv_org_fk FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Berichten in trainer-trainer conversaties.
CREATE TABLE IF NOT EXISTS gymies_trainer_trainer_messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  conversation_id BIGINT UNSIGNED NOT NULL,
  from_user_id BIGINT UNSIGNED NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_tt_msg_conversation (conversation_id),
  KEY gymies_tt_msg_from (from_user_id),
  CONSTRAINT gymies_tt_msg_conv_fk FOREIGN KEY (conversation_id) REFERENCES gymies_trainer_trainer_conversations (id) ON DELETE CASCADE,
  CONSTRAINT gymies_tt_msg_user_fk FOREIGN KEY (from_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
