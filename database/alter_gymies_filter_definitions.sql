-- Filter definitions: herbruikbare filterdefinities per context.
-- Admin UI, zoeken, trainer-CRM etc. kunnen hier dynamisch filters uit halen.
-- Uitvoeren: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/alter_gymies_filter_definitions.sql

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS gymies_filter_definitions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  context VARCHAR(64) NOT NULL COMMENT 'tickets, bookings, users, payouts, trainers, group_sessions, etc.',
  filter_key VARCHAR(64) NOT NULL COMMENT 'status, priority, role, date_from, etc.',
  label VARCHAR(120) NOT NULL,
  filter_type VARCHAR(32) NOT NULL DEFAULT 'select' COMMENT 'select, multiselect, date, text, boolean, number',
  options_json JSON DEFAULT NULL COMMENT 'Voor select: [{"value":"new","label":"Nieuw"}]',
  default_value VARCHAR(255) DEFAULT NULL,
  placeholder VARCHAR(120) DEFAULT NULL,
  sort_order SMALLINT NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_filter_definitions_context_key (context, filter_key),
  KEY gymies_filter_definitions_context (context),
  KEY gymies_filter_definitions_active (is_active, sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Standaard filterdefinities voor tickets
INSERT IGNORE INTO gymies_filter_definitions (context, filter_key, label, filter_type, options_json, sort_order) VALUES
('tickets', 'status', 'Status', 'select', '[
  {"value":"new","label":"Nieuw"},
  {"value":"in_progress","label":"In behandeling"},
  {"value":"waiting_customer","label":"Wacht op klant"},
  {"value":"waiting_trainer","label":"Wacht op trainer"},
  {"value":"resolved","label":"Opgelost"},
  {"value":"closed","label":"Gesloten"}
]', 10),
('tickets', 'priority', 'Prioriteit', 'select', '[
  {"value":"low","label":"Laag"},
  {"value":"medium","label":"Normaal"},
  {"value":"high","label":"Hoog"},
  {"value":"urgent","label":"Urgent"}
]', 20),
('tickets', 'category', 'Categorie', 'select', '[
  {"value":"general","label":"Algemeen"},
  {"value":"booking","label":"Boeking"},
  {"value":"payment","label":"Betaling"},
  {"value":"technical","label":"Technisch"},
  {"value":"other","label":"Overig"}
]', 30),
('tickets', 'date_from', 'Vanaf datum', 'date', NULL, 40),
('tickets', 'date_to', 'Tot datum', 'date', NULL, 50),
('tickets', 'search', 'Zoekterm', 'text', NULL, 60);

-- Standaard filterdefinities voor bookings
INSERT IGNORE INTO gymies_filter_definitions (context, filter_key, label, filter_type, options_json, sort_order) VALUES
('bookings', 'status', 'Status', 'select', '[
  {"value":"pending","label":"In afwachting"},
  {"value":"confirmed","label":"Bevestigd"},
  {"value":"reserved","label":"Gereserveerd"},
  {"value":"cancelled","label":"Geannuleerd"},
  {"value":"completed","label":"Afgerond"},
  {"value":"no_show","label":"No-show"}
]', 10),
('bookings', 'payment_status', 'Betaling', 'select', '[
  {"value":"unpaid","label":"Onbetaald"},
  {"value":"paid","label":"Betaald"},
  {"value":"cash","label":"Contant"},
  {"value":"refunded","label":"Terugbetaald"}
]', 20),
('bookings', 'date_from', 'Vanaf datum', 'date', NULL, 30),
('bookings', 'date_to', 'Tot datum', 'date', NULL, 40),
('bookings', 'trainer_id', 'Trainer', 'text', NULL, 50),
('bookings', 'client_id', 'Klant', 'text', NULL, 60);

-- Standaard filterdefinities voor users
INSERT IGNORE INTO gymies_filter_definitions (context, filter_key, label, filter_type, options_json, sort_order) VALUES
('users', 'role', 'Rol', 'select', '[
  {"value":"trainer","label":"Trainer"},
  {"value":"klant","label":"Klant"},
  {"value":"admin","label":"Admin"}
]', 10),
('users', 'subscription_status', 'Abonnement', 'select', '[
  {"value":"active","label":"Actief"},
  {"value":"trialing","label":"Proefperiode"},
  {"value":"past_due","label":"Betaling achterstallig"},
  {"value":"cancelled","label":"Geannuleerd"},
  {"value":"none","label":"Geen"}
]', 20),
('users', 'email_verified', 'E-mail geverifieerd', 'boolean', NULL, 30),
('users', 'search', 'Zoekterm (naam/email)', 'text', NULL, 40);

-- Standaard filterdefinities voor payouts
INSERT IGNORE INTO gymies_filter_definitions (context, filter_key, label, filter_type, options_json, sort_order) VALUES
('payouts', 'status', 'Status', 'select', '[
  {"value":"pending","label":"In afwachting"},
  {"value":"processing","label":"In behandeling"},
  {"value":"paid","label":"Uitbetaald"},
  {"value":"failed","label":"Mislukt"},
  {"value":"cancelled","label":"Geannuleerd"}
]', 10),
('payouts', 'date_from', 'Vanaf datum', 'date', NULL, 20),
('payouts', 'date_to', 'Tot datum', 'date', NULL, 30),
('payouts', 'trainer_id', 'Trainer', 'text', NULL, 40);

-- Standaard filterdefinities voor trainers (zoeken / publiek)
-- Plan (Starter/Pro/Studio) niet tonen aan klanten — maakt hen niet uit
INSERT IGNORE INTO gymies_filter_definitions (context, filter_key, label, filter_type, options_json, sort_order) VALUES
('trainers', 'specialty', 'Specialisme', 'select', '[
  {"value":"Personal training","label":"Personal training"},
  {"value":"Krachttraining","label":"Krachttraining"},
  {"value":"Fitness","label":"Fitness"},
  {"value":"Conditie","label":"Conditie"},
  {"value":"Afvallen","label":"Afvallen"},
  {"value":"Revalidatie","label":"Revalidatie"},
  {"value":"Yoga","label":"Yoga"},
  {"value":"Pilates","label":"Pilates"},
  {"value":"HIIT","label":"HIIT"},
  {"value":"Cardio","label":"Cardio"},
  {"value":"CrossFit","label":"CrossFit"},
  {"value":"Bootcamp","label":"Bootcamp"},
  {"value":"Boksen","label":"Boksen"},
  {"value":"Kickboksen","label":"Kickboksen"},
  {"value":"Hardlopen","label":"Hardlopen"},
  {"value":"Zwemmen","label":"Zwemmen"},
  {"value":"Bodyweight","label":"Bodyweight training"},
  {"value":"Spinning","label":"Spinning"},
  {"value":"Voeding","label":"Voeding & voedingscoaching"},
  {"value":"Senioren","label":"Senioren"},
  {"value":"Beginners","label":"Beginners"},
  {"value":"Sporters","label":"Sporters"},
  {"value":"Postnataal","label":"Postnataal"},
  {"value":"Mindfulness","label":"Mindfulness"},
  {"value":"Vrouwen","label":"Vrouwen (Woman2Woman)"}
]', 10),
('trainers', 'location', 'Locatie', 'text', NULL, 20),
('trainers', 'price_min', 'Min. prijs (€)', 'number', NULL, 30),
('trainers', 'price_max', 'Max. prijs (€)', 'number', NULL, 40),
('trainers', 'availability', 'Beschikbaar', 'select', '[
  {"value":"today","label":"Vandaag"},
  {"value":"this_week","label":"Deze week"},
  {"value":"next_week","label":"Volgende week"}
]', 50);

-- Standaard filterdefinities voor group_sessions (groepslessen)
INSERT IGNORE INTO gymies_filter_definitions (context, filter_key, label, filter_type, options_json, sort_order) VALUES
('group_sessions', 'status', 'Status', 'select', '[
  {"value":"draft","label":"Concept"},
  {"value":"published","label":"Gepubliceerd"},
  {"value":"cancelled","label":"Geannuleerd"},
  {"value":"completed","label":"Afgerond"}
]', 10),
('group_sessions', 'date_from', 'Vanaf datum', 'date', NULL, 20),
('group_sessions', 'date_to', 'Tot datum', 'date', NULL, 30),
('group_sessions', 'trainer_id', 'Trainer', 'text', NULL, 40);
