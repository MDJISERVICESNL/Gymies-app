INSERT IGNORE INTO gymies_plans (name, slug, price_cents_per_month, description, max_sessions_per_month, max_trainer_accounts, has_invoicing, has_crm, has_womens_choice, is_active) VALUES
  ('Gymies Starter', 'starter', 2995, 'Alles om te kunnen starten.', 30, 1, 0, 0, 1, 1),
  ('Gymies Pro', 'pro', 5995, 'Onbeperkt + facturatie + CRM.', NULL, 1, 1, 1, 1, 1),
  ('Gymies Studio', 'studio', 9995, 'Meerdere trainers.', NULL, 5, 1, 1, 1, 1);
