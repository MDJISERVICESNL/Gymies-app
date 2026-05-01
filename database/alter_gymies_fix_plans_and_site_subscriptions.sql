-- Repareer beschadigde site_subscriptions_json en zorg dat gymies_plans + website + admin in sync zijn.
-- Draai dit nadat alter_gymies_saas_model.sql is uitgevoerd (gymies_plans moet slug hebben).
--
-- 1) Zorg dat gymies_plans starter, pro, studio heeft met correcte prijzen
-- 2) Reset site_subscriptions_json naar geldige JSON (met slug) zodat sync en landingspagina werken

-- gymies_plans: upsert starter, pro, studio (vereist UNIQUE KEY op slug)
INSERT INTO gymies_plans (name, slug, price_cents_per_month, description, max_sessions_per_month, max_trainer_accounts, has_invoicing, has_crm, has_womens_choice, is_active)
SELECT 'Gymies Starter', 'starter', 2995, 'Alles om te kunnen starten.', NULL, 1, 0, 0, 1, 1
UNION ALL SELECT 'Gymies Pro', 'pro', 5995, 'Onbeperkt + facturatie + CRM.', NULL, 1, 1, 1, 1, 1
UNION ALL SELECT 'Gymies Studio', 'studio', 9995, 'Meerdere trainers.', NULL, 5, 1, 1, 1, 1
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  price_cents_per_month = VALUES(price_cents_per_month),
  description = VALUES(description),
  max_sessions_per_month = VALUES(max_sessions_per_month);

-- site_subscriptions_json: geldige JSON (met slug voor sync)
-- Prijzen komen uit gymies_plans: starter €29.95, pro €59.95, studio €99.95
INSERT INTO gymies_system_settings (setting_key, setting_value) VALUES (
  'site_subscriptions_json',
  '[{"title":"Starter","slug":"starter","price":"€29.95","description":"Voor de beginnende trainer","features":["1 Actief profiel","Directe boekingen","Support via community"],"buttonText":"Begin gratis","isFeatured":false},{"title":"Pro","slug":"pro","price":"€59.95","description":"Meest gekozen door experts","features":["Story functionaliteit","0% Commissie op sessies","Priority in zoekresultaten","Uitgebreide analytics"],"buttonText":"Start met Pro","isFeatured":true},{"title":"Studio","slug":"studio","price":"€99.95","description":"Voor studio''s en gyms","features":["Onbeperkt trainers","Eigen branding opties","API koppelingen","Dedicated manager"],"buttonText":"Contact sales","isFeatured":false}]'
)
ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value);
