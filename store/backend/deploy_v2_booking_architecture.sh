#!/bin/bash
# ============================================================
# GYMIES — V2 Booking Architecture Deploy
# Deployt: migraties, services, middleware
# Compatibel met macOS bash 3.x (geen declare -A nodig)
# ============================================================
set -e

SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LARAVEL_PATH="/var/www/gymies"
LOCAL_BACKEND="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — V2 Booking Architecture Deploy             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Stap 1: Bestanden uploaden via tar ──
echo "  [1/4] Bestanden uploaden..."
cd "$LOCAL_BACKEND"

tar czf /tmp/gymies_v2_deploy.tar.gz \
  database/migrations/2025_04_27_000001_extend_trainer_profiles_v2_settings.php \
  database/migrations/2025_04_27_000002_create_gymies_idempotency_keys_table.php \
  database/migrations/2025_04_27_000003_create_gymies_cancellation_policies_table.php \
  database/migrations/2025_04_27_000004_create_gymies_recurring_bookings_table.php \
  database/migrations/2025_04_27_000005_create_gymies_waitlist_table.php \
  app/Services/SlotEngine.php \
  app/Services/CancellationPolicyService.php \
  app/Services/RecurringBookingService.php \
  app/Services/WaitlistService.php \
  app/Http/Middleware/GymiesIdempotencyMiddleware.php

scp -i "$SSH_KEY" /tmp/gymies_v2_deploy.tar.gz "$SSH_HOST:/tmp/"
echo "  ✓ Upload klaar"

# ── Stap 2: Installeren + migraties + cache in één SSH sessie ──
echo ""
echo "  [2/4] Installeren + migraties draaien..."

ssh -i "$SSH_KEY" "$SSH_HOST" bash -s "$LARAVEL_PATH" << 'REMOTE'
set -e
LP="$1"

echo "  Bestanden uitpakken..."
cd /tmp
tar xzf gymies_v2_deploy.tar.gz

# Directories aanmaken
sudo mkdir -p "$LP/app/Services"
sudo mkdir -p "$LP/app/Http/Middleware"
sudo mkdir -p "$LP/database/migrations"

# Kopiëren
for f in database/migrations/2025_04_27_*.php; do
  [ -f "$f" ] && sudo cp "$f" "$LP/$f" && echo "  ✓ $(basename $f)"
done
for f in app/Services/*.php; do
  [ -f "$f" ] && sudo cp "$f" "$LP/$f" && echo "  ✓ $(basename $f)"
done
for f in app/Http/Middleware/GymiesIdempotencyMiddleware.php; do
  [ -f "$f" ] && sudo cp "$f" "$LP/$f" && echo "  ✓ $(basename $f)"
done

# Eigenaarschap
sudo chown -R www-data:www-data "$LP/app/Services"
sudo chown -R www-data:www-data "$LP/app/Http/Middleware"
sudo chown -R www-data:www-data "$LP/database/migrations"

echo ""
echo "  Schema + migraties..."

cd "$LP"
sudo -u www-data php << 'PHP'
<?php
require_once '/var/www/gymies/vendor/autoload.php';
$app = require_once '/var/www/gymies/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

echo "  Schema check...\n";

// 1. Trainer profiles uitbreiden
$cols = [
    'timezone'              => fn($t) => $t->string('timezone', 50)->default('Europe/Amsterdam'),
    'session_duration_min'  => fn($t) => $t->unsignedSmallInteger('session_duration_min')->default(60),
    'buffer_minutes'        => fn($t) => $t->unsignedSmallInteger('buffer_minutes')->default(15),
    'max_sessions_per_day'  => fn($t) => $t->unsignedSmallInteger('max_sessions_per_day')->nullable(),
    'max_sessions_per_week' => fn($t) => $t->unsignedSmallInteger('max_sessions_per_week')->nullable(),
    'min_break_minutes'     => fn($t) => $t->unsignedSmallInteger('min_break_minutes')->default(15),
];
if (Schema::hasTable('gymies_trainer_profiles')) {
    foreach ($cols as $col => $cb) {
        if (!Schema::hasColumn('gymies_trainer_profiles', $col)) {
            Schema::table('gymies_trainer_profiles', $cb);
            echo "  ✓ trainer_profiles.{$col} toegevoegd\n";
        } else {
            echo "  · trainer_profiles.{$col} bestaat al\n";
        }
    }
}

// 2. Idempotency keys
if (!Schema::hasTable('gymies_idempotency_keys')) {
    Schema::create('gymies_idempotency_keys', function ($table) {
        $table->id();
        $table->string('idempotency_key', 64)->unique();
        $table->unsignedBigInteger('user_id')->index();
        $table->string('endpoint', 120);
        $table->string('method', 10)->default('POST');
        $table->unsignedSmallInteger('response_code');
        $table->json('response_body');
        $table->timestamp('created_at')->useCurrent();
        $table->timestamp('expires_at')->nullable()->index();
    });
    echo "  ✓ gymies_idempotency_keys aangemaakt\n";
} else {
    echo "  · gymies_idempotency_keys bestaat al\n";
}

// 3. Cancellation policies
if (!Schema::hasTable('gymies_cancellation_policies')) {
    Schema::create('gymies_cancellation_policies', function ($table) {
        $table->id();
        $table->unsignedBigInteger('trainer_user_id')->unique();
        $table->unsignedSmallInteger('free_cancel_hours')->default(24);
        $table->unsignedSmallInteger('late_cancel_fee_pct')->default(50);
        $table->unsignedSmallInteger('no_show_fee_pct')->default(100);
        $table->boolean('allow_reschedule')->default(true);
        $table->unsignedSmallInteger('reschedule_limit_hours')->default(4);
        $table->unsignedSmallInteger('max_free_cancels_per_month')->nullable();
        $table->string('custom_message', 500)->nullable();
        $table->timestamps();
    });
    echo "  ✓ gymies_cancellation_policies aangemaakt\n";
} else {
    echo "  · gymies_cancellation_policies bestaat al\n";
}

// 4. Recurring bookings
if (!Schema::hasTable('gymies_recurring_bookings')) {
    Schema::create('gymies_recurring_bookings', function ($table) {
        $table->id();
        $table->unsignedBigInteger('client_user_id')->index();
        $table->unsignedBigInteger('trainer_user_id')->index();
        $table->unsignedTinyInteger('day_of_week');
        $table->string('start_time', 5);
        $table->unsignedSmallInteger('duration_minutes')->default(60);
        $table->date('repeat_until')->nullable();
        $table->unsignedSmallInteger('repeat_every_weeks')->default(1);
        $table->unsignedBigInteger('package_id')->nullable();
        $table->string('status', 20)->default('active')->index();
        $table->date('generated_until')->nullable();
        $table->unsignedInteger('amount_cents')->default(0);
        $table->timestamps();
    });
    echo "  ✓ gymies_recurring_bookings aangemaakt\n";
} else {
    echo "  · gymies_recurring_bookings bestaat al\n";
}

// 5. Waitlist
if (!Schema::hasTable('gymies_waitlist')) {
    Schema::create('gymies_waitlist', function ($table) {
        $table->id();
        $table->unsignedBigInteger('client_user_id')->index();
        $table->unsignedBigInteger('trainer_user_id')->index();
        $table->date('desired_date');
        $table->string('desired_time', 5);
        $table->unsignedSmallInteger('desired_duration_minutes')->default(60);
        $table->unsignedSmallInteger('position')->default(1);
        $table->string('status', 20)->default('waiting')->index();
        $table->timestamp('offered_at')->nullable();
        $table->timestamp('expires_at')->nullable()->index();
        $table->unsignedBigInteger('released_booking_id')->nullable();
        $table->unsignedBigInteger('claimed_booking_id')->nullable();
        $table->timestamps();
    });
    echo "  ✓ gymies_waitlist aangemaakt\n";
} else {
    echo "  · gymies_waitlist bestaat al\n";
}

// ── Verificatie ──
echo "\n  ═══ VERIFICATIE ═══\n";
$tables = ['gymies_idempotency_keys', 'gymies_cancellation_policies', 'gymies_recurring_bookings', 'gymies_waitlist'];
foreach ($tables as $t) {
    $exists = Schema::hasTable($t) ? '✓' : '✗';
    echo "  {$exists} {$t}\n";
}

$profileCols = ['timezone', 'session_duration_min', 'buffer_minutes', 'max_sessions_per_day', 'max_sessions_per_week', 'min_break_minutes'];
echo "\n  Trainer profile kolommen:\n";
foreach ($profileCols as $c) {
    $has = Schema::hasColumn('gymies_trainer_profiles', $c) ? '✓' : '✗';
    echo "  {$has} {$c}\n";
}
PHP

echo ""
echo "  Cache rebuilden..."
sudo -u www-data php artisan route:clear 2>/dev/null && echo "  ✓ route:clear"
sudo -u www-data php artisan route:cache 2>/dev/null && echo "  ✓ route:cache"
sudo -u www-data php artisan config:clear 2>/dev/null && echo "  ✓ config:clear"

# Cleanup
rm -f /tmp/gymies_v2_deploy.tar.gz
rm -rf /tmp/database /tmp/app
REMOTE

# ── Lokale cleanup ──
echo ""
echo "  [3/4] Cleanup..."
rm -f /tmp/gymies_v2_deploy.tar.gz

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ V2 Booking Architecture gedeployd!                ║"
echo "║                                                      ║"
echo "║  Nieuwe tabellen:                                    ║"
echo "║  · gymies_idempotency_keys                           ║"
echo "║  · gymies_cancellation_policies                      ║"
echo "║  · gymies_recurring_bookings                         ║"
echo "║  · gymies_waitlist                                   ║"
echo "║                                                      ║"
echo "║  Nieuwe services:                                    ║"
echo "║  · SlotEngine                                        ║"
echo "║  · CancellationPolicyService                         ║"
echo "║  · RecurringBookingService                           ║"
echo "║  · WaitlistService                                   ║"
echo "║  · GymiesIdempotencyMiddleware                       ║"
echo "╚══════════════════════════════════════════════════════╝"
