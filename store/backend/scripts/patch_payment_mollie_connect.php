#!/usr/bin/env php
<?php
/**
 * Patch GymiesPaymentController om Mollie Connect (OAuth token) te gebruiken voor sessiebetalingen.
 * Betalingen gaan dan naar het Mollie-account van de trainer.
 *
 * Gebruik: php patch_payment_mollie_connect.php [pad/naar/laravel]
 */

$base = $argv[1] ?? null;
if ($base) {
    $laravelPath = rtrim($base, '/');
    if (!is_dir($laravelPath)) {
        fwrite(STDERR, "Pad is geen directory: $laravelPath\n");
        exit(1);
    }
} else {
    $laravelPath = dirname(__DIR__, 2);
}

$controllerPath = $laravelPath . '/app/Http/Controllers/Gymies/GymiesPaymentController.php';
$traitPath = dirname($controllerPath) . '/MollieConnectPaymentTrait.php';

if (!file_exists($controllerPath)) {
    fwrite(STDERR, "Controller niet gevonden: $controllerPath\n");
    exit(1);
}
if (!file_exists($traitPath)) {
    fwrite(STDERR, "MollieConnectPaymentTrait niet gevonden. Sync eerst de backend.\n");
    exit(1);
}

$content = file_get_contents($controllerPath);
$blockReplaced = false;

// Stap 1: Trait + startPayment-block (alleen als nog niet gedaan)
if (strpos($content, 'createMolliePaymentForTrainer') === false) {
    // 1a. Voeg use MollieConnectPaymentTrait toe
    $content = preg_replace(
        '/(final\s+class\s+GymiesPaymentController\s+extends\s+Controller\s*\{)/',
        '$1' . "\n    use MollieConnectPaymentTrait;\n",
        $content,
        1
    );
    if (strpos($content, 'MollieConnectPaymentTrait') === false) {
        fwrite(STDERR, "Kon trait niet toevoegen (class pattern niet gevonden).\n");
        exit(1);
    }

    // 1b. Vervang Mollie-block in startPayment
    $oldBlock = <<<'PHP'
        if ($paymentMethod === self::PAYMENT_METHOD_MOLLIE) {
            $trainerMollieProfileId = null;
            if (Schema::hasColumn('gymies_trainer_profiles', 'mollie_profile_id')) {
                $trainerMollieProfileId = DB::table('gymies_trainer_profiles')
                    ->where('user_id', (int) $booking->trainer_user_id)
                    ->value('mollie_profile_id');
            }

            $apiKey = $this->getMollieApiKey();
            if ($apiKey !== '') {
                $webhookUrl = rtrim($request->root(), '/') . '/api/gymies/webhooks/mollie';
                $createResult = $this->createMolliePayment($apiKey, $amountCents, $bookingId, $returnUrl, $webhookUrl, $trainerMollieProfileId);
                if ($createResult !== null) {
                    $providerTransactionId = (string) $createResult['id'];
                    $paymentUrl = (string) $createResult['checkout_url'];
                } else {
                    $paymentUrl = $this->createStubRedirectUrl($returnUrl, $providerTransactionId);
                }
            } else {
                $paymentUrl = $this->createStubRedirectUrl($returnUrl, $providerTransactionId);
            }
        }
PHP;
    $newBlock = <<<'PHP'
        if ($paymentMethod === self::PAYMENT_METHOD_MOLLIE) {
            $profile = DB::table('gymies_trainer_profiles')->where('user_id', (int) $booking->trainer_user_id)->first();
            $encryptedToken = $profile->mollie_access_token ?? null;
            if (empty($encryptedToken)) {
                return response()->json([
                    'message' => 'Deze trainer heeft nog geen Mollie-account gekoppeld. Vraag de trainer om Mollie Connect te doen in de app.',
                ], 422);
            }
            try {
                $accessToken = decrypt($encryptedToken);
            } catch (\Throwable $e) {
                return response()->json(['message' => 'Kon Mollie-token niet laden. Laat de trainer Mollie opnieuw koppelen.'], 500);
            }
            $bookingArr = [
                'id' => $booking->id,
                'amount_cents' => $amountCents,
                'trainer_user_id' => $booking->trainer_user_id,
            ];
            try {
                $result = $this->createMolliePaymentForTrainer($bookingArr, $accessToken);
                $this->storeBookingMolliePayment((string) $bookingId, $result['payment_id'], (int) $booking->trainer_user_id);
                $providerTransactionId = $result['payment_id'];
                $paymentUrl = $result['payment_url'];
            } catch (\InvalidArgumentException $e) {
                return response()->json(['message' => $e->getMessage()], 422);
            } catch (\RuntimeException $e) {
                return response()->json(['message' => $e->getMessage()], 400);
            }
        }
PHP;
    $content = str_replace($oldBlock, $newBlock, $content, $count);
    if ($count !== 1) {
        fwrite(STDERR, "Kon Mollie-block niet vervangen (match: $count). Pas handmatig aan.\n");
        exit(1);
    }
    $blockReplaced = true;
}

// Stap 2: Webhook – probeer eerst Connect (trainer-token), anders platform-key
$webhookOld = '        $mollieStatus = $this->fetchMolliePaymentStatus($paymentId);';
$webhookNew = '        $mollieStatus = $this->fetchMolliePaymentStatusForConnect($paymentId) ?? $this->fetchMolliePaymentStatus($paymentId);';
if (strpos($content, $webhookNew) === false && strpos($content, $webhookOld) !== false) {
    $content = str_replace($webhookOld, $webhookNew, $content);
}

file_put_contents($controllerPath, $content);
if ($blockReplaced) {
    echo "GymiesPaymentController succesvol gepatcht (Mollie Connect).\n";
} elseif (strpos($content, $webhookNew) !== false) {
    echo "Webhook-update toegepast (Connect payments).\n";
} else {
    echo "Geen wijzigingen nodig.\n";
}
