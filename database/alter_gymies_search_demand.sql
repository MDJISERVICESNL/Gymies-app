-- Zoeklog voor demand: waar zoeken klanten (locatie/plaats).
-- Gebruikt voor Demand vs Supply map en Gap Detection in admin.

CREATE TABLE IF NOT EXISTS gymies_search_log (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Optioneel: ingelogde gebruiker',
  location_query VARCHAR(255) NOT NULL COMMENT 'Zoekterm zoals getypt (stad/regio)',
  city_normalized VARCHAR(100) DEFAULT NULL COMMENT 'Genormaliseerde stad voor aggregatie',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_search_log_created (created_at),
  KEY gymies_search_log_city (city_normalized),
  CONSTRAINT gymies_search_log_user_fk FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
