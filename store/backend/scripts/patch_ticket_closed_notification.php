#!/usr/bin/env php
<?php
/**
 * Patch GymiesAdminController::updateTicket om bij status 'resolved' een notificatie
 * te sturen naar de ticket-eigenaar.
 *
 * Gebruik: php patch_ticket_closed_notification.php [pad/naar/laravel]
 */

$base = $argv[1] ?? null;
if ($base) {
    if (is_dir($base)) {
        $controllerPath = rtrim($base, '/') . '/app/Http/Controllers/Gymies/GymiesAdminController.php';
    } else {
        $controllerPath = $base;
    }
} else {
    $controllerPath = __DIR__ . '/../../app/Http/Controllers/Gymies/GymiesAdminController.php';
}
$helperPath = dirname($controllerPath) . '/TicketClosedNotificationHelper.php';

if (!file_exists($controllerPath)) {
    fwrite(STDERR, "Controller niet gevonden: $controllerPath\n");
    exit(1);
}
if (!file_exists($helperPath)) {
    fwrite(STDERR, "TicketClosedNotificationHelper niet gevonden. Sync eerst de backend.\n");
    exit(1);
}

$content = file_get_contents($controllerPath);

if (strpos($content, 'TicketClosedNotificationHelper') !== false) {
    echo "Controller heeft al ticket-closed notificatie.\n";
    exit(0);
}

// 1. Voeg use-statement toe na de bestaande use-statements
$use = "use App\\Http\\Controllers\\Gymies\\TicketClosedNotificationHelper;\n";
if (preg_match('/^namespace\s+[\w\\\\]+;\s*\n\n/', $content, $m)) {
    $after = strlen($m[0]);
    $rest = substr($content, $after);
    if (!preg_match('/^use\s+/m', $rest)) {
        $content = substr($content, 0, $after) . $use . $rest;
    } else {
        $content = preg_replace(
            '/(\n)(use\s+[\w\\\\]+;\s*\n)/',
            '$1' . $use . '$2',
            $content,
            1
        );
    }
}
// Fallback: na eerste use
if (strpos($content, 'TicketClosedNotificationHelper') === false) {
    $content = preg_replace(
        '/(\nuse\s+[^;]+;\s*\n)/',
        '$1' . $use,
        $content,
        1
    );
}

// 2. Voeg notificatie-logica toe vóór "return response()->json(['ok' => true]);" in updateTicket
$insert = <<<'PHP'

        if ((string) $request->input('status') === 'resolved') {
            $userId = (int) ($t->user_id ?? $t->author_id ?? 0);
            if ($userId > 0) {
                TicketClosedNotificationHelper::notifyTicketOwner($id, $userId, 'App\Models\User');
            }
        }

PHP;

$search = "\$this->audit((int) \$admin->id, 'admin_ticket_updated', 'support_ticket', \$id, \$auditPayload);\n\n        return response()->json(['ok' => true]);";
if (strpos($content, $search) !== false) {
    $content = str_replace(
        $search,
        "\$this->audit((int) \$admin->id, 'admin_ticket_updated', 'support_ticket', \$id, \$auditPayload);" . $insert . "        return response()->json(['ok' => true]);",
        $content
    );
} else {
    fwrite(STDERR, "Kon juiste plek in updateTicket niet vinden (audit + return).\n");
    exit(1);
}

file_put_contents($controllerPath, $content);
echo "GymiesAdminController::updateTicket succesvol gepatcht met ticket-closed notificatie.\n";
