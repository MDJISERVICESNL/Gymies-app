-- Starter: onbeperkte sessies per maand (was 30).
-- NULL = unlimited. Draai na alter_gymies_saas_model.sql.

UPDATE gymies_plans SET max_sessions_per_month = NULL WHERE slug = 'starter';
