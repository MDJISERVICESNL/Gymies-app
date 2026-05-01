#!/bin/bash
cd /var/www/gymies
php artisan tinker --execute='
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

$cols = Schema::getColumnListing("gymies_support_tickets");
echo "Kolommen: " . implode(", ", $cols) . "\n\n";

$tickets = DB::table("gymies_support_tickets")->orderByDesc("created_at")->limit(10)->get();
echo "Tickets: " . $tickets->count() . "\n";
foreach ($tickets as $t) {
    $cat = $t->category ?? "-";
    $status = $t->status ?? "-";
    $subj = mb_substr($t->subject ?? "", 0, 50);
    echo "  #{$t->id} | user:{$t->user_id} | cat:{$cat} | status:{$status} | {$subj}\n";
}
'
