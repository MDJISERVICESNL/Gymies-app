# Gymies – Migratie-strategie

## Overzicht

Gymies gebruikt **SQL alter-bestanden** in plaats van Laravel migrations. De volgorde en afhankelijkheden zijn hier gedocumenteerd.

## Basis

1. **create_gymies_tables_if_not_exists.sql** – Basis-schema (users, bookings, packages, etc.)
2. **admin_dashboard_schema.sql** – Admin/Control Tower tabellen

## Uitvoeren op server

```bash
# Via deploy script (toont commando's)
./deploy.sh migrate

# Of direct (na upload_backend)
cd $REMOTE_LARAVEL
sudo -u www-data php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/<bestand>.sql
```

## Volgorde alters (aanbevolen)

| Volgorde | Bestand | Doel |
|----------|---------|------|
| 1 | alter_gymies_spoed_inval.sql | Spoed Inval basis |
| 2 | alter_gymies_spoed_inval_status_extended.sql | Status-uitbreiding |
| 3 | alter_gymies_spoed_inval_standby.sql | Stand-by modus |
| 4 | alter_gymies_spoed_inval_extras.sql | Extra velden |
| 5 | alter_gymies_buddy_search_prefs.sql | Buddy Match |
| 6 | alter_gymies_starter_unlimited_sessions.sql | Starter sessies |
| 7 | alter_gymies_subscription_change_plan.sql | Abonnementen |
| 8 | alter_gymies_upsell_settings.sql | Upsell |
| 9 | alter_gymies_trainer_trainer_chat.sql | Trainer-trainer chat |
| 10 | alter_gym_locations.sql | Ruimtes |
| 11 | alter_gym_location_blocks.sql | Blokkades |
| 12 | alter_gym_teams.sql | Teams |
| 13 | alter_gym_team_members.sql | Teamleden |
| 14 | alter_gym_invites.sql | Uitnodigingen |
| 15 | alter_gym_group_sessions_bookings_location.sql | Groepsles locatie |
| 16 | alter_gymies_organisations_extra_settings.sql | Org-instellingen |
| 17 | **alter_gymies_performance_indexes.sql** | Performance indexes |

## Rollback

Er is geen automatische rollback. Bij problemen:

- **Indexes:** `ALTER TABLE t DROP INDEX index_name;`
- **Kolommen:** handmatig `ALTER TABLE t DROP COLUMN c;`
- **Tabellen:** alleen bij nieuwe feature-tabellen; bestaande data niet droppen

## Duplicate key / al uitgevoerd

Bij "Duplicate key name" of "Duplicate column name" bestaat de wijziging al – negeer de fout. De runner gebruikt `|| true` zodat het script doorgaat.

## Performance indexes (alter_gymies_performance_indexes.sql)

Toegevoegd voor P1-verbeterpunten:

- `gymies_bookings(trainer_user_id, scheduled_at, status)` – agenda, rapportages
- `gymies_bookings(client_user_id, scheduled_at)` – mijn boekingen
- `gymies_bookings(package_id, client_user_id, status)` – low-credit cron
- `gymies_messages(conversation_id, created_at)` – chat chronologisch
- `gymies_notification_queue(user_id, event_type, created_at)` – dedup upsell
