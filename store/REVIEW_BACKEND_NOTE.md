# Review backend – is_anonymous

De Flutter-app stuurt bij `POST bookings/{id}/review` nu ook `is_anonymous: true/false`.

**GymiesBookingController::storeReview** moet dit veld accepteren en opslaan in `gymies_booking_reviews`:

```php
$request->validate([
    'rating' => 'required|integer|min:1|max:5',
    'message' => 'nullable|string|max:2000',
    'is_anonymous' => 'boolean',
]);
// ...
'is_anonymous' => $request->boolean('is_anonymous', false),
```

De migratie `2025_03_15_000000_create_gymies_booking_reviews_table.php` voegt de tabel en kolom toe.
