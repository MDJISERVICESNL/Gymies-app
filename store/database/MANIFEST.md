# Database – Gymies SQL-bestanden (manifest)

Alle bestanden staan onder **`database/`** in de repo-root (niet in `store/` gekopieerd tenzij anders vermeld). Gebruik dit als checklist voor migrations/seeds.

## Aanmaak (basis)

| Bestand | Beschrijving |
|---------|--------------|
| `create_gymies_tables.sql` | Volledige create (vanaf nul). |
| `create_gymies_tables_if_not_exists.sql` | Idempotent aanmaak – handig voor nieuwe omgeving. |

## Alters / uitbreidingen (alfabetisch)

- `alter_gymies_add_klant_trainer_fields.sql`
- `alter_gymies_add_trainer_balance_cents_only.sql`
- `alter_gymies_admin_ip_add_62_163_72_25.sql`
- `alter_gymies_admin_password_reset.sql`
- `alter_gymies_admin_user_notes.sql`
- `alter_gymies_admin_werkbak.sql`
- `alter_gymies_all_additions.sql`
- `alter_gymies_booking_confirmation_note.sql`
- `alter_gymies_booking_reschedule_request.sql`
- `alter_gymies_booking_reschedule_symmetric.sql`
- `alter_gymies_broadcasts.sql`
- `alter_gymies_cancellation_policy.sql`
- `alter_gymies_client_dossier.sql`
- `alter_gymies_client_progress.sql`
- `alter_gymies_client_progress_simple.sql`
- `alter_gymies_control_tower.sql`
- `alter_gymies_direct_book.sql`
- `alter_gymies_disputes_resolution.sql`
- `alter_gymies_drop_legacy_wallet_payout.sql`
- `alter_gymies_email_verification.sql`
- `alter_gymies_future_tables.sql`
- `alter_gymies_group_sessions.sql`
- `alter_gymies_group_sessions_add_status.sql`
- `alter_gymies_group_sessions_add_status_key_only.sql`
- `alter_gymies_group_sessions_crowdfund.sql`
- `alter_gymies_group_sessions_waitlist_enabled.sql`
- `alter_gymies_gym_organisations.sql`
- `alter_gymies_incident_resolution.sql`
- `alter_gymies_master_spec_additions.sql`
- `alter_gymies_moderation.sql`
- `alter_gymies_mollie_payment_tables.sql`
- `alter_gymies_notification_read_at.sql`
- `alter_gymies_packages_admin.sql`
- `alter_gymies_packages_subscription_fields.sql`
- `alter_gymies_payout_settings.sql`
- `alter_gymies_promo_codes_trainer.sql`
- `alter_gymies_saas_model.sql`
- `alter_gymies_saas_plans_only.sql`
- `alter_gymies_saas_plans_seed.sql`
- `alter_gymies_saas_rest.sql`
- `alter_gymies_saas_subscriptions_fix.sql`
- `alter_gymies_search_demand.sql`
- `alter_gymies_stickiness_features.sql`
- `alter_gymies_support_ticket_contact.sql`
- `alter_gymies_ticket_close_reason.sql`
- `alter_gymies_trainer_media.sql`
- `alter_gymies_trainer_storefront.sql`
- `alter_gymies_users_add_register_columns.sql`
- `alter_gymies_users_newsletter.sql`
- `alter_gymies_womens_safety.sql`
- `deprecated_alter_gymies_wallet_and_refund.sql`

## Schema dumps

- `gymies_complete_schema.sql` – volledige dump Gymies-tabellen.
- `run_gymies_tables.sh` – run-script (server).

## Seeds

- `seed_gymies_admin_dummy.sql`
- `seed_gymies_dummy_trainers.sql`
- `seed_gymies_dummy_trainers_server.sql`

## Config op server

- Laravel `.env` – `DB_*` wijst naar MySQL/SQL Server waar deze tabellen leven.
- **Geen** echte credentials in `store/` – alleen in `credentials.env.example` (repo-root) als voorbeeld.
