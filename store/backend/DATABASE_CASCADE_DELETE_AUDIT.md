# Gymies Cascade Delete & Referential Integrity Audit

## Overview
This document defines the cascade delete behavior for all critical operations in the Gymies app.
All database foreign keys MUST be configured with appropriate ON DELETE actions.

**CRITICAL FIX-AUD-006:** This audit ensures data consistency when:
- Users delete their accounts
- Trainers are deactivated
- Bookings are cancelled
- Organizations are deleted

---

## 1. USER ACCOUNT DELETION

### Scenario
User initiates account deletion via app or admin action.

### Cascade Operations Required

#### a) Bookings Table
```sql
-- FIX-AUD-006a: All bookings by/with user must be soft-deleted or cancelled
ALTER TABLE bookings ADD CONSTRAINT fk_bookings_client_id 
  FOREIGN KEY (client_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE bookings ADD CONSTRAINT fk_bookings_trainer_id 
  FOREIGN KEY (trainer_id) REFERENCES users(id) ON DELETE CASCADE;

-- Action on delete:
-- - All bookings where client_id = user_id → status = 'cancelled'
-- - All bookings where trainer_id = user_id → status = 'cancelled'
-- - Send cancellation notification to other party
-- - Refund payments if applicable
-- - Remove from waitlists
```

#### b) Messages & Conversations
```sql
-- FIX-AUD-006b: Delete or anonymize all messages/conversations
ALTER TABLE conversations ADD CONSTRAINT fk_conversations_user_id 
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE messages ADD CONSTRAINT fk_messages_sender_id 
  FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE;

-- Action on delete:
-- - Delete all conversations involving user
-- - Delete all messages sent by user (or anonymize)
-- - Remove any draft messages
```

#### c) Favorites & Reviews
```sql
-- FIX-AUD-006c: Remove user from favorites and anonymize reviews
ALTER TABLE favorites ADD CONSTRAINT fk_favorites_user_id 
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE favorites ADD CONSTRAINT fk_favorites_trainer_id 
  FOREIGN KEY (trainer_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE reviews ADD CONSTRAINT fk_reviews_reviewer_id 
  FOREIGN KEY (reviewer_id) REFERENCES users(id) ON DELETE CASCADE;

-- Action on delete:
-- - Delete all favorites where user is favoriter
-- - Delete all favorites where user (trainer) is favorited
-- - Anonymize or delete reviews left by user
-- - Anonymize or delete reviews about user
```

#### d) Device Tokens & Push Notifications
```sql
-- FIX-AUD-006d: Clean up all device tokens and notification subscriptions
ALTER TABLE device_tokens ADD CONSTRAINT fk_device_tokens_user_id 
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE notification_subscriptions ADD CONSTRAINT fk_notif_subs_user_id 
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- Action on delete:
-- - Delete all device tokens for user
-- - Delete all notification subscriptions
-- - Cancel any pending notifications in queue
```

#### e) Profile & Storefront
```sql
-- FIX-AUD-006e: Delete profile data and hide storefront
ALTER TABLE profiles ADD CONSTRAINT fk_profiles_user_id 
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE storefronts ADD CONSTRAINT fk_storefronts_trainer_id 
  FOREIGN KEY (trainer_id) REFERENCES users(id) ON DELETE CASCADE;

-- Action on delete:
-- - Delete all profile data (bio, avatar, social links)
-- - Mark storefront as deleted/hidden from search
-- - Preserve but hide availability calendar
```

#### f) Subscriptions & Memberships
```sql
-- FIX-AUD-006f: Cancel active subscriptions
ALTER TABLE subscriptions ADD CONSTRAINT fk_subscriptions_user_id 
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- Action on delete:
-- - Cancel all active subscriptions (status = 'active' → 'cancelled')
-- - Refund remaining balance if applicable
-- - Remove from auto-renew queues
```

#### g) Payment Records (DO NOT CASCADE)
```sql
-- FIX-AUD-006g: PRESERVE payment records for audit trail
-- CRITICAL: DO NOT cascade delete payments - keep for financial audit

ALTER TABLE payments ADD CONSTRAINT fk_payments_user_id 
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT;

-- Manual handling in user delete controller:
-- - Anonymize payment_metadata (name, email, address)
-- - Keep transaction IDs and amounts (audit trail)
-- - Keep payment date timestamps
```

---

## 2. TRAINER DEACTIVATION BY ADMIN

### Scenario
Admin deactivates a trainer account (not full deletion - preserve bookings for history).

### Cascade Operations Required

```sql
-- FIX-AUD-006h: Deactivate trainer-specific features, don't delete
ALTER TABLE trainers ADD is_active BOOLEAN DEFAULT true;

-- Action on deactivate:
-- - is_active = false (soft delete, preserve data)
-- - All FUTURE bookings (start_date > now()) → status = 'cancelled'
-- - All PAST bookings (start_date <= now()) → keep as-is (history)
-- - Send cancellation notice to clients with future bookings
-- - Hide storefront from search (but keep data)
-- - Cancel active subscriptions offered by trainer
-- - Pause availability calendar
```

---

## 3. BOOKING CANCELLATION

### Scenario
Client or trainer cancels a booking.

### Cascade Operations Required

```sql
-- FIX-AUD-006i: Handle all side effects of cancellation
ALTER TABLE bookings ADD status ENUM('pending', 'confirmed', 'cancelled', 'completed', 'no_show');

-- Action on cancel:
-- - status = 'cancelled' + cancelled_at = now()
-- - If payment exists: initiate refund
-- - Remove from waitlist (if queued)
-- - Restore trainer's availability slot
-- - Notify both client and trainer
-- - Mark booking as non-reviewable (WHERE booking_id = ? → reviews deleted)
-- - Update trainer's calendar

-- FIX-AUD-006j: Prevent reviews on cancelled bookings
ALTER TABLE reviews ADD CONSTRAINT fk_reviews_booking_id 
  FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE;

-- When booking is cancelled:
-- - Delete any existing reviews
-- - Prevent review submission in app UI
```

---

## 4. ORGANIZATION / GYM DELETION

### Scenario
Admin or organization owner deletes entire organization (e.g., gym closure).

### Cascade Operations Required

```sql
-- FIX-AUD-006k: Cascade all org-related data
ALTER TABLE locations ADD CONSTRAINT fk_locations_org_id 
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;

ALTER TABLE team_members ADD CONSTRAINT fk_team_members_org_id 
  FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;

ALTER TABLE gym_equipment ADD CONSTRAINT fk_equipment_gym_id 
  FOREIGN KEY (gym_id) REFERENCES gyms(id) ON DELETE CASCADE;

-- Action on delete:
-- - Delete all locations under this organization
-- - Delete all team members (or mark deleted + unlink from org)
-- - Delete all inventory/equipment
-- - Cancel all active group sessions at this gym
-- - Cancel all client bookings at this gym
-- - Notify affected trainers and clients
-- - Hide from search/directory
```

---

## 5. REFERENTIAL INTEGRITY ENFORCEMENT

### Rules for All Foreign Keys

1. **Timestamp-based soft deletes** (preferred):
   ```sql
   ALTER TABLE table_name ADD deleted_at TIMESTAMP NULL;
   -- Check: WHERE deleted_at IS NULL
   -- Benefit: preserves audit trail
   ```

2. **Hard deletes with CASCADE**:
   ```sql
   ALTER TABLE child_table 
     FOREIGN KEY (parent_id) REFERENCES parent_table(id) ON DELETE CASCADE;
   -- Use ONLY for data that has no audit/compliance need
   ```

3. **RESTRICT (prevent orphans)**:
   ```sql
   ALTER TABLE child_table 
     FOREIGN KEY (parent_id) REFERENCES parent_table(id) ON DELETE RESTRICT;
   -- Use for critical data (payments, audit logs, financial records)
   ```

---

## 6. IMPLEMENTATION CHECKLIST

- [ ] All foreign keys defined with explicit ON DELETE action
- [ ] User delete handler cascades all 7 categories (bookings, messages, favorites, reviews, tokens, profile, subscriptions)
- [ ] Payment table has ON DELETE RESTRICT (no cascade)
- [ ] Booking cancellation handler updates related tables
- [ ] Trainer deactivation uses soft delete (not hard delete)
- [ ] Organization deletion cascades to locations, members, equipment
- [ ] All delete operations log changes to audit table
- [ ] Notification system queues messages BEFORE deletions occur
- [ ] Refund logic executes BEFORE payment records modified
- [ ] Database migrations tested with sample data

---

## 7. MIGRATION TEMPLATE

```php
// Create foreign key with CASCADE
Schema::table('bookings', function (Blueprint $table) {
    $table->foreign('client_id')
        ->references('id')->on('users')
        ->onDelete('cascade');
    
    $table->foreign('trainer_id')
        ->references('id')->on('users')
        ->onDelete('cascade');
});

// Soft delete example
Schema::table('profiles', function (Blueprint $table) {
    $table->softDeletes();
});

// Audit logging
Schema::table('users', function (Blueprint $table) {
    $table->timestamp('deleted_at')->nullable();
    $table->text('deletion_reason')->nullable();
});
```

---

## 8. CONTROLLER DELETE LOGIC PATTERN

```php
// User deletion controller
class UserDeleteController {
    public function destroy(User $user) {
        DB::transaction(function () use ($user) {
            // 1. Queue notifications FIRST (before any deletions)
            $this->notifyAffectedParties($user);
            
            // 2. Handle refunds SECOND (before payment records change)
            $this->processRefunds($user);
            
            // 3. Cancel bookings
            Booking::where('client_id', $user->id)
                ->orWhere('trainer_id', $user->id)
                ->update(['status' => 'cancelled', 'cancelled_at' => now()]);
            
            // 4. Delete child records (will cascade via FK)
            $user->messages()->delete();
            $user->favorites()->delete();
            $user->reviews()->delete();
            $user->deviceTokens()->delete();
            
            // 5. Soft delete user (preserve audit trail)
            $user->delete();
        });
    }
}
```

---

## Status: IN PROGRESS
- [ ] FIX-AUD-006 - Audit all cascade delete configurations
- [ ] FIX-AUD-006a - Booking cancellation on user delete
- [ ] FIX-AUD-006b - Message deletion on user delete
- [ ] FIX-AUD-006c - Review/favorite cleanup on user delete
- [ ] FIX-AUD-006d - Device token cleanup on user delete
- [ ] FIX-AUD-006e - Profile/storefront cleanup on user delete
- [ ] FIX-AUD-006f - Subscription cancellation on user delete
- [ ] FIX-AUD-006g - Payment records preservation (RESTRICT, not CASCADE)
- [ ] FIX-AUD-006h - Trainer deactivation (soft delete, future bookings cancelled)
- [ ] FIX-AUD-006i - Booking cancellation (refunds, notifications, review prevention)
- [ ] FIX-AUD-006j - Review deletion on booking cancellation
- [ ] FIX-AUD-006k - Organization deletion cascades all child records
