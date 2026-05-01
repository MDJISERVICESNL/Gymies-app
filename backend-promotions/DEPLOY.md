# Gymies Promotie-systeem Deploy Guide

## Stap-voor-stap deploy op je server

### 1. SSH naar je server
```bash
ssh amazonekey
cd /var/www/gymies
```

### 2. Backup database (ALTIJD EERST!)
```bash
php artisan tinker --execute="echo DB::connection()->getDatabaseName();"
mysqldump -u $(php artisan tinker --execute="echo config('database.connections.mysql.username');") -p$(php artisan tinker --execute="echo config('database.connections.mysql.password');") -h $(php artisan tinker --execute="echo config('database.connections.mysql.host');") gymies > ~/gymies_backup_$(date +%Y%m%d_%H%M%S).sql
```

### 3. Kopieer bestanden
Kopieer vanuit `backend-promotions/` naar de juiste locaties:

**Migrations → `database/migrations/`**
- `2026_04_20_create_promotions_table.php`
- `2026_04_20_create_trainer_promotions_table.php`
- `2026_04_20_add_dynamic_fields_to_plans_and_subscriptions.php`

**Models → `app/Models/`**
- `Promotion.php`
- `TrainerPromotion.php`

**Service → `app/Services/`**
- `PromotionService.php`

**Controller → `app/Http/Controllers/Api/`**
- `PromotionController.php`

**Command → `app/Console/Commands/`**
- `ExpirePromotionsCommand.php`

**Routes → toevoegen aan `routes/api.php`**

### 4. Draai migrations
```bash
php artisan migrate
```

### 5. Voeg routes toe aan routes/api.php
### 6. Test
```bash
php artisan tinker
```
