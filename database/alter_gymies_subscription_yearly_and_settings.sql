-- ============================================================
-- Abonnementen: jaarlijks, dynamische korting, waterdichte plans
-- ============================================================

-- Draai eenmalig. Bij "Duplicate column" kolom bestaat al – dan overslaan of handmatig die regel commenten.

-- 1. gymies_subscriptions: billing interval
ALTER TABLE gymies_subscriptions
  ADD COLUMN billing_interval ENUM('monthly','yearly') NOT NULL DEFAULT 'monthly'
    COMMENT 'Maandelijks of jaarlijks factureren'
  AFTER plan_id;

-- 2. gymies_plans: optioneel vast jaartarief (NULL = bereken uit monthly + yearly_discount_percent)
ALTER TABLE gymies_plans
  ADD COLUMN price_cents_per_year INT UNSIGNED DEFAULT NULL
    COMMENT 'Vast jaartarief in centen. NULL = bereken uit monthly + yearly_discount_percent'
  AFTER price_cents_per_month;

-- 3. gymies_system_settings: jaarlijkse korting + grace period
INSERT INTO gymies_system_settings (setting_key, setting_value) VALUES
  ('yearly_discount_percent', '15'),
  ('subscription_grace_days', '14')
ON DUPLICATE KEY UPDATE setting_key = setting_key;
