-- Performance indexes voor veelgebruikte queries.
-- Run eenmalig. Bij "Duplicate key name" bestaat de index al – negeer.
-- Bron: P1-verbeterpunten (bookings, sessions, messages, notification_queue).

-- Bookings: trainer + datum + status (agenda, rapportages)
ALTER TABLE gymies_bookings
  ADD INDEX gymies_bookings_trainer_scheduled_status (trainer_user_id, scheduled_at, status);

-- Bookings: client + datum (mijn boekingen)
ALTER TABLE gymies_bookings
  ADD INDEX gymies_bookings_client_scheduled (client_user_id, scheduled_at);

-- Bookings: package + client (low-credit cron, used count)
ALTER TABLE gymies_bookings
  ADD INDEX gymies_bookings_package_client_status (package_id, client_user_id, status);

-- Messages: conversation + created_at (chat chronologisch)
ALTER TABLE gymies_messages
  ADD INDEX gymies_messages_conversation_created (conversation_id, created_at);

-- Notification queue: user + event_type + created_at (dedup upsell)
ALTER TABLE gymies_notification_queue
  ADD INDEX gymies_notification_queue_user_event_created (user_id, event_type, created_at);
