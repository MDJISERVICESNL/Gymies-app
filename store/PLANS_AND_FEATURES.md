# Gymies trainer-plannen (SaaS) – overzicht

## Plan-slugs (normalisatie)

| API / DB-waarde | Genormaliseerd | Opmerking |
|-----------------|----------------|-----------|
| `starter`, `basis` | `starter` | Default |
| `pro` | `pro` | |
| `studio`, `elite` | `studio` | Zelfde rechten als studio |

Bron: `gymies_trainer_profiles.subscription_plan` (backend) + `normalizedTrainerPlan()` in `trainer_plan.dart`.

## Feature-matrix (Dart – `PlanFeatures.forPlan`)

| Plan | Groepslessen | Team | Wachtlijst |
|------|--------------|------|------------|
| **starter** | nee | nee | nee |
| **pro** | ja | nee | nee |
| **studio** | ja | ja | ja |

## Backend – `GymiesPlanManager` (PHP)

Constanten:

- `FEATURE_GROUP_SESSIONS` – Pro + Studio
- `FEATURE_TEAM` – alleen Studio
- `FEATURE_INVOICE_BRANDED` – Pro + Studio

Methodes:

- `trainerPlanSlug($trainerUserId)` → `starter` | `pro` | `studio`
- `can($trainerUserId, $feature)` → bool
- `assertGroupSessions` / `assertTeam` → `allowed`, `message`, `upgrade_hint` (copy voor upsell-teksten in app)

## Dart helpers (`trainer_plan.dart`)

- `trainerCanAccessGroupSessions(user)` – Pro/Studio
- `trainerCanAccessTeam(user)` – Studio only
- `trainerCanEditPacks(user)` – zelfde als groepslessen (Starter lockt pakketten-CRUD)

## SQL gerelateerd aan plannen

- `database/alter_gymies_saas_plans_seed.sql`
- `database/alter_gymies_saas_plans_only.sql`
- `database/alter_gymies_saas_model.sql`
- `database/alter_gymies_saas_subscriptions_fix.sql`
- `database/alter_gymies_saas_rest.sql`

Zie `database/MANIFEST.md` voor volledige paden.

## Inspelen in een nieuwe app

- Toon alleen menu-items als `PlanFeatures.forUser(user)` true is.
- Toon upgrade-CTA met `upgrade_hint`-teksten uit API-responses waar de backend `assert*` gebruikt.
- Houd plan-slugs gelijk aan backend om geen drift te krijgen.
