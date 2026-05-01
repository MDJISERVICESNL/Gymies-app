-- Package/Subscription: admin kan sessies aanpassen en pakket bevriezen

ALTER TABLE gymies_packages
  ADD COLUMN sessions_used INT UNSIGNED NOT NULL DEFAULT 0 AFTER sessions_count,
  ADD COLUMN frozen_until DATE DEFAULT NULL COMMENT 'Bevroren tot datum (admin)' AFTER valid_days,
  ADD COLUMN frozen_reason VARCHAR(255) DEFAULT NULL AFTER frozen_until;
