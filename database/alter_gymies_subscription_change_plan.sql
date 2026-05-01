-- Planwijziging: wijziging gaat pas in bij volgende factuurdatum.
-- pending_plan_id wordt gezet bij change-plan; webhook past het toe na betaalde betaling.
-- Draai eenmalig. Bij "Duplicate column" of "Duplicate key" is de migratie al uitgevoerd.
ALTER TABLE gymies_subscriptions
  ADD COLUMN pending_plan_id BIGINT UNSIGNED NULL DEFAULT NULL;
ALTER TABLE gymies_subscriptions
  ADD CONSTRAINT gymies_subscriptions_pending_plan_fk
    FOREIGN KEY (pending_plan_id) REFERENCES gymies_plans (id) ON DELETE SET NULL;
