ALTER TABLE gymies_users
  ADD COLUMN trainer_balance_cents INT NOT NULL DEFAULT 0
  COMMENT 'Trainer-saldo in centen. Negatief = boete (bv. -2500 = €25). Wordt verrekend bij volgende uitbetaling.';
