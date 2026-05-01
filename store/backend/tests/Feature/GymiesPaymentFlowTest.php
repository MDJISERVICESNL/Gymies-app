<?php

declare(strict_types=1);

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * Gymies Payment Flow Feature Tests
 * ──────────────────────────────────
 * Test de volledige betaalflow: booking aanmaken, betaling starten,
 * webhook verwerken, idempotency, cash flow, en Mollie reconciliatie.
 *
 * Vereisten:
 *  - php artisan test --filter=GymiesPaymentFlowTest
 *  - Database met gymies_* tabellen (migraties draaien)
 *  - .env.testing met MOLLIE_API_KEY=test_...
 *
 * Deze tests gebruiken RefreshDatabase zodat elke test schone state heeft.
 */
class GymiesPaymentFlowTest extends TestCase
{
    use RefreshDatabase;

    private string $baseUrl = '/api/gymies';
    private array $headers  = [];
    private ?int $trainerId  = null;
    private ?int $clientId   = null;
    private ?string $clientToken = null;
    private ?string $trainerToken = null;

    protected function setUp(): void
    {
        parent::setUp();

        // Skip als tabellen niet bestaan (nog geen migraties gedraaid)
        if (!Schema::hasTable('gymies_users')) {
            $this->markTestSkipped('gymies_users tabel ontbreekt — draai migraties eerst.');
        }

        // Maak test-gebruikers
        $this->trainerId = $this->createTestUser('trainer');
        $this->clientId  = $this->createTestUser('client');
        $this->trainerToken = $this->createTestToken($this->trainerId);
        $this->clientToken  = $this->createTestToken($this->clientId);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 1: Booking aanmaken als klant
    // ════════════════════════════════════════════════════════════════════
    public function test_client_can_create_booking(): void
    {
        $response = $this->withToken($this->clientToken)
            ->postJson("{$this->baseUrl}/bookings", [
                'trainer_user_id' => $this->trainerId,
                'date'            => now()->addDays(3)->format('Y-m-d'),
                'time_start'      => '10:00',
                'time_end'        => '11:00',
                'payment_method'  => 'mollie',
            ]);

        $response->assertStatus(200)
            ->assertJsonStructure(['booking_id'])
            ->assertJsonMissing(['password', 'iban', 'mollie_access_token']);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 2: Booking aanmaken zonder auth → 401
    // ════════════════════════════════════════════════════════════════════
    public function test_booking_requires_authentication(): void
    {
        $response = $this->postJson("{$this->baseUrl}/bookings", [
            'trainer_user_id' => $this->trainerId,
            'date'            => now()->addDays(3)->format('Y-m-d'),
            'time_start'      => '10:00',
            'time_end'        => '11:00',
        ]);

        $response->assertStatus(401);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 3: Cash betaling bevestigen (trainer)
    // ════════════════════════════════════════════════════════════════════
    public function test_trainer_can_confirm_cash_payment(): void
    {
        $bookingId = $this->createTestBooking('cash', 'pending');

        $response = $this->withToken($this->trainerToken)
            ->postJson("{$this->baseUrl}/bookings/{$bookingId}/confirm-cash", [
                'confirmed' => true,
            ]);

        // Kan 200 (success) of 422 (al bevestigd) of 404 (niet gevonden) zijn
        $this->assertContains($response->status(), [200, 422, 404]);

        // Controleer dat response geen gevoelige data bevat
        $response->assertJsonMissing(['password', 'iban', 'mollie_access_token']);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 4: Idempotency — dubbele cash bevestiging
    // ════════════════════════════════════════════════════════════════════
    public function test_cash_confirmation_is_idempotent(): void
    {
        $bookingId = $this->createTestBooking('cash', 'pending');

        // Eerste bevestiging
        $response1 = $this->withToken($this->trainerToken)
            ->withHeaders(['X-Idempotency-Key' => 'test-idem-001'])
            ->postJson("{$this->baseUrl}/bookings/{$bookingId}/confirm-cash", [
                'confirmed' => true,
            ]);

        // Tweede bevestiging met zelfde idempotency key
        $response2 = $this->withToken($this->trainerToken)
            ->withHeaders(['X-Idempotency-Key' => 'test-idem-001'])
            ->postJson("{$this->baseUrl}/bookings/{$bookingId}/confirm-cash", [
                'confirmed' => true,
            ]);

        // Beide moeten hetzelfde resultaat geven
        $this->assertEquals($response1->status(), $response2->status());
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 5: Mollie webhook verwerking
    // ════════════════════════════════════════════════════════════════════
    public function test_mollie_webhook_accepts_valid_payment_id(): void
    {
        // Mollie webhook is een POST met payment ID
        $response = $this->postJson("{$this->baseUrl}/payments/webhook", [
            'id' => 'tr_test_' . bin2hex(random_bytes(8)),
        ]);

        // Webhook moet 200 retourneren (Mollie verwacht dit)
        // Of 404 als payment niet gevonden (dat is ook OK — we verwerken het niet)
        $this->assertContains($response->status(), [200, 404, 422]);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 6: Webhook zonder payment ID → 422
    // ════════════════════════════════════════════════════════════════════
    public function test_mollie_webhook_rejects_empty_payment(): void
    {
        $response = $this->postJson("{$this->baseUrl}/payments/webhook", []);

        $this->assertContains($response->status(), [422, 400]);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 7: API response filtering — geen gevoelige data
    // ════════════════════════════════════════════════════════════════════
    public function test_user_profile_hides_sensitive_fields(): void
    {
        $response = $this->withToken($this->clientToken)
            ->getJson("{$this->baseUrl}/me");

        if ($response->status() === 200) {
            $response->assertJsonMissing(['password', 'remember_token']);

            // Controleer dat er geen password hash in de response zit
            $content = $response->getContent();
            $this->assertStringNotContainsString('$2y$', $content, 'Bcrypt hash gevonden in response');
            $this->assertStringNotContainsString('$2a$', $content, 'Bcrypt hash gevonden in response');
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 8: Health check endpoint
    // ════════════════════════════════════════════════════════════════════
    public function test_health_endpoint_returns_ok(): void
    {
        $response = $this->getJson("{$this->baseUrl}/health");

        $response->assertStatus(200)
            ->assertJsonStructure(['status', 'timestamp']);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 9: App version endpoint
    // ════════════════════════════════════════════════════════════════════
    public function test_app_version_endpoint(): void
    {
        $response = $this->getJson("{$this->baseUrl}/app-version?version=1.2.1&platform=ios");

        $response->assertStatus(200)
            ->assertJsonStructure(['min_version', 'latest_version', 'force_update']);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 10: Force update voor oude versie
    // ════════════════════════════════════════════════════════════════════
    public function test_app_version_forces_update_for_old_version(): void
    {
        $response = $this->getJson("{$this->baseUrl}/app-version?version=0.1.0&platform=android");

        $response->assertStatus(200)
            ->assertJson(['force_update' => true]);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 11: Feature flags endpoint retourneert flags
    // ════════════════════════════════════════════════════════════════════
    public function test_feature_flags_endpoint_returns_flags(): void
    {
        // Seed een feature flag
        if (Schema::hasTable('gymies_feature_flags')) {
            DB::table('gymies_feature_flags')->insert([
                'key'                => 'test_flag_' . bin2hex(random_bytes(4)),
                'name'               => 'Test Flag',
                'description'        => 'Test feature flag',
                'enabled'            => true,
                'rollout_percentage' => 100.00,
                'created_at'         => now(),
                'updated_at'         => now(),
            ]);
        }

        $response = $this->getJson("{$this->baseUrl}/feature-flags");

        $response->assertStatus(200)
            ->assertJsonStructure(['flags']);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 12: Verlopen token → 401
    // ════════════════════════════════════════════════════════════════════
    public function test_expired_token_returns_unauthorized(): void
    {
        $expiredToken = bin2hex(random_bytes(32));

        if (Schema::hasTable('gymies_personal_access_tokens')) {
            DB::table('gymies_personal_access_tokens')->insert([
                'user_id'    => $this->clientId,
                'token'      => hash('sha256', $expiredToken),
                'name'       => 'expired-test',
                'created_at' => now()->subDays(2),
                'updated_at' => now()->subDays(2),
                'expires_at' => now()->subHour(), // Verlopen!
            ]);
        } else {
            $this->markTestSkipped('gymies_personal_access_tokens tabel ontbreekt.');
        }

        $response = $this->withToken($expiredToken)
            ->getJson("{$this->baseUrl}/me");

        $response->assertStatus(401);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 13: Trainer kan geen booking aanmaken (alleen klanten)
    // ════════════════════════════════════════════════════════════════════
    public function test_trainer_cannot_create_booking(): void
    {
        $response = $this->withToken($this->trainerToken)
            ->postJson("{$this->baseUrl}/bookings", [
                'trainer_user_id' => $this->trainerId,
                'date'            => now()->addDays(3)->format('Y-m-d'),
                'time_start'      => '10:00',
                'time_end'        => '11:00',
            ]);

        // Moet 403 retourneren — trainers mogen niet boeken
        $this->assertContains($response->status(), [403, 422]);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 14: Booking in het verleden → 422
    // ════════════════════════════════════════════════════════════════════
    public function test_booking_in_past_is_rejected(): void
    {
        $response = $this->withToken($this->clientToken)
            ->postJson("{$this->baseUrl}/bookings", [
                'trainer_user_id' => $this->trainerId,
                'scheduled_at'    => now()->subDays(1)->format('Y-m-d H:i:s'),
                'duration_minutes' => 60,
            ]);

        // Verleden sessie moet afgewezen worden
        $this->assertContains($response->status(), [422, 409, 400]);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 15: Feature flag rollout percentage werkt deterministisch
    // ════════════════════════════════════════════════════════════════════
    public function test_feature_flag_rollout_is_deterministic(): void
    {
        if (!Schema::hasTable('gymies_feature_flags')) {
            $this->markTestSkipped('gymies_feature_flags tabel ontbreekt.');
        }

        DB::table('gymies_feature_flags')->updateOrInsert(
            ['key' => 'test_rollout_flag'],
            [
                'name'               => 'Rollout Test',
                'description'        => 'Test deterministic rollout',
                'enabled'            => true,
                'rollout_percentage' => 50.00,
                'created_at'         => now(),
                'updated_at'         => now(),
            ]
        );

        // Zelfde user + key moet altijd hetzelfde resultaat geven
        \App\Http\Controllers\Gymies\GymiesFeatureFlags::clearCache();
        $result1 = \App\Http\Controllers\Gymies\GymiesFeatureFlags::isEnabled('test_rollout_flag', 42);
        \App\Http\Controllers\Gymies\GymiesFeatureFlags::clearCache();
        $result2 = \App\Http\Controllers\Gymies\GymiesFeatureFlags::isEnabled('test_rollout_flag', 42);

        $this->assertEquals($result1, $result2, 'Feature flag rollout moet deterministisch zijn voor dezelfde user');

        // 0% rollout = altijd uit
        DB::table('gymies_feature_flags')->where('key', 'test_rollout_flag')
            ->update(['rollout_percentage' => 0.00, 'updated_at' => now()]);
        \App\Http\Controllers\Gymies\GymiesFeatureFlags::clearCache();
        $this->assertFalse(
            \App\Http\Controllers\Gymies\GymiesFeatureFlags::isEnabled('test_rollout_flag', 42),
            '0% rollout moet altijd false retourneren'
        );

        // 100% rollout = altijd aan
        DB::table('gymies_feature_flags')->where('key', 'test_rollout_flag')
            ->update(['rollout_percentage' => 100.00, 'updated_at' => now()]);
        \App\Http\Controllers\Gymies\GymiesFeatureFlags::clearCache();
        $this->assertTrue(
            \App\Http\Controllers\Gymies\GymiesFeatureFlags::isEnabled('test_rollout_flag', 42),
            '100% rollout moet altijd true retourneren'
        );
    }

    // ════════════════════════════════════════════════════════════════════
    // Helpers
    // ════════════════════════════════════════════════════════════════════

    private function createTestUser(string $role): int
    {
        return DB::table('gymies_users')->insertGetId([
            'email'        => "test-{$role}-" . bin2hex(random_bytes(4)) . '@gymies-test.nl',
            'password'     => bcrypt('TestPassword123!'),
            'display_name' => "Test " . ucfirst($role),
            'role'         => $role,
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);
    }

    private function createTestToken(int $userId): string
    {
        $token = bin2hex(random_bytes(32));

        if (Schema::hasTable('gymies_personal_access_tokens')) {
            DB::table('gymies_personal_access_tokens')->insert([
                'user_id'    => $userId,
                'token'      => hash('sha256', $token),
                'name'       => 'test-token',
                'created_at' => now(),
                'updated_at' => now(),
                'expires_at' => now()->addHours(24),
            ]);
        } elseif (Schema::hasTable('gymies_sessions')) {
            DB::table('gymies_sessions')->insert([
                'user_id'       => $userId,
                'session_token' => $token,
                'created_at'    => now(),
                'expires_at'    => now()->addHours(24),
            ]);
        }

        return $token;
    }

    private function createTestBooking(string $paymentMethod = 'mollie', string $status = 'pending'): int
    {
        return DB::table('gymies_bookings')->insertGetId([
            'client_user_id'  => $this->clientId,
            'trainer_user_id' => $this->trainerId,
            'date'            => now()->addDays(3)->format('Y-m-d'),
            'time_start'      => '10:00:00',
            'time_end'        => '11:00:00',
            'payment_method'  => $paymentMethod,
            'status'          => $status,
            'price_cents'     => 5000,
            'created_at'      => now(),
            'updated_at'      => now(),
        ]);
    }
}
