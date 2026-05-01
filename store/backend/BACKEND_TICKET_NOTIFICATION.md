# Ticket afgehandeld – notificatie naar klant/trainer

Wanneer een medewerker een ticket op **Afgehandeld** zet in het admin berichtencentrum, moet de klant of trainer een melding ontvangen in het meldingencentrum.

## Implementatie

1. **Helper bestand**  
   `app/Http/Controllers/Gymies/TicketClosedNotificationHelper.php` is toegevoegd.  
   Deze roept `TicketClosedNotificationHelper::notifyTicketOwner($ticketId, $userId, $notifiableType)` aan.

2. **Integratie in GymiesAdminController::updateTicket**

   In de `updateTicket`-methode, na het succesvol updaten van de ticketstatus naar `closed`:

   ```php
   use App\Http\Controllers\Gymies\TicketClosedNotificationHelper;

   public function updateTicket(Request $request, $ticketId)
   {
       $updates = $request->all();
       $newStatus = $updates['status'] ?? null;

       // ... bestaande logica om ticket te updaten ...

       if ($newStatus === 'closed') {
           $ticket = /* haal ticket op met user_id */;
           $userId = (int) ($ticket->user_id ?? $ticket->author_id ?? 0);
           if ($userId > 0) {
               TicketClosedNotificationHelper::notifyTicketOwner(
                   $ticketId,
                   $userId,
                   'App\Models\User'  // of de juiste notifiable_type voor jouw User model
               );
           }
       }

       return response()->json([...]);
   }
   ```

3. **Meldingstekst**  
   De klant/trainer ziet in het meldingencentrum:
   > **Ticket afgehandeld**  
   > Je ticket met ticket id : [id] is afgehandeld door Gymies

4. **Veldnamen**  
   Zorg dat de ticket-query `user_id` of `author_id` teruggeeft (de eigenaar van het ticket).
