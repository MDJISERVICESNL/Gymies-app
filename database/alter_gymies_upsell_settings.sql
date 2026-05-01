-- Revenue & Upsell defaults (keys: upsell_annual_contract_free_months, upsell_pro_trial_days, upsell_referral_free_months)
INSERT INTO gymies_system_settings (setting_key, setting_value)
VALUES
  ('upsell_annual_contract_free_months', '2'),
  ('upsell_pro_trial_days', '14'),
  ('upsell_referral_free_months', '1')
ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value);
