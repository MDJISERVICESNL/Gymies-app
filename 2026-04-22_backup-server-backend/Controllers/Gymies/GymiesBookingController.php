<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Http\Requests\GymiesDirectBookingRequest;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies API: boekingen ophalen en aanmaken.
 * Tabel: gymies_bookings.
 */
final class GymiesBookingController extends Controller
{
    private const ALLOWED_DURATIONS = [45, 60, 90, 120];
    private const LEAD_TIME_MINUTES = 120;
    private const MAX_BOOKING_DAYS_AHEAD = 180;
    /** Direct Boeken: slot 10 min gereserveerd tijdens betaling. */
    private const RESERVED_LOCK_MINUTES = 10;
    /** Standaard lead time (min) als trainer geen profiel-instelling heeft (4 uur). */
    private const DEFAULT_LEAD_TIME_MINUTES = 240;

    /** Platform annuleringsbeleid (zie Cursor assets/annuleringsbeleid-gymies.md). */
    private const CANCELLATION_HOURS_FULL_CHOICE = 48;  // >48u: keuze bank of credits
    private const CANCELLATION_HOURS_CREDITS_ONLY = 24; // 24–48u: alleen credits
    private const TRAINER_PENALTY_CENTS = 2500;        // €25 boete bij trainer annulering <24u of trainer no-show
    /** Bedenktijd: binnen 15 min na boeken altijd 100% gratis annuleerbaar (bank, geen fee). */
    private const GRACE_PERIOD_MINUTES = 15;

    public function index(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => []]);
        }

        $userId = $user->id;
        $isTrainer = $user->role === 'trainer';
        $hasOrganisationId = DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'organisation_id');
        $hasPayoutRoute = DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'payout_route');

        $select = [
            'b.id',
            'b.client_user_id',
            'b.trainer_user_id',
            'b.scheduled_at',
            'b.duration_minutes',
            'b.status',
            'b.amount_cents',
            'b.paid_at',
            'trainer.display_name as trainer_name',
            'client.display_name as client_name',
        ];
        if ($hasOrganisationId) {
            $select[] = 'b.organisation_id';
        }
        if ($hasPayoutRoute) {
            $select[] = 'b.payout_route';
        }
        if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'location_type')) {
            $select[] = 'b.location_type';
            $select[] = 'b.location_notes';
        }
        if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'confirmation_note')) {
            $select[] = 'b.confirmation_note';
        }
        if (Schema::hasColumn('gymies_bookings', 'proposed_scheduled_at')) {
            $select[] = 'b.proposed_scheduled_at';
            $select[] = 'b.proposed_duration_minutes';
        }
        if (Schema::hasColumn('gymies_bookings', 'proposed_by_user_id')) {
            $select[] = 'b.proposed_by_user_id';
        }
        if (Schema::hasColumn('gymies_bookings', 'proposed_at')) {
            $select[] = 'b.proposed_at';
        }
        $hasPackageId = Schema::hasColumn('gymies_bookings', 'package_id');
        if ($hasPackageId) {
            $select[] = 'b.package_id';
            $select[] = 'b.sessions_remaining';
        }
        if (Schema::hasColumn('gymies_bookings', 'check_in_at')) {
            $select[] = 'b.check_in_at';
        }
        if (Schema::hasColumn('gymies_bookings', 'payment_method')) {
            $select[] = 'b.payment_method';
        }
        if (Schema::hasColumn('gymies_bookings', 'spoed_inval_original_trainer_id')) {
            $select[] = 'b.spoed_inval_original_trainer_id';
        }
        if (Schema::hasColumn('gymies_bookings', 'gym_location_id')) {
            $select[] = 'b.gym_location_id';
        }

        $query = DB::table('gymies_bookings as b')
            ->join('gymies_users as trainer', 'b.trainer_user_id', '=', 'trainer.id')
            ->join('gymies_users as client', 'b.client_user_id', '=', 'client.id');
        if ($hasPackageId && Schema::hasTable('gymies_packages')) {
            $query->leftJoin('gymies_packages as pkg', 'b.package_id', '=', 'pkg.id');
            $select[] = 'pkg.name as package_name';
        }
        if (Schema::hasColumn('gymies_bookings', 'gym_location_id') && Schema::hasTable('gymies_gym_locations')) {
            $query->leftJoin('gymies_gym_locations as gl', 'b.gym_location_id', '=', 'gl.id');
            $select[] = 'gl.name as gym_location_name';
        }
        $query->select(...$select);

        if ($isTrainer) {
            // Trainer ziet zowel eigen sessies (als trainer) als sessies waar hij/zij klant is
            $query->where(function ($q) use ($userId) {
                $q->where('b.trainer_user_id', $userId)
                    ->orWhere('b.client_user_id', $userId);
            });
        } else {
            $query->where('b.client_user_id', $userId);
        }

        $rows = $query->orderBy('b.scheduled_at', 'desc')->get();

        foreach ($rows as $r) {
            if (property_exists($r, 'proposed_scheduled_at') && $r->proposed_scheduled_at !== null
                && property_exists($r, 'proposed_at') && $r->proposed_at !== null) {
                $deadline = Carbon::parse($r->proposed_at)->addHours(24);
                if (now()->greaterThan($deadline)) {
                    $this->maybeExpireRescheduleProposal($r);
                }
            }
        }
        $rows = $query->orderBy('b.scheduled_at', 'desc')->get();

        $reviewedBookingIds = [];
        if (Schema::hasTable('gymies_reviews')) {
            $completedIds = $rows->where('status', 'completed')->pluck('id')->map(fn ($id) => (int) $id)->all();
            if (!empty($completedIds)) {
                $reviewedBookingIds = DB::table('gymies_reviews')->whereIn('booking_id', $completedIds)->pluck('booking_id')->map(fn ($id) => (int) $id)->all();
            }
        }

        $data = $rows->map(function ($r) use ($isTrainer, $reviewedBookingIds) {
            $item = [
                'id' => (string) $r->id,
                'client_user_id' => (string) $r->client_user_id,
                'trainer_user_id' => (string) $r->trainer_user_id,
                'trainer_name' => $r->trainer_name ?? 'Trainer',
                'client_name' => $r->client_name ?? 'Klant',
                'scheduled_at' => $r->scheduled_at,
                'duration_minutes' => (int) $r->duration_minutes,
                'status' => $r->status,
                'amount_cents' => $r->amount_cents ? (int) $r->amount_cents : null,
                'paid_at' => $r->paid_at,
                'organisation_id' => property_exists($r, 'organisation_id') && $r->organisation_id ? (string) $r->organisation_id : null,
                'payout_route' => property_exists($r, 'payout_route') ? ($r->payout_route ?? 'direct_trainer') : 'direct_trainer',
            ];
            if (property_exists($r, 'location_type')) {
                $item['location_type'] = $r->location_type ? (string) $r->location_type : null;
                $item['location_notes'] = $r->location_notes ? (string) $r->location_notes : null;
            }
            if (property_exists($r, 'gym_location_id') && $r->gym_location_id) {
                $item['gym_location_id'] = (string) $r->gym_location_id;
                $item['gym_location_name'] = property_exists($r, 'gym_location_name') && $r->gym_location_name ? (string) $r->gym_location_name : null;
            }
            if (property_exists($r, 'confirmation_note')) {
                $item['confirmation_note'] = $r->confirmation_note ? (string) $r->confirmation_note : null;
            }
            if ($r->status === 'completed') {
                $item['has_review'] = in_array((int) $r->id, $reviewedBookingIds, true);
            }
            if (property_exists($r, 'proposed_scheduled_at') && $r->proposed_scheduled_at !== null) {
                $item['proposed_scheduled_at'] = $r->proposed_scheduled_at;
                $item['proposed_duration_minutes'] = $r->proposed_duration_minutes !== null ? (int) $r->proposed_duration_minutes : null;
                if (property_exists($r, 'proposed_by_user_id')) {
                    $item['proposed_by_user_id'] = $r->proposed_by_user_id ? (string) $r->proposed_by_user_id : null;
                }
                if (property_exists($r, 'proposed_at')) {
                    $item['proposed_at'] = $r->proposed_at;
                    $deadline = $r->proposed_at ? Carbon::parse($r->proposed_at)->addHours(24) : null;
                    $item['proposed_response_deadline'] = $deadline?->toIso8601String();
                    $item['proposal_expired'] = $deadline && now()->greaterThan($deadline);
                }
            }
            if (property_exists($r, 'check_in_at') && $r->check_in_at !== null) {
                $item['check_in_at'] = $r->check_in_at;
            }
            if (property_exists($r, 'package_id') && $r->package_id !== null) {
                $item['package_id'] = (string) $r->package_id;
                $item['package_name'] = isset($r->package_name) ? (string) $r->package_name : null;
                $item['sessions_remaining'] = $r->sessions_remaining !== null ? (int) $r->sessions_remaining : null;
            }
            if (property_exists($r, 'payment_method') && $r->payment_method !== null) {
                $item['payment_method'] = (string) $r->payment_method;
            }
            if (property_exists($r, 'spoed_inval_original_trainer_id') && $r->spoed_inval_original_trainer_id !== null) {
                $item['is_inval_docent'] = true;
            }
            return $item;
        })->all();

        return response()->json(['data' => $data]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'klant') {
            return response()->json(['message' => 'Alleen klanten kunnen boeken.'], 403);
        }

        $request->validate([
            'trainer_user_id' => 'required|exists:gymies_users,id',
            'scheduled_at' => 'required|date',
            'duration_minutes' => 'nullable|integer',
            'amount_cents' => 'nullable|integer|min:0',
            'package_id' => 'nullable|integer|min:1',
            'gym_location_id' => 'nullable|integer|min:1',
        ]);

        $trainerId = (int) $request->input('trainer_user_id');
        $trainer = DB::table('gymies_users')->where('id', $trainerId)->where('role', 'trainer')->first();
        if (!$trainer) {
            return response()->json(['message' => 'Trainer niet gevonden.'], 404);
        }

        $scheduledAt = $request->input('scheduled_at');
        $duration = (int) ($request->input('duration_minutes') ?? 60);
        $leadTimeMinutes = $this->getTrainerLeadTimeMinutes($trainerId);
        $maxDaysAhead = $this->getTrainerMaxBookingDaysAhead($trainerId);
        $slotValidationError = $this->validateRequestedSlotWithLeadTime($scheduledAt, $duration, $leadTimeMinutes, $maxDaysAhead);
        if ($slotValidationError instanceof JsonResponse) {
            return $slotValidationError;
        }

        $packageId = $request->input('package_id') ? (int) $request->input('package_id') : null;
        $amountCents = $request->input('amount_cents');
        $sessionsRemaining = null;

        if ($packageId !== null && Schema::hasTable('gymies_packages') && Schema::hasColumn('gymies_bookings', 'package_id')) {
            $package = DB::table('gymies_packages')
                ->where('id', $packageId)
                ->where('trainer_user_id', $trainerId)
                ->first(['id', 'sessions_count', 'total_cents']);
            if (!$package) {
                return response()->json(['message' => 'Pakket niet gevonden of hoort niet bij deze trainer.'], 422);
            }
            $sessionsCount = (int) $package->sessions_count;
            $existingCount = (int) DB::table('gymies_bookings')
                ->where('client_user_id', $user->id)
                ->where('package_id', $packageId)
                ->whereNotIn('status', ['cancelled'])
                ->count();
            if ($existingCount >= $sessionsCount) {
                return response()->json(['message' => 'Geen resterende sessies in dit pakket. Koop een nieuw pakket of boek een losse sessie.'], 422);
            }
            $sessionsRemaining = $sessionsCount - $existingCount - 1;
            $amountCents = $existingCount === 0 ? (int) $package->total_cents : 0;
        }

        $organisationId = null;
        $payoutRoute = 'direct_trainer';
        if (DB::getSchemaBuilder()->hasTable('gymies_organisation_trainers')) {
            $orgLink = DB::table('gymies_organisation_trainers')
                ->where('trainer_user_id', $trainerId)
                ->where('status', 'active')
                ->where('is_primary', 1)
                ->first(['organisation_id', 'payout_route']);
            if ($orgLink && !empty($orgLink->organisation_id)) {
                $organisationId = (int) $orgLink->organisation_id;
                $payoutRoute = (string) ($orgLink->payout_route ?? 'via_organisation');
            }
        }

        // S-025: Race Condition Overbooking — Move overlap check INSIDE transaction scope to prevent TOCTOU
        $id = null;
        DB::beginTransaction();
        try {
            // S-025: Check overlap WITHIN transaction and before insert
            if ($this->hasPendingConfirmedOrReservedOverlap($trainerId, $scheduledAt, $duration, 0)) {
                DB::rollBack();
                return response()->json([
                    'message' => 'Dit tijdslot is al aangevraagd of bevestigd. Kies een ander tijdstip.',
                ], 409);
            }

            $insertPayload = [
                'client_user_id' => $user->id,
                'trainer_user_id' => $trainerId,
                'scheduled_at' => $scheduledAt,
                'duration_minutes' => $duration,
                'status' => 'pending',
            ];
            if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'organisation_id')) {
                $insertPayload['organisation_id'] = $organisationId;
            }
            if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'payout_route')) {
                $insertPayload['payout_route'] = $payoutRoute;
            }
            if ($amountCents !== null && DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'amount_cents')) {
                $insertPayload['amount_cents'] = (int) $amountCents;
            }
            if ($packageId !== null && Schema::hasColumn('gymies_bookings', 'package_id')) {
                $insertPayload['package_id'] = $packageId;
            }
            if ($sessionsRemaining !== null && Schema::hasColumn('gymies_bookings', 'sessions_remaining')) {
                $insertPayload['sessions_remaining'] = $sessionsRemaining;
            }
            if (Schema::hasColumn('gymies_bookings', 'gym_location_id') && $request->filled('gym_location_id')) {
                $gymLocationId = (int) $request->input('gym_location_id');
                if ($organisationId && Schema::hasTable('gymies_gym_locations')) {
                    $loc = DB::table('gymies_gym_locations')->where('id', $gymLocationId)->where('organisation_id', $organisationId)->first();
                    if ($loc) {
                        $insertPayload['gym_location_id'] = $gymLocationId;
                    }
                }
            }
            $id = DB::table('gymies_bookings')->insertGetId($insertPayload);
            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        // Echte notificatie-events voor klant en trainer.
        $payloadForTrainer = json_encode([
            'booking_id' => (string) $id,
            'client_user_id' => (string) $user->id,
            'scheduled_at' => $scheduledAt,
            'duration_minutes' => $duration,
        ], JSON_UNESCAPED_UNICODE);
        $payloadForClient = json_encode([
            'booking_id' => (string) $id,
            'trainer_user_id' => (string) $trainerId,
            'scheduled_at' => $scheduledAt,
            'duration_minutes' => $duration,
        ], JSON_UNESCAPED_UNICODE);
        DB::table('gymies_notification_queue')->insert([
            [
                'user_id' => $trainerId,
                'channel' => 'in_app',
                'event_type' => 'booking_created_for_trainer',
                'payload_json' => $payloadForTrainer,
                'scheduled_for' => now(),
                'created_at' => now(),
            ],
            [
                'user_id' => $user->id,
                'channel' => 'in_app',
                'event_type' => 'booking_pending_for_client',
                'payload_json' => $payloadForClient,
                'scheduled_for' => now(),
                'created_at' => now(),
            ],
        ]);

        $row = DB::table('gymies_bookings as b')
            ->join('gymies_users as trainer', 'b.trainer_user_id', '=', 'trainer.id')
            ->where('b.id', $id)
            ->select('b.*', 'trainer.display_name as trainer_name')
            ->first();

        $this->logAudit(
            (int) $user->id,
            'booking_created',
            'booking',
            (int) $id,
            null,
            ['trainer_user_id' => $trainerId, 'scheduled_at' => $scheduledAt, 'duration_minutes' => $duration]
        );

        $data = [
            'id' => (string) $row->id,
            'client_user_id' => (string) $row->client_user_id,
            'trainer_user_id' => (string) $row->trainer_user_id,
            'trainer_name' => $row->trainer_name ?? 'Trainer',
            'client_name' => null,
            'scheduled_at' => $row->scheduled_at,
            'duration_minutes' => (int) $row->duration_minutes,
            'status' => $row->status,
            'amount_cents' => $row->amount_cents ? (int) $row->amount_cents : null,
            'paid_at' => $row->paid_at,
            'organisation_id' => property_exists($row, 'organisation_id') && $row->organisation_id ? (string) $row->organisation_id : null,
            'payout_route' => property_exists($row, 'payout_route') ? ($row->payout_route ?? 'direct_trainer') : 'direct_trainer',
        ];
        if (property_exists($row, 'package_id') && $row->package_id !== null) {
            $data['package_id'] = (string) $row->package_id;
            $data['sessions_remaining'] = $row->sessions_remaining !== null ? (int) $row->sessions_remaining : null;
            $pkg = Schema::hasTable('gymies_packages') ? DB::table('gymies_packages')->where('id', $row->package_id)->value('name') : null;
            $data['package_name'] = $pkg ? (string) $pkg : null;
        }
        if (property_exists($row, 'payment_method') && $row->payment_method !== null) {
            $data['payment_method'] = (string) $row->payment_method;
        }
        return response()->json(['data' => $data], 201);
    }

    /**
     * Direct Boeken: maak boeking met status reserved, klant betaalt daarna direct.
     * Slot wordt 10 min gereserveerd. Lead time uit trainerprofiel (standaard 4 uur).
     */
    public function storeDirectBook(GymiesDirectBookingRequest $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'klant') {
            return response()->json(['message' => 'Alleen klanten kunnen direct boeken.'], 403);
        }
        if (Schema::hasColumn('gymies_users', 'email_verified_at')) {
            $verified = $user->email_verified_at ?? null;
            if ($verified === null || $verified === '') {
                return response()->json([
                    'message' => 'Verifieer eerst je e-mailadres voordat je kunt boeken.',
                    'requires_email_verification' => true,
                ], 422);
            }
        }

        $trainerId = (int) $request->input('trainer_user_id');
        $trainer = DB::table('gymies_users')->where('id', $trainerId)->where('role', 'trainer')->first();
        if (!$trainer) {
            return response()->json(['message' => 'Trainer niet gevonden.'], 404);
        }

        // Women-only check: als trainer women_only=1, dan alleen vrouwelijke klanten
        if (Schema::hasColumn('gymies_trainer_profiles', 'women_only') && Schema::hasColumn('gymies_users', 'gender')) {
            $profile = DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->first(['women_only']);
            $clientGender = $user->gender ?? 'not_specified';
            if ($profile && (int) ($profile->women_only ?? 0) === 1 && $clientGender !== 'female') {
                return response()->json([
                    'message' => 'Deze trainer traint momenteel uitsluitend vrouwen.',
                    'women_only' => true,
                ], 403);
            }
        }

        $scheduledAt = $request->input('scheduled_at');
        $duration = (int) ($request->input('duration_minutes') ?? 60);

        // P-FIX-1: Server-side price calculation — never trust client amount_cents
        // Fetch the trainer's service price from DB instead of using client input
        $serviceId = (int) $request->input('service_id');
        $amountCents = 0;
        if ($serviceId > 0 && Schema::hasTable('gymies_trainer_services')) {
            $service = DB::table('gymies_trainer_services')
                ->where('id', $serviceId)
                ->where('trainer_user_id', $trainerId)
                ->first(['price_cents']);
            if ($service) {
                $amountCents = (int) $service->price_cents;
            }
        }
        // If no service found or service_id not provided, use default or reject
        if ($amountCents === 0) {
            // Try to get default service price or reject
            if (Schema::hasTable('gymies_trainer_profiles')) {
                $profile = DB::table('gymies_trainer_profiles')
                    ->where('user_id', $trainerId)
                    ->first(['session_price_cents']);
                if ($profile && $profile->session_price_cents) {
                    $amountCents = (int) $profile->session_price_cents;
                }
            }
        }
        if ($amountCents === 0) {
            return response()->json(['message' => 'Geen geldige prijs gevonden. Controleer de service of trainerprofiel.'], 422);
        }

        $leadTimeMinutes = $this->getTrainerLeadTimeMinutes($trainerId);
        $maxDaysAhead = $this->getTrainerMaxBookingDaysAhead($trainerId);
        $slotError = $this->validateRequestedSlotWithLeadTime($scheduledAt, $duration, $leadTimeMinutes, $maxDaysAhead);
        if ($slotError instanceof JsonResponse) {
            return $slotError;
        }

        $organisationId = null;
        $payoutRoute = 'direct_trainer';
        if (DB::getSchemaBuilder()->hasTable('gymies_organisation_trainers')) {
            $orgLink = DB::table('gymies_organisation_trainers')
                ->where('trainer_user_id', $trainerId)
                ->where('status', 'active')
                ->where('is_primary', 1)
                ->first(['organisation_id', 'payout_route']);
            if ($orgLink && !empty($orgLink->organisation_id)) {
                $organisationId = (int) $orgLink->organisation_id;
                $payoutRoute = (string) ($orgLink->payout_route ?? 'via_organisation');
            }
        }

        $packageId = $request->input('package_id') ? (int) $request->input('package_id') : null;
        $sessionsRemaining = null;
        if ($packageId !== null && Schema::hasTable('gymies_packages') && Schema::hasColumn('gymies_bookings', 'package_id')) {
            // P-FIX-6: Lock BEFORE count to prevent race condition in package sessions
            // Lock the package row first to ensure exclusive access
            $package = DB::table('gymies_packages')
                ->where('id', $packageId)
                ->where('trainer_user_id', $trainerId)
                ->lockForUpdate()
                ->first(['id', 'sessions_count', 'total_cents']);
            if (!$package) {
                return response()->json(['message' => 'Pakket niet gevonden of hoort niet bij deze trainer.'], 422);
            }
            $sessionsCount = (int) $package->sessions_count;

            // Now count used sessions within locked context
            $existingCount = (int) DB::table('gymies_bookings')
                ->where('client_user_id', $user->id)
                ->where('package_id', $packageId)
                ->whereNotIn('status', ['cancelled'])
                ->count();
            if ($existingCount >= $sessionsCount) {
                return response()->json(['message' => 'Geen resterende sessies in dit pakket.'], 422);
            }
            $sessionsRemaining = $sessionsCount - $existingCount - 1;
            $amountCents = $existingCount === 0 ? (int) $package->total_cents : $amountCents;
        }

        $paymentMethod = trim((string) ($request->input('payment_method') ?? 'online'));

        // Cash-check: trainer moet cash accepteren
        if ($paymentMethod === 'cash' && Schema::hasColumn('gymies_trainer_profiles', 'accepts_cash')) {
            $acceptsCash = (int) (DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->value('accepts_cash') ?? 0);
            if (!$acceptsCash) {
                return response()->json(['message' => 'Deze trainer accepteert geen cash-betalingen.'], 422);
            }
        }

        $reservedUntil = now()->addMinutes(self::RESERVED_LOCK_MINUTES);
        $insertPayload = [
            'client_user_id' => $user->id,
            'trainer_user_id' => $trainerId,
            'scheduled_at' => $scheduledAt,
            'duration_minutes' => $duration,
            'amount_cents' => $amountCents,
            'status' => 'reserved',
        ];
        if (Schema::hasColumn('gymies_bookings', 'payment_method')) {
            $insertPayload['payment_method'] = $paymentMethod === 'cash' ? 'cash' : 'mollie_connect';
        }
        if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'reserved_until')) {
            $insertPayload['reserved_until'] = $reservedUntil;
        }
        if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'organisation_id')) {
            $insertPayload['organisation_id'] = $organisationId;
        }
        if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'payout_route')) {
            $insertPayload['payout_route'] = $payoutRoute;
        }
        if ($packageId !== null && Schema::hasColumn('gymies_bookings', 'package_id')) {
            $insertPayload['package_id'] = $packageId;
        }
        if ($sessionsRemaining !== null && Schema::hasColumn('gymies_bookings', 'sessions_remaining')) {
            $insertPayload['sessions_remaining'] = $sessionsRemaining;
        }
        if (Schema::hasColumn('gymies_bookings', 'gym_location_id') && $request->filled('gym_location_id')) {
            $gymLocationId = (int) $request->input('gym_location_id');
            if ($organisationId && Schema::hasTable('gymies_gym_locations')) {
                $loc = DB::table('gymies_gym_locations')->where('id', $gymLocationId)->where('organisation_id', $organisationId)->first();
                if ($loc) {
                    $insertPayload['gym_location_id'] = $gymLocationId;
                }
            }
        }

        $id = null;
        DB::beginTransaction();
        try {
            // lockForUpdate=true: vergrendelt overlappende rijen en laat gelijktijdige transacties wachten.
            // Voorkomt race-condition waarbij twee klanten tegelijk hetzelfde slot boeken.
            if ($this->hasPendingConfirmedOrReservedOverlap($trainerId, $scheduledAt, $duration, 0, lockForUpdate: true)) {
                DB::rollBack();
                return response()->json([
                    'message' => 'Dit tijdslot is net door iemand anders gekozen. Kies een ander tijdstip.',
                ], 409);
            }
            $id = DB::table('gymies_bookings')->insertGetId($insertPayload);
            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        $row = DB::table('gymies_bookings as b')
            ->join('gymies_users as trainer', 'b.trainer_user_id', '=', 'trainer.id')
            ->where('b.id', $id)
            ->select('b.*', 'trainer.display_name as trainer_name')
            ->first();

        $data = [
            'id' => (string) $row->id,
            'trainer_user_id' => (string) $row->trainer_user_id,
            'trainer_name' => $row->trainer_name ?? 'Trainer',
            'scheduled_at' => $row->scheduled_at,
            'duration_minutes' => (int) $row->duration_minutes,
            'status' => $row->status,
            'amount_cents' => (int) ($row->amount_cents ?? 0),
            'reserved_until' => isset($row->reserved_until) ? $row->reserved_until : $reservedUntil->toDateTimeString(),
        ];
        if (property_exists($row, 'payment_method') && $row->payment_method !== null) {
            $data['payment_method'] = (string) $row->payment_method;
        }
        return response()->json(['data' => $data], 201);
    }

    /**
     * Trainer bevestigt cash-betaling op locatie na QR check-in.
     */
    public function confirmCashPayment(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen cash-betaling bevestigen.'], 403);
        }
        $request->validate([
            'received_amount_cents' => 'nullable|integer|min:0',
            'note' => 'nullable|string|max:2000',
            'received_at' => 'nullable|date',
        ]);

        $booking = DB::table('gymies_bookings')
            ->where('id', (int) $id)
            ->where('trainer_user_id', (int) $user->id)
            ->first();

        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        $paymentMethod = property_exists($booking, 'payment_method') ? $booking->payment_method : null;
        if ($paymentMethod !== 'cash') {
            return response()->json(['message' => 'Dit is geen cash-boeking.'], 422);
        }

        $receivedAt = $request->input('received_at') ? Carbon::parse((string) $request->input('received_at')) : now();
        $receivedAmount = $request->input('received_amount_cents');
        $receivedAmountCents = $receivedAmount !== null ? (int) $receivedAmount : (int) ($booking->amount_cents ?? 0);
        $note = trim((string) ($request->input('note') ?? ''));

        $update = [
            'status' => 'confirmed',
            'paid_at' => $receivedAt,
            'updated_at' => now(),
        ];
        if (Schema::hasColumn('gymies_bookings', 'cash_confirmed_at')) {
            $update['cash_confirmed_at'] = $receivedAt;
            $update['cash_confirmed_by_user_id'] = (int) $user->id;
        }

        DB::beginTransaction();
        try {
            // P-FIX-3: Lock BEFORE status check to prevent TOCTOU race condition
            // Acquire row lock first, then check status within locked context
            $locked = DB::table('gymies_bookings')
                ->where('id', (int) $id)
                ->where('trainer_user_id', (int) $user->id)
                ->lockForUpdate()
                ->first();

            if (!$locked) {
                DB::rollBack();
                return response()->json(['message' => 'Boeking niet gevonden.'], 404);
            }

            if (!empty($locked->cash_confirmed_at)) {
                DB::rollBack();
                return response()->json(['message' => 'Cash is al bevestigd voor deze boeking.'], 422);
            }
            DB::table('gymies_bookings')->where('id', (int) $id)->update($update);

            if (Schema::hasTable('gymies_payment_transactions')) {
                $latestTx = DB::table('gymies_payment_transactions')
                    ->where('booking_id', (int) $id)
                    ->orderByDesc('id')
                    ->first(['id', 'provider_transaction_id']);

                if ($latestTx) {
                    DB::table('gymies_payment_transactions')
                        ->where('id', (int) $latestTx->id)
                        ->update([
                            'provider' => 'cash',
                            'payment_method' => 'cash',
                            'status' => 'paid_cash',
                            'paid_at' => $receivedAt,
                            'amount_cents' => $receivedAmountCents,
                            'updated_at' => now(),
                        ]);
                } else {
                    DB::table('gymies_payment_transactions')->insert([
                        'booking_id' => (int) $id,
                        'user_id' => (int) $booking->client_user_id,
                        'counterparty_user_id' => (int) $booking->trainer_user_id,
                        'provider' => 'cash',
                        'provider_transaction_id' => 'cash_' . (int) $id . '_' . bin2hex(random_bytes(8)),
                        'amount_cents' => $receivedAmountCents,
                        'status' => 'paid_cash',
                        'payment_method' => 'cash',
                        'paid_at' => $receivedAt,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }
            }
            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        if (Schema::hasTable('gymies_notification_queue')) {
            DB::table('gymies_notification_queue')->insert([
                'user_id' => (int) $booking->client_user_id,
                'channel' => 'in_app',
                'event_type' => 'cash_payment_confirmed',
                'payload_json' => json_encode([
                    'booking_id' => (string) $id,
                    'received_amount_cents' => $receivedAmountCents,
                    'received_at' => $receivedAt->toIso8601String(),
                    'note' => $note !== '' ? $note : null,
                    'message' => 'Je trainer heeft de contante betaling bevestigd.',
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => now(),
                'created_at' => now(),
            ]);
        }

        return response()->json(['ok' => true, 'message' => 'Cash-betaling bevestigd.']);
    }

    /**
     * Trainer accepteert een cash-boeking (reserved): sessie gaat door, contant bij check-in.
     */
    public function acceptReservedCash(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen cash-boekingen accepteren.'], 403);
        }

        $trainerId = (int) $user->id;
        $booking = DB::table('gymies_bookings')
            ->where('id', (int) $id)
            ->where('trainer_user_id', $trainerId)
            ->first();

        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if ($booking->status !== 'reserved') {
            return response()->json(['message' => 'Alleen gereserveerde boekingen kunnen worden geaccepteerd.'], 422);
        }
        $paymentMethod = property_exists($booking, 'payment_method') ? $booking->payment_method : null;
        if ($paymentMethod !== 'cash') {
            return response()->json(['message' => 'Dit is geen cash-boeking.'], 422);
        }

        DB::table('gymies_bookings')
            ->where('id', (int) $id)
            ->update([
                'status' => 'confirmed',
                'updated_at' => now(),
            ]);

        if (Schema::hasTable('gymies_notification_queue')) {
            DB::table('gymies_notification_queue')->insert([
                'user_id' => (int) $booking->client_user_id,
                'channel' => 'in_app',
                'event_type' => 'booking_confirmed_for_client',
                'payload_json' => json_encode([
                    'booking_id' => (string) $id,
                    'trainer_user_id' => (string) $trainerId,
                    'scheduled_at' => $booking->scheduled_at,
                    'message' => 'Je trainer heeft de sessie bevestigd. Contant betalen bij aanvang.',
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => now(),
                'created_at' => now(),
            ]);
        }
        if (class_exists(\App\Helpers\GymiesChatBroadcast::class)) {
            \App\Helpers\GymiesChatBroadcast::sendTrainerConfirmationToClient(
                (int) $booking->client_user_id,
                $trainerId,
                (string) $booking->scheduled_at,
                null,
                (int) $id,
            );
        }

        return $this->respondBookingById((int) $id);
    }

    // T-020 FIXED: ownership check aanwezig — trainer_user_id wordt geverifieerd op alle update-operaties
    public function confirm(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen bevestigen.'], 403);
        }
        $request->validate([
            'amount_cents' => 'nullable|integer|min:0',
            'location_type' => 'nullable|string|in:online,on_site,gym',
            'location_notes' => 'nullable|string|max:2000',
            'confirmation_note' => 'nullable|string|max:2000',
            'gym_location_id' => 'nullable|integer|min:1',
        ]);

        $trainerId = (int) $user->id;
        $confirmedBookingId = null;
        $confirmedClientId = null;
        $rejectedRows = [];

        DB::beginTransaction();
        try {
            $booking = DB::table('gymies_bookings')
                ->where('id', $id)
                ->where('trainer_user_id', $trainerId)
                ->lockForUpdate()
                ->first();
            if (!$booking) {
                DB::rollBack();
                return response()->json(['message' => 'Boeking niet gevonden.'], 404);
            }
            if ($booking->status !== 'pending') {
                DB::rollBack();
                return response()->json(['message' => 'Alleen aanvragen in afwachting kunnen worden bevestigd.'], 422);
            }

            $updatePayload = [
                'status' => 'confirmed',
                'updated_at' => now(),
            ];
            // P-FIX-2: Price is locked at booking creation — trainer cannot change it
            // The amount_cents stored in the booking record is authoritative
            // Do NOT allow: $updatePayload['amount_cents'] = (int) $amountCents;
            // Client-provided amount_cents is ignored completely
            if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'location_type')) {
                $locType = $request->input('location_type');
                if ($locType !== null && in_array($locType, ['online', 'on_site', 'gym'], true)) {
                    $updatePayload['location_type'] = $locType;
                }
            }
            if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'location_notes')) {
                $locNotes = $request->input('location_notes');
                if ($locNotes !== null) {
                    $updatePayload['location_notes'] = trim((string) $locNotes) ?: null;
                }
            }
            if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'confirmation_note')) {
                $confNote = $request->input('confirmation_note');
                if ($confNote !== null) {
                    $updatePayload['confirmation_note'] = trim((string) $confNote) ?: null;
                }
            }
            if (Schema::hasColumn('gymies_bookings', 'gym_location_id') && $request->filled('gym_location_id')) {
                $gymLocationId = (int) $request->input('gym_location_id');
                $orgId = null;
                if (Schema::hasColumn('gymies_bookings', 'organisation_id')) {
                    $orgId = $booking->organisation_id ? (int) $booking->organisation_id : null;
                }
                if (!$orgId && Schema::hasTable('gymies_organisation_trainers')) {
                    $orgLink = DB::table('gymies_organisation_trainers')
                        ->where('trainer_user_id', $trainerId)
                        ->where('status', 'active')
                        ->where('is_primary', 1)
                        ->first(['organisation_id']);
                    $orgId = $orgLink && !empty($orgLink->organisation_id) ? (int) $orgLink->organisation_id : null;
                }
                if ($orgId && Schema::hasTable('gymies_gym_locations')) {
                    $loc = DB::table('gymies_gym_locations')->where('id', $gymLocationId)->where('organisation_id', $orgId)->first();
                    if ($loc) {
                        $updatePayload['gym_location_id'] = $gymLocationId;
                    }
                }
            }
            DB::table('gymies_bookings')
                ->where('id', $booking->id)
                ->update($updatePayload);
            unset($updatePayload['updated_at']);
            $scheduledAt = (string) $booking->scheduled_at;
            $duration = (int) $booking->duration_minutes;
            // S-027: Race Condition Booking Confirm — Check overlap WITHIN transaction scope to prevent TOCTOU
            if ($this->hasConfirmedOverlap($trainerId, $scheduledAt, $duration, (int) $booking->id)) {
                DB::rollBack();
                return response()->json(['message' => 'Dit tijdslot conflicteert met een al bevestigde sessie.'], 409);
            }

            $rejectedRows = DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerId)
                ->where('id', '!=', $booking->id)
                ->where('status', 'pending')
                ->whereRaw("? < DATE_ADD(scheduled_at, INTERVAL duration_minutes MINUTE) AND DATE_ADD(?, INTERVAL ? MINUTE) > scheduled_at", [
                    $scheduledAt,
                    $scheduledAt,
                    $duration,
                ])
                ->lockForUpdate()
                ->get(['id', 'client_user_id', 'trainer_user_id'])
                ->map(fn ($r) => [
                    'id' => (int) $r->id,
                    'client_user_id' => (int) $r->client_user_id,
                    'trainer_user_id' => (int) $r->trainer_user_id,
                ])
                ->all();

            if (!empty($rejectedRows)) {
                DB::table('gymies_bookings')
                    ->whereIn('id', array_map(fn ($r) => $r['id'], $rejectedRows))
                    ->update([
                        'status' => 'cancelled',
                        'cancelled_at' => now(),
                        'cancelled_by_user_id' => $trainerId,
                        'updated_at' => now(),
                    ]);
            }

            DB::commit();
            $confirmedBookingId = (int) $booking->id;
            $confirmedClientId = (int) $booking->client_user_id;
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        if ($confirmedBookingId !== null && $confirmedClientId !== null) {
            $this->insertStatusNotifications($confirmedBookingId, $confirmedClientId, $trainerId, 'booking_confirmed');
            $confirmedBooking = DB::table('gymies_bookings')->where('id', $confirmedBookingId)->first();
            if ($confirmedBooking) {
                $confNote = DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'confirmation_note')
                    ? ($confirmedBooking->confirmation_note ?? null)
                    : null;
                if (class_exists(\App\Helpers\GymiesChatBroadcast::class)) {
                    \App\Helpers\GymiesChatBroadcast::sendTrainerConfirmationToClient(
                        $confirmedClientId,
                        $trainerId,
                        (string) $confirmedBooking->scheduled_at,
                        $confNote !== null && trim((string) $confNote) !== '' ? trim((string) $confNote) : null,
                        $confirmedBookingId,
                    );
                }
            }
            $this->logAudit(
                $trainerId,
                'booking_confirmed',
                'booking',
                $confirmedBookingId,
                ['status' => 'pending'],
                ['status' => 'confirmed']
            );
        }
        foreach ($rejectedRows as $row) {
            $this->insertStatusNotifications((int) $row['id'], (int) $row['client_user_id'], (int) $row['trainer_user_id'], 'booking_rejected');
            $this->logAudit(
                $trainerId,
                'booking_auto_rejected',
                'booking',
                (int) $row['id'],
                ['status' => 'pending'],
                ['status' => 'cancelled']
            );
        }

        return $this->respondBookingById((int) $confirmedBookingId);
    }

    /**
     * Direct verplaatsen is uitgeschakeld: beide partijen stemmen af via verplaatsingsverzoek.
     */
    public function reschedule(Request $request, string $id): JsonResponse
    {
        return response()->json([
            'message' => 'Verplaatsen gaat via een verzoek. Gebruik "Verplaatsingsverzoek" zodat de andere partij kan bevestigen.',
        ], 403);
    }

    /**
     * Verplaatsingsverzoek: trainer of klant stelt nieuwe datum/tijd voor; de andere partij moet accepteren of afwijzen.
     */
    public function rescheduleRequest(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $request->validate([
            'scheduled_at' => 'required|date',
            'duration_minutes' => 'nullable|integer',
        ]);

        $booking = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        $isTrainer = (int) $booking->trainer_user_id === (int) $user->id;
        $isClient = (int) $booking->client_user_id === (int) $user->id;
        if (!$isTrainer && !$isClient) {
            return response()->json(['message' => 'Je kunt alleen voor je eigen boekingen een verplaatsingsverzoek indienen.'], 403);
        }
        if (!in_array($booking->status, ['pending', 'confirmed'], true)) {
            return response()->json(['message' => 'Deze boeking kan niet meer verplaatst worden.'], 422);
        }

        $newScheduledAt = (string) $request->input('scheduled_at');
        $newDuration = (int) ($request->input('duration_minutes') ?? $booking->duration_minutes ?? 60);
        $trainerId = (int) $booking->trainer_user_id;
        $leadTimeMinutes = $this->getTrainerLeadTimeMinutes($trainerId);
        $maxDaysAhead = $this->getTrainerMaxBookingDaysAhead($trainerId);
        $slotValidationError = $this->validateRequestedSlotWithLeadTime($newScheduledAt, $newDuration, $leadTimeMinutes, $maxDaysAhead);
        if ($slotValidationError instanceof JsonResponse) {
            return $slotValidationError;
        }
        $bookingId = (int) $booking->id;
        if ($isTrainer && $this->hasConfirmedOverlap($trainerId, $newScheduledAt, $newDuration, $bookingId)) {
            return response()->json(['message' => 'Dit tijdslot conflicteert met een andere sessie.'], 409);
        }

        if (!Schema::hasColumn('gymies_bookings', 'proposed_scheduled_at')) {
            return response()->json(['message' => 'Verplaatsingsverzoeken zijn nog niet beschikbaar voor deze boeking.'], 503);
        }

        $now = now();
        $updatePayload = [
            'proposed_scheduled_at' => $newScheduledAt,
            'proposed_duration_minutes' => $newDuration,
            'updated_at' => $now,
        ];
        if (Schema::hasColumn('gymies_bookings', 'proposed_by_user_id')) {
            $updatePayload['proposed_by_user_id'] = $user->id;
        }
        if (Schema::hasColumn('gymies_bookings', 'proposed_at')) {
            $updatePayload['proposed_at'] = $now;
        }
        DB::table('gymies_bookings')->where('id', $bookingId)->update($updatePayload);

        // Chat als single source of truth: injecteer interactieve Reschedule_Card in trainer–klant thread
        $this->injectRescheduleCardMessage($bookingId, $booking, $user, $newScheduledAt, $newDuration);

        $this->insertStatusNotifications($bookingId, (int) $booking->client_user_id, $trainerId, 'reschedule_requested');
        $this->logAudit(
            (int) $user->id,
            'reschedule_requested',
            'booking',
            $bookingId,
            ['scheduled_at' => $booking->scheduled_at],
            ['proposed_scheduled_at' => $newScheduledAt]
        );

        $response = $this->respondBookingById($bookingId);
        $data = $response->getData(true);
        if (is_array($data)) {
            $data['auto_accepted'] = false;
            $data['message'] = $isTrainer
                ? 'Verplaatsingsverzoek verzonden. De klant moet nog reageren.'
                : 'Verplaatsingsverzoek verzonden. De trainer moet nog reageren.';
        }
        return response()->json($data);
    }

    /**
     * Reageren op verplaatsingsverzoek: alleen de andere partij (niet de indiener) kan accepteren of afwijzen.
     * Trainer kan bij accepteren optioneel locatie/notitie meegeven.
     */
    public function rescheduleRespond(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $request->validate([
            'action' => 'required|in:accept,reject',
            'location_type' => 'nullable|string|in:gym,on_site,online',
            'location_notes' => 'nullable|string|max:1000',
            'confirmation_note' => 'nullable|string|max:2000',
            'gym_location_id' => 'nullable|integer|min:1',
        ]);

        $booking = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        $isTrainer = (int) $booking->trainer_user_id === (int) $user->id;
        $isClient = (int) $booking->client_user_id === (int) $user->id;
        if (!$isTrainer && !$isClient) {
            return response()->json(['message' => 'Je kunt alleen op verzoeken voor je eigen boekingen reageren.'], 403);
        }
        if (!Schema::hasColumn('gymies_bookings', 'proposed_scheduled_at') || empty($booking->proposed_scheduled_at)) {
            return response()->json(['message' => 'Er staat geen verplaatsingsverzoek open voor deze boeking.'], 422);
        }

        $this->maybeExpireRescheduleProposal($booking);
        $booking = DB::table('gymies_bookings')->where('id', $id)->first();
        if (empty($booking->proposed_scheduled_at)) {
            return response()->json(['message' => 'Dit verplaatsingsverzoek is verlopen. De sessie is geannuleerd met volledige restitutie.'], 422);
        }

        $proposedByUserId = Schema::hasColumn('gymies_bookings', 'proposed_by_user_id') && $booking->proposed_by_user_id !== null
            ? (int) $booking->proposed_by_user_id
            : null;
        $onlyOtherPartyResponds = $proposedByUserId !== null
            ? (($proposedByUserId === (int) $booking->trainer_user_id && $isClient) || ($proposedByUserId === (int) $booking->client_user_id && $isTrainer))
            : true;
        if (!$onlyOtherPartyResponds) {
            return response()->json(['message' => 'Alleen de andere partij kan op dit verzoek reageren. Jij hebt het verzoek ingediend.'], 403);
        }

        $action = (string) $request->input('action');
        $proposedAt = (string) $booking->proposed_scheduled_at;
        $proposedDuration = (int) ($booking->proposed_duration_minutes ?? $booking->duration_minutes ?? 60);

        if ($action === 'reject') {
            $clearPayload = [
                'proposed_scheduled_at' => null,
                'proposed_duration_minutes' => null,
                'updated_at' => now(),
            ];
            if (Schema::hasColumn('gymies_bookings', 'proposed_by_user_id')) {
                $clearPayload['proposed_by_user_id'] = null;
            }
            if (Schema::hasColumn('gymies_bookings', 'proposed_at')) {
                $clearPayload['proposed_at'] = null;
            }
            DB::table('gymies_bookings')->where('id', $booking->id)->update($clearPayload);
            $this->updateRescheduleCardState((int) $booking->id, 'rejected');
            $this->insertStatusNotifications((int) $booking->id, (int) $booking->client_user_id, (int) $booking->trainer_user_id, 'reschedule_rejected');
            $response = $this->respondBookingById((int) $booking->id);
            $data = $response->getData(true);
            if (is_array($data)) {
                $data['message'] = 'Verplaatsingsverzoek afgewezen.';
            }
            return response()->json($data);
        }

        $trainerIdForSlot = (int) $booking->trainer_user_id;
        $leadTimeMinutes = $this->getTrainerLeadTimeMinutes($trainerIdForSlot);
        $maxDaysAhead = $this->getTrainerMaxBookingDaysAhead($trainerIdForSlot);
        $slotError = $this->validateRequestedSlotWithLeadTime($proposedAt, $proposedDuration, $leadTimeMinutes, $maxDaysAhead);
        if ($slotError instanceof JsonResponse) {
            return $slotError;
        }
        if ($this->hasConfirmedOverlap($trainerIdForSlot, $proposedAt, $proposedDuration, (int) $booking->id)) {
            return response()->json(['message' => 'Het voorgestelde tijdslot conflicteert inmiddels met een andere sessie.'], 409);
        }

        $updatePayload = [
            'scheduled_at' => $proposedAt,
            'duration_minutes' => $proposedDuration,
            'proposed_scheduled_at' => null,
            'proposed_duration_minutes' => null,
            'status' => 'confirmed',
            'updated_at' => now(),
        ];
        if (Schema::hasColumn('gymies_bookings', 'proposed_by_user_id')) {
            $updatePayload['proposed_by_user_id'] = null;
        }
        if (Schema::hasColumn('gymies_bookings', 'proposed_at')) {
            $updatePayload['proposed_at'] = null;
        }
        if ($isTrainer && DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'location_type')) {
            $locType = $request->input('location_type');
            if ($locType !== null) {
                $updatePayload['location_type'] = $locType;
            }
            $locNotes = $request->input('location_notes');
            if ($locNotes !== null) {
                $updatePayload['location_notes'] = trim((string) $locNotes) ?: null;
            }
        }
        if ($isTrainer && DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'confirmation_note')) {
            $confNote = $request->input('confirmation_note');
            if ($confNote !== null) {
                $updatePayload['confirmation_note'] = trim((string) $confNote) ?: null;
            }
        }
        if ($isTrainer && Schema::hasColumn('gymies_bookings', 'gym_location_id') && $request->filled('gym_location_id')) {
            $gymLocationId = (int) $request->input('gym_location_id');
            $orgId = $booking->organisation_id ? (int) $booking->organisation_id : null;
            if (!$orgId && Schema::hasTable('gymies_organisation_trainers')) {
                $orgLink = DB::table('gymies_organisation_trainers')
                    ->where('trainer_user_id', (int) $booking->trainer_user_id)
                    ->where('status', 'active')
                    ->where('is_primary', 1)
                    ->first(['organisation_id']);
                $orgId = $orgLink && !empty($orgLink->organisation_id) ? (int) $orgLink->organisation_id : null;
            }
            if ($orgId && Schema::hasTable('gymies_gym_locations')) {
                $loc = DB::table('gymies_gym_locations')->where('id', $gymLocationId)->where('organisation_id', $orgId)->first();
                if ($loc) {
                    $updatePayload['gym_location_id'] = $gymLocationId;
                }
            }
        }
        DB::table('gymies_bookings')->where('id', $booking->id)->update($updatePayload);

        $this->updateRescheduleCardState((int) $booking->id, 'accepted');
        $this->insertStatusNotifications((int) $booking->id, (int) $booking->client_user_id, (int) $booking->trainer_user_id, 'booking_rescheduled');
        $updatedBooking = DB::table('gymies_bookings')->where('id', $booking->id)->first();
        if ($updatedBooking) {
            $confNote = DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'confirmation_note')
                ? ($updatedBooking->confirmation_note ?? null)
                : null;
            if (class_exists(\App\Helpers\GymiesChatBroadcast::class)) {
                \App\Helpers\GymiesChatBroadcast::sendTrainerConfirmationToClient(
                    (int) $booking->client_user_id,
                    (int) $booking->trainer_user_id,
                    (string) $updatedBooking->scheduled_at,
                    $confNote !== null && trim((string) $confNote) !== '' ? trim((string) $confNote) : null,
                    (int) $booking->id,
                );
            }
        }
        $this->logAudit(
            (int) $user->id,
            'reschedule_accepted',
            'booking',
            (int) $booking->id,
            ['scheduled_at' => $booking->scheduled_at],
            ['scheduled_at' => $proposedAt]
        );
        $response = $this->respondBookingById((int) $booking->id);
        $data = $response->getData(true);
        if (is_array($data)) {
            $data['message'] = 'Verplaatsingsverzoek geaccepteerd.';
        }
        return response()->json($data);
    }

    /**
     * Als er een open verplaatsingsverzoek is en de termijn (24u) is verstreken: annuleer boeking met 100% restitutie.
     */
    private function maybeExpireRescheduleProposal(object $booking): void
    {
        if (!Schema::hasColumn('gymies_bookings', 'proposed_at') || $booking->proposed_at === null) {
            return;
        }
        $deadline = Carbon::parse($booking->proposed_at)->addHours(24);
        if (now()->lessThan($deadline)) {
            return;
        }
        $bookingId = (int) $booking->id;
        $clearPayload = [
            'proposed_scheduled_at' => null,
            'proposed_duration_minutes' => null,
            'proposed_by_user_id' => null,
            'proposed_at' => null,
            'status' => 'cancelled',
            'cancelled_at' => now(),
            'cancelled_by_user_id' => null,
            'updated_at' => now(),
        ];
        if (!Schema::hasColumn('gymies_bookings', 'proposed_by_user_id')) {
            unset($clearPayload['proposed_by_user_id']);
        }
        if (!Schema::hasColumn('gymies_bookings', 'proposed_at')) {
            unset($clearPayload['proposed_at']);
        }
        DB::table('gymies_bookings')->where('id', $bookingId)->update($clearPayload);
        $this->insertStatusNotifications(
            $bookingId,
            (int) $booking->client_user_id,
            (int) $booking->trainer_user_id,
            'reschedule_expired'
        );
    }

    /**
     * Platform annuleringsbeleid: bepaalt restitutie en toegestane methode op basis van uren tot aanvang.
     * @return array{refund_percent: int, refund_method_allowed: string, cancellation_policy_message: string, penalty_applies: bool, penalty_cents: int}
     */
    private function platformCancellationOutcome(float $hoursUntil, bool $isTrainer, ?string $bookingCreatedAt = null): array
    {
        // Bedenktijd: klant annuleert binnen 15 min na boeken → altijd 100% bank (geen fee)
        if (!$isTrainer && $bookingCreatedAt !== null) {
            $minutesSinceBooking = Carbon::parse($bookingCreatedAt)->diffInSeconds(now()) / 60.0;
            if ($minutesSinceBooking <= self::GRACE_PERIOD_MINUTES) {
                return [
                    'refund_percent' => 100,
                    'refund_method_allowed' => 'bank_or_wallet',
                    'cancellation_policy_message' => 'Bedenktijd: je annuleert binnen 15 minuten na boeken. 100% terug, geen kosten.',
                    'penalty_applies' => false,
                    'penalty_cents' => 0,
                    'grace_period' => true,
                ];
            }
        }

        $penaltyApplies = false;
        $penaltyCents = 0;
        if ($isTrainer) {
            if ($hoursUntil < self::CANCELLATION_HOURS_CREDITS_ONLY) {
                $penaltyApplies = true;
                $penaltyCents = self::TRAINER_PENALTY_CENTS;
            }
            return [
                'refund_percent' => 100,
                'refund_method_allowed' => $hoursUntil >= self::CANCELLATION_HOURS_FULL_CHOICE ? 'bank_or_wallet' : 'wallet_only',
                'cancellation_policy_message' => $penaltyApplies
                    ? 'Trainer annuleert binnen 24 uur. Klant krijgt 100% terug. Trainer krijgt een boete van €25.'
                    : 'Trainer heeft geannuleerd. Volledige restitutie voor de klant.',
                'penalty_applies' => $penaltyApplies,
                'penalty_cents' => $penaltyCents,
                'grace_period' => false,
            ];
        }
        if ($hoursUntil >= self::CANCELLATION_HOURS_FULL_CHOICE) {
            return [
                'refund_percent' => 100,
                'refund_method_allowed' => 'bank_or_wallet',
                'cancellation_policy_message' => 'Gratis annuleren tot 48 uur van tevoren. Je kunt kiezen: Gymies Credits (direct) of bankoverschrijving (3–5 werkdagen).',
                'penalty_applies' => false,
                'penalty_cents' => 0,
                'grace_period' => false,
            ];
        }
        if ($hoursUntil >= self::CANCELLATION_HOURS_CREDITS_ONLY) {
            return [
                'refund_percent' => 100,
                'refund_method_allowed' => 'wallet_only',
                'cancellation_policy_message' => 'Bij annulering tussen 24 en 48 uur ontvang je het bedrag terug in Gymies Credits (direct beschikbaar voor een nieuwe sessie).',
                'penalty_applies' => false,
                'penalty_cents' => 0,
                'grace_period' => false,
            ];
        }
        return [
            'refund_percent' => 0,
            'refund_method_allowed' => 'none',
            'cancellation_policy_message' => 'Binnen 24 uur voor aanvang is geen restitutie mogelijk. De volledige boekingswaarde blijft in rekening.',
            'penalty_applies' => false,
            'penalty_cents' => 0,
            'grace_period' => false,
        ];
    }

    /**
     * Preview: welke restitutie geldt bij annuleren (platformbeleid 48u/24u).
     */
    public function cancellationPreview(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $booking = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        $isTrainer = (int) $booking->trainer_user_id === (int) $user->id;
        $isClient = (int) $booking->client_user_id === (int) $user->id;
        if (!$isTrainer && !$isClient) {
            return response()->json(['message' => 'Je kunt alleen je eigen boekingen annuleren.'], 403);
        }
        if (in_array($booking->status, ['cancelled', 'completed', 'no_show'], true)) {
            return response()->json(['message' => 'Deze boeking kan niet meer geannuleerd worden.'], 422);
        }

        $scheduledAt = Carbon::parse($booking->scheduled_at);
        $hoursUntil = $scheduledAt->isFuture() ? $scheduledAt->diffInSeconds(now()) / 3600.0 : 0.0;
        $outcome = $this->platformCancellationOutcome($hoursUntil, $isTrainer, $booking->created_at ?? null);

        return response()->json([
            'data' => [
                'cancellation_policy_message' => $outcome['cancellation_policy_message'],
                'refund_percent' => $outcome['refund_percent'],
                'refund_method_allowed' => $outcome['refund_method_allowed'],
                'penalty_applies' => $outcome['penalty_applies'],
                'penalty_cents' => $outcome['penalty_cents'],
            ],
        ]);
    }

    /**
     * Annuleren: platformbeleid 48u/24u. Klant kiest bij >48u: wallet of bank. Trainer <24u: boete €25.
     */
    public function cancel(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $booking = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        $isTrainer = (int) $booking->trainer_user_id === (int) $user->id;
        $isClient = (int) $booking->client_user_id === (int) $user->id;
        if (!$isTrainer && !$isClient) {
            return response()->json(['message' => 'Je kunt alleen je eigen boekingen annuleren.'], 403);
        }
        if (in_array($booking->status, ['cancelled', 'completed', 'no_show'], true)) {
            return response()->json(['message' => 'Deze boeking kan niet meer geannuleerd worden.'], 422);
        }

        $scheduledAt = Carbon::parse($booking->scheduled_at);
        $hoursUntil = $scheduledAt->isFuture() ? $scheduledAt->diffInSeconds(now()) / 3600.0 : 0.0;
        $outcome = $this->platformCancellationOutcome($hoursUntil, $isTrainer, $booking->created_at ?? null);
        $refundPercent = $outcome['refund_percent'];
        $refundMethodAllowed = $outcome['refund_method_allowed'];
        $isGracePeriod = $outcome['grace_period'] ?? false;

        $refundMethod = null;
        if ($refundPercent > 0) {
            if ($isTrainer) {
                $refundMethod = 'wallet'; // trainer annuleert: klant altijd 100% naar wallet
            } elseif ($isClient && in_array($refundMethodAllowed, ['bank_or_wallet', 'wallet_only'], true)) {
                // S-068: Missing Rate Limit Refund Method — max 5 refund-aanvragen per uur per user
                if ($refundMethodAllowed === 'bank_or_wallet') {
                    if (Schema::hasTable('gymies_rate_limits')) {
                        $refundKey = 'refund_req:' . (int) $user->id;
                        $windowStart = now()->subMinutes(60);
                        $refundCount = DB::table('gymies_rate_limits')
                            ->where('key', $refundKey)
                            ->where('window_start', '>=', $windowStart)
                            ->count();
                        if ($refundCount >= 5) {
                            return response()->json(['message' => 'Te veel refund-aanvragen. Probeer het later opnieuw.'], 429);
                        }
                        DB::table('gymies_rate_limits')->insert([
                            'key'          => $refundKey,
                            'window_start' => now(),
                            'created_at'   => now(),
                        ]);
                    }
                }
                $refundMethod = $refundMethodAllowed === 'wallet_only' ? 'wallet' : $request->input('refund_method', 'wallet');
                if (!in_array($refundMethod, ['wallet', 'bank'], true)) {
                    $refundMethod = 'wallet';
                }
            }
        }

        DB::beginTransaction();
        try {
            // Vergrendel de rij eerst om race conditions bij gelijktijdige annuleringen te voorkomen.
            $locked = DB::table('gymies_bookings')
                ->where('id', $booking->id)
                ->whereNotIn('status', ['cancelled', 'completed', 'no_show'])
                ->lockForUpdate()
                ->first(['id', 'status']);
            if (!$locked) {
                DB::rollBack();
                return response()->json(['message' => 'Boeking kon niet worden geannuleerd (al geannuleerd of afgerond).'], 422);
            }
            DB::table('gymies_bookings')
                ->where('id', $booking->id)
                ->update([
                    'status' => 'cancelled',
                    'cancelled_at' => now(),
                    'cancelled_by_user_id' => $user->id,
                    'updated_at' => now(),
                ]);

            $amountCents = (int) ($booking->amount_cents ?? 0);
            $clientUserId = (int) $booking->client_user_id;
            $trainerUserId = (int) $booking->trainer_user_id;

            if ($isTrainer && $outcome['penalty_applies']) {
                $this->applyTrainerPenalty($trainerUserId, (int) $booking->id, 'late_cancellation');
            }

            if ($refundPercent > 0 && $amountCents > 0) {
                if ($refundMethod === 'wallet' && Schema::hasTable('gymies_wallet_transactions') && Schema::hasColumn('gymies_users', 'wallet_balance_cents')) {
                    // Atomische increment voorkomt race condition bij gelijktijdige refunds.
                    DB::table('gymies_users')->where('id', $clientUserId)->increment('wallet_balance_cents', $amountCents);
                    $newBalance = (int) (DB::table('gymies_users')->where('id', $clientUserId)->value('wallet_balance_cents') ?? 0);
                    $walletInsert = [
                        'user_id' => $clientUserId,
                        'amount_cents' => $amountCents,
                        'balance_after_cents' => $newBalance,
                        'booking_id' => (int) $booking->id,
                        'reason' => $isTrainer ? 'Annulering door trainer. Restitutie.' : 'Annulering door klant. Restitutie volgens beleid.',
                        'reference_type' => 'cancellation_refund',
                        'admin_user_id' => null,
                        'created_at' => now(),
                    ];
                    if (Schema::hasColumn('gymies_wallet_transactions', 'expires_at')) {
                        $walletInsert['expires_at'] = now()->addYear()->toDateString();
                    }
                    DB::table('gymies_wallet_transactions')->insert($walletInsert);
                } elseif ($refundMethod === 'bank' && Schema::hasTable('gymies_admin_refunds')) {
                    $bankFeeCents = 0;
                    if (!$isGracePeriod) {
                        $bankFeeCents = 99;
                        if (Schema::hasTable('gymies_system_settings')) {
                            $row = DB::table('gymies_system_settings')->where('setting_key', 'bank_refund_admin_fee_cents')->first();
                            if ($row) {
                                $bankFeeCents = (int) $row->setting_value;
                            }
                        }
                    }
                    $refundAmountCents = max(0, $amountCents - $bankFeeCents);
                    $reason = $isGracePeriod
                        ? 'Bedenktijd (15 min). 100% teruggestort, geen kosten.'
                        : 'Klant koos bankoverschrijving bij annulering (>48u). Transactiekosten ingehouden. Verwerken via Mollie/admin.';
                    DB::table('gymies_admin_refunds')->insert([
                        'booking_id' => (int) $booking->id,
                        'client_user_id' => $clientUserId,
                        'type' => 'full_refund',
                        'amount_cents' => $refundAmountCents,
                        'status' => 'pending',
                        'reason' => $reason,
                        'admin_user_id' => (int) $user->id,
                        'created_at' => now(),
                    ]);

                    // S-069: Missing Bank Refund Audit — log admin action for bank refunds
                    if (DB::getSchemaBuilder()->hasTable('gymies_audit_log')) {
                        DB::table('gymies_audit_log')->insert([
                            'user_id' => (int) $user->id,
                            'action' => 'admin.bank_refund',
                            'entity_type' => 'booking',
                            'entity_id' => (int) $booking->id,
                            'new_values' => json_encode([
                                'refund_amount_cents' => $refundAmountCents,
                                'bank_fee_cents' => $bankFeeCents,
                                'reason' => $reason,
                            ], JSON_UNESCAPED_UNICODE),
                            'ip_address' => request()->ip(),
                            'created_at' => now(),
                        ]);
                    }
                }
            }

            $this->insertStatusNotifications((int) $booking->id, $clientUserId, $trainerUserId, 'booking_cancelled');
            $this->logAudit(
                (int) $user->id,
                'booking_cancelled',
                'booking',
                (int) $booking->id,
                ['status' => $booking->status],
                ['status' => 'cancelled', 'refund_percent' => $refundPercent, 'refund_method' => $refundMethod]
            );
            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        $response = $this->respondBookingById((int) $booking->id);
        $payload = $response->getData(true);
        if (is_array($payload)) {
            $payload['refund_percent'] = $refundPercent;
            $payload['cancellation_policy_message'] = $outcome['cancellation_policy_message'];
            $payload['refund_method_used'] = $refundMethod;
        }
        return response()->json($payload);
    }

    private function applyTrainerPenalty(int $trainerUserId, int $bookingId, string $reason): void
    {
        if (!Schema::hasColumn('gymies_users', 'trainer_balance_cents')) {
            return;
        }

        // P-FIX-4: Idempotency guard for trainer penalty
        // Check if penalty has already been applied to prevent double-deduction
        if (Schema::hasTable('gymies_trainer_penalties')) {
            $existingPenalty = DB::table('gymies_trainer_penalties')
                ->where('booking_id', $bookingId)
                ->where('trainer_user_id', $trainerUserId)
                ->first();
            if ($existingPenalty) {
                // Penalty already applied — skip to prevent double-deduction
                return;
            }
        }

        // P-FIX-5: Check balance before penalty decrement to prevent negative balance
        $trainer = DB::table('gymies_users')->where('id', $trainerUserId)->lockForUpdate()->first(['trainer_balance_cents']);
        $penaltyCents = self::TRAINER_PENALTY_CENTS;
        if ($trainer && $trainer->trainer_balance_cents < $penaltyCents) {
            // Apply only what is available, log the shortfall
            $penaltyCents = max(0, $trainer->trainer_balance_cents);
            if (function_exists('logger')) {
                logger()->warning('Trainer penalty exceeds available balance', [
                    'trainer_id' => $trainerUserId,
                    'booking_id' => $bookingId,
                    'available_cents' => $trainer->trainer_balance_cents,
                    'penalty_cents' => self::TRAINER_PENALTY_CENTS,
                ]);
            }
        }

        // B30: Atomische decrement voorkomt race condition bij gelijktijdige penalty-toepassingen.
        DB::table('gymies_users')->where('id', $trainerUserId)->decrement('trainer_balance_cents', $penaltyCents, ['updated_at' => now()]);
        $newBalance = (int) (DB::table('gymies_users')->where('id', $trainerUserId)->value('trainer_balance_cents') ?? 0);
        if (Schema::hasTable('gymies_trainer_penalties')) {
            DB::table('gymies_trainer_penalties')->insert([
                'trainer_user_id' => $trainerUserId,
                'amount_cents' => -$penaltyCents,
                'booking_id' => $bookingId,
                'reason' => $reason,
                'balance_after_cents' => $newBalance,
                'created_at' => now(),
            ]);
        }

        // Reset Gymies Pro consecutive counter op annulering
        if (Schema::hasColumn('gymies_trainer_profiles', 'consecutive_completed')) {
            DB::table('gymies_trainer_profiles')->where('user_id', $trainerUserId)->update([
                'consecutive_completed' => 0,
            ]);
        }
    }

    private function formatCancellationPolicyMessage(int $hoursBefore, int $refundPercent, ?string $name): string
    {
        if ($hoursBefore >= 24) {
            $days = (int) ($hoursBefore / 24);
            $label = $days === 1 ? '24 uur' : "{$days} uur";
            return $refundPercent >= 100
                ? "Gratis annuleren tot {$label} van tevoren."
                : "Tot {$label} van tevoren: {$refundPercent}% restitutie.";
        }
        if ($hoursBefore > 0) {
            return $refundPercent >= 100
                ? "Gratis annuleren tot {$hoursBefore} uur van tevoren."
                : "Tot {$hoursBefore} uur van tevoren: {$refundPercent}% restitutie.";
        }
        return $refundPercent > 0
            ? "Binnen de termijn: {$refundPercent}% restitutie."
            : "Binnen de termijn: geen restitutie.";
    }

    /**
     * Beoordeling plaatsen: alleen klant, voor eigen voltooide boeking, één review per boeking.
     */
    public function storeReview(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'klant') {
            return response()->json(['message' => 'Alleen klanten kunnen een beoordeling plaatsen.'], 403);
        }
        $request->validate([
            'rating' => 'required|integer|min:1|max:5',
            'review_text' => 'nullable|string|max:2000',
        ]);

        // S-030: Information Disclosure Review — Filter query by client_user_id to prevent existence disclosure
        $booking = DB::table('gymies_bookings')
            ->where('id', $id)
            ->where('client_user_id', $user->id)
            ->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if ($booking->status !== 'completed') {
            return response()->json(['message' => 'Alleen voltooide sessies kunnen worden beoordeeld.'], 422);
        }

        if (!Schema::hasTable('gymies_reviews')) {
            return response()->json(['message' => 'Beoordelingen zijn nog niet beschikbaar.'], 503);
        }
        if (DB::table('gymies_reviews')->where('booking_id', (int) $id)->exists()) {
            return response()->json(['message' => 'Je hebt deze sessie al beoordeeld.'], 422);
        }

        $rating = (int) $request->input('rating');
        $reviewText = $request->input('review_text') ? trim((string) $request->input('review_text')) : null;
        DB::table('gymies_reviews')->insert([
            'booking_id' => (int) $id,
            'client_user_id' => (int) $user->id,
            'trainer_user_id' => (int) $booking->trainer_user_id,
            'rating' => $rating,
            'review_text' => $reviewText,
            'status' => 'approved',
            'created_at' => now(),
        ]);
        return response()->json([
            'message' => 'Bedankt voor je beoordeling!',
            'data' => ['booking_id' => (string) $id, 'rating' => $rating],
        ]);
    }

    /**
     * Controleren of de ingelogde klant deze boeking al heeft beoordeeld.
     */
    public function getReviewStatus(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $booking = DB::table('gymies_bookings')->where('id', $id)->first(['id', 'client_user_id', 'status']);
        if (!$booking || (int) $booking->client_user_id !== (int) $user->id) {
            return response()->json(['data' => ['has_review' => false]]);
        }
        $hasReview = false;
        $rating = null;
        if (Schema::hasTable('gymies_reviews')) {
            $review = DB::table('gymies_reviews')->where('booking_id', (int) $id)->first(['rating']);
            $hasReview = $review !== null;
            $rating = $review ? (int) $review->rating : null;
        }
        return response()->json(['data' => ['has_review' => $hasReview, 'rating' => $rating]]);
    }

    /**
     * Trainer: sessie markeren als "Voltooid" of "Klant niet verschenen" (no_show).
     * Alleen voor bevestigde boekingen waar het geplande tijdslot al is verstreken.
     * No-show zorgt ervoor dat de trainer uitbetaling behoudt (status telt mee voor revenue).
     */
    public function sessionStatus(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen de sessiestatus bijwerken.'], 403);
        }
        $request->validate([
            'status' => 'required|in:completed,no_show',
        ]);
        $newStatus = (string) $request->input('status');

        $booking = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if ((int) $booking->trainer_user_id !== (int) $user->id) {
            return response()->json(['message' => 'Je kunt alleen je eigen sessies markeren.'], 403);
        }
        if ($booking->status !== 'confirmed') {
            return response()->json(['message' => 'Alleen bevestigde sessies kunnen als voltooid of no-show worden gemarkeerd.'], 422);
        }

        $scheduledAt = Carbon::parse($booking->scheduled_at);
        $duration = (int) ($booking->duration_minutes ?? 60);
        $sessionEnd = $scheduledAt->copy()->addMinutes($duration);
        if (now()->lessThan($sessionEnd)) {
            return response()->json(['message' => 'Je kunt de sessie pas na het geplande einde markeren.'], 422);
        }

        // S-029 & S-031: Business Logic No-Show too early + Time Manipulation — Validate scheduled_at is not in future and respect grace period for no-show
        if (now()->lt(Carbon::parse($booking->scheduled_at))) {
            return response()->json(['message' => 'De geplande tijd mag niet in de toekomst liggen.'], 422);
        }
        if ($newStatus === 'no_show' && now()->lt($scheduledAt->copy()->addMinutes(5))) {
            return response()->json(['message' => 'Je kunt pas 5 minuten na de starttijd een no-show melden.'], 422);
        }

        DB::table('gymies_bookings')->where('id', $id)->update([
            'status' => $newStatus,
            'updated_at' => now(),
        ]);

        $this->logAudit((int) $user->id, 'session_status_' . $newStatus, 'booking', (int) $id, ['status' => 'confirmed'], ['status' => $newStatus]);

        // Gymies Points: check referral bonuses bij voltooide sessies
        // S-070: Timing Leak Referral — dispatch referral updates as async job to prevent timing attacks
        if ($newStatus === 'completed' && class_exists(\App\Http\Controllers\Gymies\GymiesPointsService::class)) {
            $clientId = (int) ($booking->client_user_id ?? 0);
            if ($clientId > 0 && Schema::hasTable('gymies_referrals')) {
                // Dispatch async job instead of sync processing to prevent timing-based information disclosure
                if (class_exists('Illuminate\Support\Facades\Queue')) {
                    try {
                        \Illuminate\Support\Facades\Queue::push(function () use ($clientId, $id) {
                            $referral = DB::table('gymies_referrals')
                                ->where('referred_user_id', $clientId)
                                ->where('status', 'completed')
                                ->first();
                            if ($referral) {
                                $referrerId = (int) $referral->referrer_user_id;
                                $bookingId = (int) $id;

                                // Tel voltooide sessies van deze verwezen gebruiker
                                $sessionCount = DB::table('gymies_bookings')
                                    ->where('client_user_id', $clientId)
                                    ->where('status', 'completed')
                                    ->count();

                                // Eerste sessie bonus
                                if ($sessionCount === 1) {
                                    \App\Http\Controllers\Gymies\GymiesPointsService::award(
                                        $referrerId,
                                        'referral_first_session',
                                        $bookingId,
                                        'gymies_bookings',
                                        'Verwezen vriend voltooit eerste sessie'
                                    );
                                }

                                // Milestone sessies bonus
                                $rule = \App\Http\Controllers\Gymies\GymiesPointsService::getRule('referral_session_milestone');
                                if ($rule) {
                                    $conditions = is_string($rule->conditions_json)
                                        ? json_decode($rule->conditions_json, true) ?? []
                                        : (array) $rule->conditions_json;
                                    $threshold = (int) ($conditions['sessions_threshold'] ?? 5);
                                    if ($sessionCount === $threshold) {
                                        \App\Http\Controllers\Gymies\GymiesPointsService::award(
                                            $referrerId,
                                            'referral_session_milestone',
                                            $clientId,
                                            'gymies_users',
                                            "Verwezen vriend bereikt {$threshold} sessies"
                                        );
                                    }
                                }
                            }
                        });
                    } catch (\Throwable $e) {
                        if (function_exists('logger')) {
                            logger()->warning('Gymies referral milestone job dispatch failed (non-blocking)', ['error' => $e->getMessage()]);
                        }
                    }
                } else {
                    // Fallback: sync processing if queue unavailable
                    $referral = DB::table('gymies_referrals')
                        ->where('referred_user_id', $clientId)
                        ->where('status', 'completed')
                        ->first();
                    if ($referral) {
                        $referrerId = (int) $referral->referrer_user_id;
                        $bookingId = (int) $id;

                        // Tel voltooide sessies van deze verwezen gebruiker
                        $sessionCount = DB::table('gymies_bookings')
                            ->where('client_user_id', $clientId)
                            ->where('status', 'completed')
                            ->count();

                        // Eerste sessie bonus
                        if ($sessionCount === 1) {
                            \App\Http\Controllers\Gymies\GymiesPointsService::award(
                                $referrerId,
                                'referral_first_session',
                                $bookingId,
                                'gymies_bookings',
                                'Verwezen vriend voltooit eerste sessie'
                            );
                        }

                        // Milestone sessies bonus
                        $rule = \App\Http\Controllers\Gymies\GymiesPointsService::getRule('referral_session_milestone');
                        if ($rule) {
                            $conditions = is_string($rule->conditions_json)
                                ? json_decode($rule->conditions_json, true) ?? []
                                : (array) $rule->conditions_json;
                            $threshold = (int) ($conditions['sessions_threshold'] ?? 5);
                            if ($sessionCount === $threshold) {
                                \App\Http\Controllers\Gymies\GymiesPointsService::award(
                                    $referrerId,
                                    'referral_session_milestone',
                                    $clientId,
                                    'gymies_users',
                                    "Verwezen vriend bereikt {$threshold} sessies"
                                );
                            }
                        }
                    }
                }
            }
        }

        return $this->respondBookingById((int) $id);
    }

    /**
     * Klant: meldt "Trainer niet verschenen". Na sessie-einde (+15 min): 100% naar wallet, trainer €25 boete.
     */
    public function reportTrainerNoShow(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $booking = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if ((int) $booking->client_user_id !== (int) $user->id) {
            return response()->json(['message' => 'Alleen de klant van deze boeking kan dit melden.'], 403);
        }
        if ($booking->status !== 'confirmed') {
            return response()->json(['message' => 'Alleen bevestigde boekingen kunnen als trainer-no-show worden gemeld.'], 422);
        }

        $scheduledAt = Carbon::parse($booking->scheduled_at);
        $sessionEnd = $scheduledAt->copy()->addMinutes((int) ($booking->duration_minutes ?? 60));
        $minReportTime = $scheduledAt->copy()->addMinutes(15);
        if (now()->lessThan($minReportTime)) {
            return response()->json(['message' => 'Je kunt dit pas 15 minuten na de afgesproken starttijd melden.'], 422);
        }

        $amountCents = (int) ($booking->amount_cents ?? 0);
        $clientUserId = (int) $booking->client_user_id;
        $trainerUserId = (int) $booking->trainer_user_id;

        DB::beginTransaction();
        try {
            DB::table('gymies_bookings')->where('id', $id)->update([
                'status' => 'cancelled',
                'cancelled_at' => now(),
                'cancelled_by_user_id' => null,
                'updated_at' => now(),
            ]);

            $this->applyTrainerPenalty($trainerUserId, (int) $booking->id, 'trainer_no_show');

            if ($amountCents > 0 && Schema::hasTable('gymies_wallet_transactions') && Schema::hasColumn('gymies_users', 'wallet_balance_cents')) {
                // Atomische increment voorkomt race condition bij gelijktijdige updates.
                DB::table('gymies_users')->where('id', $clientUserId)->increment('wallet_balance_cents', $amountCents);
                $newBalance = (int) (DB::table('gymies_users')->where('id', $clientUserId)->value('wallet_balance_cents') ?? 0);
                $walletInsert = [
                    'user_id' => $clientUserId,
                    'amount_cents' => $amountCents,
                    'balance_after_cents' => $newBalance,
                    'booking_id' => (int) $booking->id,
                    'reason' => 'Trainer niet verschenen. 100% restitutie.',
                    'reference_type' => 'trainer_no_show_refund',
                    'admin_user_id' => null,
                    'created_at' => now(),
                ];
                if (Schema::hasColumn('gymies_wallet_transactions', 'expires_at')) {
                    $walletInsert['expires_at'] = now()->addYear()->toDateString();
                }
                DB::table('gymies_wallet_transactions')->insert($walletInsert);
            }

            $this->logAudit((int) $user->id, 'client_reported_trainer_no_show', 'booking', (int) $booking->id, ['status' => 'confirmed'], ['status' => 'cancelled']);
            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        return response()->json([
            'message' => 'Melding ontvangen. Het bedrag is teruggestort op je Gymies-wallet.',
            'data' => $this->respondBookingById((int) $booking->id)->getData(true),
        ]);
    }

    /**
     * Trainer: beoordeling + eventuele reactie ophalen voor een boeking.
     */
    public function getBookingReview(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $booking = DB::table('gymies_bookings')->where('id', $id)->first(['id', 'trainer_user_id', 'status']);
        if (!$booking || (int) $booking->trainer_user_id !== (int) $user->id) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if (!Schema::hasTable('gymies_reviews')) {
            return response()->json(['data' => ['has_review' => false]]);
        }
        $review = DB::table('gymies_reviews')->where('booking_id', (int) $id)->first(['id', 'rating', 'review_text', 'created_at']);
        if (!$review) {
            return response()->json(['data' => ['has_review' => false]]);
        }
        $responseText = null;
        if (Schema::hasTable('gymies_review_responses')) {
            $resp = DB::table('gymies_review_responses')->where('review_id', (int) $review->id)->first(['body', 'created_at']);
            $responseText = $resp ? (string) $resp->body : null;
        }
        return response()->json([
            'data' => [
                'has_review' => true,
                'review_id' => (string) $review->id,
                'rating' => (int) $review->rating,
                'review_text' => $review->review_text ? (string) $review->review_text : null,
                'review_created_at' => $review->created_at,
                'response_text' => $responseText,
            ],
        ]);
    }

    /**
     * Trainer: reageren op een beoordeling (één reactie per beoordeling).
     */
    public function storeReviewResponse(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen reageren op een beoordeling.'], 403);
        }
        $request->validate([
            'response_text' => 'required|string|max:2000',
        ]);
        $booking = DB::table('gymies_bookings')->where('id', $id)->first(['id', 'trainer_user_id', 'status']);
        if (!$booking || (int) $booking->trainer_user_id !== (int) $user->id) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if (!Schema::hasTable('gymies_reviews')) {
            return response()->json(['message' => 'Beoordelingen zijn nog niet beschikbaar.'], 503);
        }
        $review = DB::table('gymies_reviews')->where('booking_id', (int) $id)->first(['id']);
        if (!$review) {
            return response()->json(['message' => 'Er is nog geen beoordeling voor deze boeking.'], 422);
        }
        if (!Schema::hasTable('gymies_review_responses')) {
            return response()->json(['message' => 'Reacties op beoordelingen zijn nog niet beschikbaar.'], 503);
        }
        $body = trim((string) $request->input('response_text'));
        $existing = DB::table('gymies_review_responses')->where('review_id', (int) $review->id)->first();
        if ($existing) {
            DB::table('gymies_review_responses')->where('id', $existing->id)->update(['body' => $body]);
        } else {
            DB::table('gymies_review_responses')->insert([
                'review_id' => (int) $review->id,
                'trainer_user_id' => (int) $user->id,
                'body' => $body,
                'created_at' => now(),
            ]);
        }
        return response()->json([
            'message' => 'Je reactie is geplaatst.',
            'data' => ['response_text' => $body],
        ]);
    }

    public function trainerSummary(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers hebben toegang tot dit overzicht.'], 403);
        }

        $trainerId = (int) $user->id;
        $now = now();
        $weekStart = $now->copy()->startOfWeek();
        $weekEnd = $now->copy()->endOfWeek();

        $counts = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->selectRaw("SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending_count")
            ->selectRaw("SUM(CASE WHEN status = 'confirmed' AND scheduled_at >= ? THEN 1 ELSE 0 END) AS upcoming_count", [$now])
            ->selectRaw("SUM(CASE WHEN status = 'confirmed' AND scheduled_at BETWEEN ? AND ? THEN 1 ELSE 0 END) AS this_week_count", [$weekStart, $weekEnd])
            ->selectRaw("SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_count")
            ->first();

        $revenue = (int) (DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereIn('status', ['completed', 'confirmed'])
            ->whereNotNull('paid_at')
            ->sum('amount_cents') ?? 0);

        $upcomingRows = DB::table('gymies_bookings as b')
            ->join('gymies_users as client', 'b.client_user_id', '=', 'client.id')
            ->where('b.trainer_user_id', $trainerId)
            ->whereIn('b.status', ['pending', 'confirmed'])
            ->where('b.scheduled_at', '>=', $now)
            ->orderBy('b.scheduled_at')
            ->limit(10)
            ->select(
                'b.id',
                'b.client_user_id',
                'b.trainer_user_id',
                'b.scheduled_at',
                'b.duration_minutes',
                'b.status',
                'b.amount_cents',
                'b.paid_at',
                'client.display_name as client_name'
            )
            ->get();

        $upcoming = $upcomingRows->map(fn ($r) => [
            'id' => (string) $r->id,
            'client_user_id' => (string) $r->client_user_id,
            'trainer_user_id' => (string) $r->trainer_user_id,
            'trainer_name' => $user->display_name ?? $user->email,
            'client_name' => $r->client_name ?? 'Klant',
            'scheduled_at' => $r->scheduled_at,
            'duration_minutes' => (int) $r->duration_minutes,
            'status' => $r->status,
            'amount_cents' => $r->amount_cents ? (int) $r->amount_cents : null,
            'paid_at' => $r->paid_at,
        ])->all();

        return response()->json([
            'data' => [
                'pending_count' => (int) ($counts->pending_count ?? 0),
                'upcoming_count' => (int) ($counts->upcoming_count ?? 0),
                'this_week_count' => (int) ($counts->this_week_count ?? 0),
                'completed_count' => (int) ($counts->completed_count ?? 0),
                'revenue_cents' => $revenue,
                'upcoming_bookings' => $upcoming,
            ],
        ]);
    }

    private function respondBookingById(int $bookingId): JsonResponse
    {
        $hasOrganisationId = DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'organisation_id');
        $hasPayoutRoute = DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'payout_route');
        $select = [
            'b.id',
            'b.client_user_id',
            'b.trainer_user_id',
            'b.scheduled_at',
            'b.duration_minutes',
            'b.status',
            'b.amount_cents',
            'b.paid_at',
            'trainer.display_name as trainer_name',
            'client.display_name as client_name',
        ];
        if ($hasOrganisationId) {
            $select[] = 'b.organisation_id';
        }
        if ($hasPayoutRoute) {
            $select[] = 'b.payout_route';
        }
        if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'location_type')) {
            $select[] = 'b.location_type';
            $select[] = 'b.location_notes';
        }
        if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'confirmation_note')) {
            $select[] = 'b.confirmation_note';
        }
        if (Schema::hasColumn('gymies_bookings', 'proposed_scheduled_at')) {
            $select[] = 'b.proposed_scheduled_at';
            $select[] = 'b.proposed_duration_minutes';
        }
        if (Schema::hasColumn('gymies_bookings', 'proposed_by_user_id')) {
            $select[] = 'b.proposed_by_user_id';
        }
        if (Schema::hasColumn('gymies_bookings', 'proposed_at')) {
            $select[] = 'b.proposed_at';
        }
        $hasPackageId = Schema::hasColumn('gymies_bookings', 'package_id');
        if ($hasPackageId) {
            $select[] = 'b.package_id';
            $select[] = 'b.sessions_remaining';
        }
        if (Schema::hasColumn('gymies_bookings', 'payment_method')) {
            $select[] = 'b.payment_method';
        }

        $bookingQuery = DB::table('gymies_bookings as b')
            ->join('gymies_users as trainer', 'b.trainer_user_id', '=', 'trainer.id')
            ->join('gymies_users as client', 'b.client_user_id', '=', 'client.id');
        if ($hasPackageId && Schema::hasTable('gymies_packages')) {
            $bookingQuery->leftJoin('gymies_packages as pkg', 'b.package_id', '=', 'pkg.id');
            $select[] = 'pkg.name as package_name';
        }
        $row = $bookingQuery->where('b.id', $bookingId)->select(...$select)->first();
        if (!$row) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if (property_exists($row, 'proposed_scheduled_at') && $row->proposed_scheduled_at !== null && property_exists($row, 'proposed_at') && $row->proposed_at !== null) {
            $this->maybeExpireRescheduleProposal($row);
            $refetch = DB::table('gymies_bookings as b')
                ->join('gymies_users as trainer', 'b.trainer_user_id', '=', 'trainer.id')
                ->join('gymies_users as client', 'b.client_user_id', '=', 'client.id');
            if ($hasPackageId && Schema::hasTable('gymies_packages')) {
                $refetch->leftJoin('gymies_packages as pkg', 'b.package_id', '=', 'pkg.id');
            }
            $row = $refetch->where('b.id', $bookingId)->select(...$select)->first();
            if (!$row) {
                return response()->json(['message' => 'Boeking niet gevonden.'], 404);
            }
        }

        $res = [
            'id' => (string) $row->id,
            'client_user_id' => (string) $row->client_user_id,
            'trainer_user_id' => (string) $row->trainer_user_id,
            'trainer_name' => $row->trainer_name ?? 'Trainer',
            'client_name' => $row->client_name ?? 'Klant',
            'scheduled_at' => $row->scheduled_at,
            'duration_minutes' => (int) $row->duration_minutes,
            'status' => $row->status,
            'amount_cents' => $row->amount_cents ? (int) $row->amount_cents : null,
            'paid_at' => $row->paid_at,
            'organisation_id' => property_exists($row, 'organisation_id') && $row->organisation_id ? (string) $row->organisation_id : null,
            'payout_route' => property_exists($row, 'payout_route') ? ($row->payout_route ?? 'direct_trainer') : 'direct_trainer',
        ];
        if (property_exists($row, 'location_type')) {
            $res['location_type'] = $row->location_type ? (string) $row->location_type : null;
            $res['location_notes'] = $row->location_notes ? (string) $row->location_notes : null;
        }
        if (property_exists($row, 'confirmation_note')) {
            $res['confirmation_note'] = $row->confirmation_note ? (string) $row->confirmation_note : null;
        }
        if (property_exists($row, 'proposed_scheduled_at') && $row->proposed_scheduled_at !== null) {
            $res['proposed_scheduled_at'] = $row->proposed_scheduled_at;
            $res['proposed_duration_minutes'] = $row->proposed_duration_minutes !== null ? (int) $row->proposed_duration_minutes : null;
            if (property_exists($row, 'proposed_by_user_id')) {
                $res['proposed_by_user_id'] = $row->proposed_by_user_id ? (string) $row->proposed_by_user_id : null;
            }
            if (property_exists($row, 'proposed_at')) {
                $res['proposed_at'] = $row->proposed_at;
                $deadline = $row->proposed_at ? Carbon::parse($row->proposed_at)->addHours(24) : null;
                $res['proposed_response_deadline'] = $deadline?->toIso8601String();
                $res['proposal_expired'] = $deadline && now()->greaterThan($deadline);
            }
        }
        if (property_exists($row, 'package_id') && $row->package_id !== null) {
            $res['package_id'] = (string) $row->package_id;
            $res['package_name'] = isset($row->package_name) ? (string) $row->package_name : null;
            $res['sessions_remaining'] = $row->sessions_remaining !== null ? (int) $row->sessions_remaining : null;
        }
        if (property_exists($row, 'payment_method') && $row->payment_method !== null) {
            $res['payment_method'] = (string) $row->payment_method;
        }
        return response()->json(['data' => $res]);
    }

    private function insertStatusNotifications(int $bookingId, int $clientId, int $trainerId, string $eventType): void
    {
        $payloadForClient = json_encode([
            'booking_id' => (string) $bookingId,
            'event_type' => $eventType,
        ], JSON_UNESCAPED_UNICODE);
        $payloadForTrainer = json_encode([
            'booking_id' => (string) $bookingId,
            'event_type' => $eventType,
        ], JSON_UNESCAPED_UNICODE);

        DB::table('gymies_notification_queue')->insert([
            [
                'user_id' => $clientId,
                'channel' => 'in_app',
                'event_type' => $eventType . '_for_client',
                'payload_json' => $payloadForClient,
                'scheduled_for' => now(),
                'created_at' => now(),
            ],
            [
                'user_id' => $trainerId,
                'channel' => 'in_app',
                'event_type' => $eventType . '_for_trainer',
                'payload_json' => $payloadForTrainer,
                'scheduled_for' => now(),
                'created_at' => now(),
            ],
        ]);
    }

    private function validateRequestedSlot(string $scheduledAt, int $duration): ?JsonResponse
    {
        if (!in_array($duration, self::ALLOWED_DURATIONS, true)) {
            return response()->json([
                'message' => 'Ongeldige duur. Toegestaan: 45, 60, 90 of 120 minuten.',
            ], 422);
        }

        try {
            $start = Carbon::parse($scheduledAt);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Ongeldige datum/tijd.'], 422);
        }

        if ($start->second !== 0 || ($start->minute % 15) !== 0) {
            return response()->json([
                'message' => 'Starttijd moet op een kwartiergrens liggen (bijv. 10:00, 10:15, 10:30, 10:45).',
            ], 422);
        }

        $minStart = now()->addMinutes(self::LEAD_TIME_MINUTES);
        if ($start->lt($minStart)) {
            return response()->json([
                'message' => 'Boek minimaal 2 uur van tevoren.',
            ], 422);
        }

        $maxStart = now()->addDays(self::MAX_BOOKING_DAYS_AHEAD);
        if ($start->gt($maxStart)) {
            return response()->json([
                'message' => 'Deze datum ligt te ver in de toekomst.',
            ], 422);
        }

        return null;
    }

    private function getTrainerLeadTimeMinutes(int $trainerId): int
    {
        if (!Schema::hasTable('gymies_trainer_profiles') || !Schema::hasColumn('gymies_trainer_profiles', 'lead_time_minutes')) {
            return self::DEFAULT_LEAD_TIME_MINUTES;
        }
        $profile = DB::table('gymies_trainer_profiles')
            ->where('user_id', $trainerId)
            ->value('lead_time_minutes');
        return $profile !== null ? (int) $profile : self::DEFAULT_LEAD_TIME_MINUTES;
    }

    /**
     * Max dagen vooruit boekbaar per trainer; NULL in DB = platformdefault.
     */
    private function getTrainerMaxBookingDaysAhead(int $trainerId): int
    {
        if (!Schema::hasTable('gymies_trainer_profiles')
            || !Schema::hasColumn('gymies_trainer_profiles', 'booking_max_days_ahead')) {
            return self::MAX_BOOKING_DAYS_AHEAD;
        }
        $v = DB::table('gymies_trainer_profiles')
            ->where('user_id', $trainerId)
            ->value('booking_max_days_ahead');
        if ($v === null) {
            return self::MAX_BOOKING_DAYS_AHEAD;
        }
        $days = (int) $v;
        if ($days < 1) {
            return 1;
        }
        if ($days > 365) {
            return 365;
        }
        return min($days, self::MAX_BOOKING_DAYS_AHEAD);
    }

    private function validateRequestedSlotWithLeadTime(
        string $scheduledAt,
        int $duration,
        int $leadTimeMinutes,
        ?int $maxDaysAhead = null,
    ): ?JsonResponse
    {
        if (!in_array($duration, self::ALLOWED_DURATIONS, true)) {
            return response()->json(['message' => 'Ongeldige duur. Toegestaan: 45, 60, 90 of 120 minuten.'], 422);
        }
        try {
            $start = Carbon::parse($scheduledAt);
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Ongeldige datum/tijd.'], 422);
        }
        if ($start->second !== 0 || ($start->minute % 15) !== 0) {
            return response()->json([
                'message' => 'Starttijd moet op een kwartiergrens liggen (bijv. 10:00, 10:15, 10:30, 10:45).',
            ], 422);
        }
        $minStart = now()->addMinutes($leadTimeMinutes);
        if ($start->lt($minStart)) {
            if ($leadTimeMinutes < 60) {
                $leadLabel = "{$leadTimeMinutes} minuten";
            } elseif ($leadTimeMinutes % 60 === 0) {
                $h = (int) ($leadTimeMinutes / 60);
                $leadLabel = $h === 1 ? '1 uur' : "{$h} uur";
            } else {
                $h = intdiv($leadTimeMinutes, 60);
                $m = $leadTimeMinutes % 60;
                $leadLabel = $h > 0 ? "{$h} uur en {$m} minuten" : "{$m} minuten";
            }
            return response()->json([
                'message' => "Boek minimaal {$leadLabel} van tevoren (direct boekbaar vanaf " . $minStart->format('d-m-Y H:i') . ').',
            ], 422);
        }
        $daysAhead = $maxDaysAhead ?? self::MAX_BOOKING_DAYS_AHEAD;
        $maxStart = now()->addDays($daysAhead)->endOfDay();
        if ($start->gt($maxStart)) {
            return response()->json([
                'message' => "Deze trainer laat niet verder dan {$daysAhead} dagen vooruit boeken.",
            ], 422);
        }

        return null;
    }

    private function hasConfirmedOverlap(int $trainerId, string $scheduledAt, int $duration, int $excludeBookingId = 0): bool
    {
        $query = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('status', 'confirmed')
            ->whereRaw("? < DATE_ADD(scheduled_at, INTERVAL duration_minutes MINUTE) AND DATE_ADD(?, INTERVAL ? MINUTE) > scheduled_at", [
                $scheduledAt,
                $scheduledAt,
                $duration,
            ]);
        if ($excludeBookingId > 0) {
            $query->where('id', '!=', $excludeBookingId);
        }

        return $query->exists();
    }

    /**
     * Of er al een pending of confirmed boeking is voor dit slot (double-entry preventie).
     */
    private function hasPendingOrConfirmedOverlap(int $trainerId, string $scheduledAt, int $duration, int $excludeBookingId = 0): bool
    {
        return $this->hasPendingConfirmedOrReservedOverlap($trainerId, $scheduledAt, $duration, $excludeBookingId);
    }

    /**
     * Pending, confirmed of reserved (met geldige reserved_until) overlap – Direct Boeken.
     */
    private function hasPendingConfirmedOrReservedOverlap(int $trainerId, string $scheduledAt, int $duration, int $excludeBookingId = 0, bool $lockForUpdate = false): bool
    {
        $query = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereRaw("? < DATE_ADD(scheduled_at, INTERVAL duration_minutes MINUTE) AND DATE_ADD(?, INTERVAL ? MINUTE) > scheduled_at", [
                $scheduledAt,
                $scheduledAt,
                $duration,
            ]);
        if ($excludeBookingId > 0) {
            $query->where('id', '!=', $excludeBookingId);
        }
        $hasReservedCol = Schema::hasColumn('gymies_bookings', 'reserved_until');
        if ($hasReservedCol) {
            $query->where(function ($q) {
                $q->whereIn('status', ['pending', 'confirmed'])
                    ->orWhere(function ($q2) {
                        $q2->where('status', 'reserved')
                            ->where(function ($q3) {
                                $q3->whereNull('reserved_until')->orWhere('reserved_until', '>', now());
                            });
                    });
            });
        } else {
            $query->whereIn('status', ['pending', 'confirmed', 'reserved']);
        }

        // lockForUpdate: vergrendel de gevonden rijen zodat gelijktijdige transacties wachten.
        // Essentieel bij Direct Boeken om dubbele reservering van hetzelfde tijdslot te voorkomen.
        if ($lockForUpdate) {
            // exists() ondersteunt geen lockForUpdate; gebruik count() met sharedLock/lockForUpdate
            return $query->lockForUpdate()->count() > 0;
        }

        return $query->exists();
    }

    /**
     * @param array<string,mixed>|null $oldValues
     * @param array<string,mixed>|null $newValues
     */
    private function logAudit(int $userId, string $action, string $entityType, int $entityId, ?array $oldValues, ?array $newValues): void
    {
        if (!DB::getSchemaBuilder()->hasTable('gymies_audit_log')) {
            return;
        }

        // S-100: Audit Log Injection — sanitize arrays before json_encode to prevent object-reference injection
        $safeOld = null;
        if ($oldValues !== null) {
            $safeOld = json_decode(json_encode($oldValues, JSON_PARTIAL_OUTPUT_ON_ERROR), true);
        }
        $safeNew = null;
        if ($newValues !== null) {
            $safeNew = json_decode(json_encode($newValues, JSON_PARTIAL_OUTPUT_ON_ERROR), true);
        }

        DB::table('gymies_audit_log')->insert([
            'user_id' => $userId,
            'action' => $action,
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'old_values' => $safeOld ? json_encode($safeOld, JSON_UNESCAPED_UNICODE) : null,
            'new_values' => $safeNew ? json_encode($safeNew, JSON_UNESCAPED_UNICODE) : null,
            'ip_address' => request()->ip(),
            'created_at' => now(),
        ]);
    }

    /**
     * Ghost-Rating: klant stuurt 3 emoji-scores in na sessie.
     */
    public function submitGhostRating(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }
        if (!Schema::hasTable('gymies_ghost_ratings')) {
            return response()->json(['message' => 'Ghost-rating niet beschikbaar. Draai migratie.'], 503);
        }

        $booking = DB::table('gymies_bookings')->where('id', (int) $id)->first();
        if (!$booking || (int) $booking->client_user_id !== (int) $user->id) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if ($booking->status !== 'completed') {
            return response()->json(['message' => 'Alleen voltooide sessies kunnen een ghost-rating krijgen.'], 422);
        }

        $existing = DB::table('gymies_ghost_ratings')->where('booking_id', (int) $id)->first();
        if ($existing) {
            return response()->json(['message' => 'Je hebt deze sessie al beoordeeld.'], 422);
        }

        $request->validate([
            'punctuality' => 'required|integer|min:1|max:3',
            'energy' => 'required|integer|min:1|max:3',
            'would_rebook' => 'required|integer|min:1|max:3',
        ]);

        DB::table('gymies_ghost_ratings')->insert([
            'booking_id' => (int) $id,
            'client_user_id' => (int) $user->id,
            'trainer_user_id' => (int) $booking->trainer_user_id,
            'punctuality' => (int) $request->input('punctuality'),
            'energy' => (int) $request->input('energy'),
            'would_rebook' => (int) $request->input('would_rebook'),
            'created_at' => now(),
        ]);

        return response()->json(['ok' => true, 'message' => 'Bedankt voor je feedback!']);
    }

    /** Prefix voor gestructureerde chat-kaarten (Flutter parseert JSON erachter). */
    private const CARD_PREFIX = '__GYMIES_CARD__:';

    /**
     * Na reschedule-request: één kaart in de chat-thread zodat de andere partij in-app kan akkoord/afwijzen
     * (retentie; geen WhatsApp-uitstap). Body = CARD_PREFIX + JSON.
     */
    private function injectRescheduleCardMessage(
        int $bookingId,
        object $booking,
        object $proposerUser,
        string $newScheduledAt,
        int $newDuration,
    ): void {
        if (!Schema::hasTable('gymies_conversations') || !Schema::hasTable('gymies_messages')) {
            return;
        }
        $clientId = (int) $booking->client_user_id;
        $trainerId = (int) $booking->trainer_user_id;
        $conv = DB::table('gymies_conversations')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->orderByDesc('id')
            ->first();
        if ($conv === null) {
            $convId = DB::table('gymies_conversations')->insertGetId([
                'client_user_id' => $clientId,
                'trainer_user_id' => $trainerId,
                'booking_id' => $bookingId,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        } else {
            $convId = (int) $conv->id;
        }
        $payload = [
            'type' => 'reschedule',
            'booking_id' => (string) $bookingId,
            'trainer_user_id' => (string) $trainerId,
            'state' => 'pending',
            'scheduled_at' => (string) $booking->scheduled_at,
            'proposed_scheduled_at' => $newScheduledAt,
            'proposed_by_user_id' => (string) $proposerUser->id,
            'duration_minutes' => $newDuration,
        ];
        $body = self::CARD_PREFIX . json_encode($payload, JSON_UNESCAPED_UNICODE);
        $messageId = DB::table('gymies_messages')->insertGetId([
            'conversation_id' => $convId,
            'from_user_id' => $proposerUser->id,
            'body' => $body,
            'created_at' => now(),
        ]);
        DB::table('gymies_conversations')->where('id', $convId)->update(['updated_at' => now()]);
        if (class_exists(\App\Helpers\GymiesChatBroadcast::class)) {
            \App\Helpers\GymiesChatBroadcast::afterMessageInserted((string) $convId, (int) $messageId, (int) $proposerUser->id, $body);
        }
    }

    /**
     * Na accept/reject: bestaande pending-kaart voor deze boeking in dezelfde conversatie bijwerken
     * zodat de UI "Geregeld" / "Afgewezen" kan tonen zonder nieuw bericht.
     */
    private function updateRescheduleCardState(int $bookingId, string $state): void
    {
        if (!Schema::hasTable('gymies_messages') || !Schema::hasTable('gymies_conversations')) {
            return;
        }
        $booking = DB::table('gymies_bookings')->where('id', $bookingId)->first();
        if ($booking === null) {
            return;
        }
        $clientId = (int) $booking->client_user_id;
        $trainerId = (int) $booking->trainer_user_id;
        $prefix = self::CARD_PREFIX;
        $rows = DB::table('gymies_messages as m')
            ->join('gymies_conversations as c', 'c.id', '=', 'm.conversation_id')
            ->where('c.client_user_id', $clientId)
            ->where('c.trainer_user_id', $trainerId)
            ->where('m.body', 'like', $prefix . '%')
            ->orderByDesc('m.id')
            ->limit(80)
            ->get(['m.id', 'm.body']);
        foreach ($rows as $row) {
            $raw = substr((string) $row->body, strlen($prefix));
            $json = json_decode($raw, true);
            if (!is_array($json) || ($json['type'] ?? '') !== 'reschedule') {
                continue;
            }
            if ((string) ($json['booking_id'] ?? '') !== (string) $bookingId) {
                continue;
            }
            if (($json['state'] ?? '') !== 'pending') {
                continue;
            }
            $json['state'] = $state;
            $json['resolved_at'] = now()->toIso8601String();
            $newBody = $prefix . json_encode($json, JSON_UNESCAPED_UNICODE);
            DB::table('gymies_messages')->where('id', $row->id)->update(['body' => $newBody]);
            break;
        }
    }
}
