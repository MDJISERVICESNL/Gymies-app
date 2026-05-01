-- Standaard abonnementen voor landingspagina (site_subscriptions_json).
-- Voert alleen in als de waarde nog leeg is; overschrijft geen bestaande admin-config.
INSERT INTO gymies_system_settings (setting_key, setting_value)
VALUES (
  'site_subscriptions_json',
  '[{"title":"Starter","price":"€0","description":"Voor de beginnende trainer","features":["1 Actief profiel","Directe boekingen","Support via community"],"buttonText":"Begin gratis","isFeatured":false},{"title":"Pro","price":"€29","description":"Meest gekozen door experts","features":["Story functionaliteit","0% Commissie op sessies","Priority in zoekresultaten","Uitgebreide analytics"],"buttonText":"Start met Pro","isFeatured":true},{"title":"Elite","price":"€79","description":"Voor studio''s en gyms","features":["Onbeperkt trainers","Eigen branding opties","API koppelingen","Dedicated manager"],"buttonText":"Contact sales","isFeatured":false}]'
)
ON DUPLICATE KEY UPDATE setting_value = IF(TRIM(COALESCE(setting_value, '')) = '', VALUES(setting_value), setting_value);
