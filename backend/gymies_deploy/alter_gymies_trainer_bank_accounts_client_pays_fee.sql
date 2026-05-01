-- Fee Switcher / "Eigen Baas": wie betaalt de servicekosten bovenop het uurtarief?
-- 1 = klant betaalt toeslag (bijv. €0,49 bovenop) — trainer ziet volledige uitbetaling = tarief.
-- 0 = trainer neemt het in marge — klant betaalt rond tarief, trainer ontvangt tarief minus fee.
-- Kolom ontbreekt op oude omgevingen → default gedrag blijft client_pays = 1.

ALTER TABLE gymies_trainer_bank_accounts
  ADD COLUMN client_pays_service_fee TINYINT(1) NOT NULL DEFAULT 1
  COMMENT '1=client pays fee on top, 0=trainer absorbs'
  AFTER notify_payout_failed;
