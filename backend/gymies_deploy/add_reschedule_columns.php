<?php
/**
 * Add reschedule proposal columns to gymies_bookings.
 *
 * Run on server:
 *   cd /var/www/gymies && php artisan tinker < /tmp/add_reschedule_columns.php
 *
 * Or copy-paste into: php artisan tinker
 */

use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;
use Illuminate\Database\Schema\Blueprint;

$table = 'gymies_bookings';

// 1. proposed_scheduled_at
if (!Schema::hasColumn($table, 'proposed_scheduled_at')) {
    Schema::table($table, function (Blueprint $t) {
        $t->timestamp('proposed_scheduled_at')->nullable()->after('scheduled_at');
    });
    echo "✅ Added proposed_scheduled_at\n";
} else {
    echo "⏭️ proposed_scheduled_at already exists\n";
}

// 2. proposed_duration_minutes
if (!Schema::hasColumn($table, 'proposed_duration_minutes')) {
    Schema::table($table, function (Blueprint $t) {
        $t->unsignedSmallInteger('proposed_duration_minutes')->nullable()->after('proposed_scheduled_at');
    });
    echo "✅ Added proposed_duration_minutes\n";
} else {
    echo "⏭️ proposed_duration_minutes already exists\n";
}

// 3. proposed_by_user_id
if (!Schema::hasColumn($table, 'proposed_by_user_id')) {
    Schema::table($table, function (Blueprint $t) {
        $t->unsignedBigInteger('proposed_by_user_id')->nullable()->after('proposed_duration_minutes');
    });
    echo "✅ Added proposed_by_user_id\n";
} else {
    echo "⏭️ proposed_by_user_id already exists\n";
}

// 4. proposed_at
if (!Schema::hasColumn($table, 'proposed_at')) {
    Schema::table($table, function (Blueprint $t) {
        $t->timestamp('proposed_at')->nullable()->after('proposed_by_user_id');
    });
    echo "✅ Added proposed_at\n";
} else {
    echo "⏭️ proposed_at already exists\n";
}

// Verification
echo "\n=== Verification ===\n";
$cols = Schema::getColumnListing($table);
$needed = ['proposed_scheduled_at', 'proposed_duration_minutes', 'proposed_by_user_id', 'proposed_at'];
foreach ($needed as $c) {
    $exists = in_array($c, $cols);
    echo ($exists ? '✅' : '❌') . " $c: " . ($exists ? 'EXISTS' : 'MISSING') . "\n";
}
