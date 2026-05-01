-- ============================================================
-- Demo-account: demo@gymies.nl + demo-klant@gymies.nl
-- Actief (niet geschorst), trainer op Pro + actief abonnement in DB,
-- rijk gevuld voor testers (boekingen, chat, dossier, voortgang, doelen).
-- ============================================================
-- Gebruik op server:
--   cd /var/www/gymies && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/seed_gymies_demo_account_full.sql
-- Of: mysql -u USER -p DB < database/seed_gymies_demo_account_full.sql
--
-- Wachtwoord beiden: password (bcrypt hash)
-- ============================================================

SET NAMES utf8mb4;

-- bcrypt voor 'password'
SET @pw := '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi';

-- ========== 1) USERS ==========
INSERT INTO gymies_users (
  email, password_hash, role, display_name, first_name, last_name, phone,
  email_verified_at, phone_verified_at, trainer_approved_at,
  address_line1, postcode, city, country, business_name, coc_number, vat_number
) VALUES
  ('demo@gymies.nl', @pw, 'trainer', 'Alex van den Berg', 'Alex', 'van den Berg', '+31612345678',
   NOW(), NOW(), NOW(),
   'Overtoom 120', '1054 HS', 'Amsterdam', 'NL', 'Van den Berg PT', '87654321', 'NL998877665B01'),
  ('demo-klant@gymies.nl', @pw, 'klant', 'Sam de Vries', 'Sam', 'de Vries', '+31687654321',
   NOW(), NOW(), NULL,
   'Elandsgracht 44', '1016 SG', 'Amsterdam', 'NL', NULL, NULL, NULL)
ON DUPLICATE KEY UPDATE
  password_hash = VALUES(password_hash),
  role = VALUES(role),
  display_name = VALUES(display_name),
  first_name = VALUES(first_name),
  last_name = VALUES(last_name),
  phone = VALUES(phone),
  email_verified_at = COALESCE(email_verified_at, NOW()),
  trainer_approved_at = COALESCE(trainer_approved_at, VALUES(trainer_approved_at)),
  is_suspended = 0,
  suspended_reason = NULL,
  suspended_at = NULL;

SET @demo_trainer_id := (SELECT id FROM gymies_users WHERE email = 'demo@gymies.nl' LIMIT 1);
SET @demo_client_id := (SELECT id FROM gymies_users WHERE email = 'demo-klant@gymies.nl' LIMIT 1);

-- Extra profielinfo (accounts expliciet actief + leesbare demo-identiteit)
UPDATE gymies_users SET
  is_suspended = 0,
  suspended_reason = NULL,
  suspended_at = NULL,
  preferred_language = 'nl',
  date_of_birth = '1992-03-18',
  avatar_url = 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400&q=80',
  accessibility_needs = 'Demo-account: geen echte medische gegevens. Geschikt voor testers van de Gymies-app.'
WHERE id = @demo_client_id AND @demo_client_id IS NOT NULL;

UPDATE gymies_users SET
  is_suspended = 0,
  suspended_reason = NULL,
  suspended_at = NULL,
  preferred_language = 'nl',
  date_of_birth = '1988-11-02',
  avatar_url = 'https://images.unsplash.com/photo-1549476464-37392f717541?w=400&q=80'
WHERE id = @demo_trainer_id AND @demo_trainer_id IS NOT NULL;

-- ========== 2) TRAINER PROFIEL (demo@gymies.nl) ==========
INSERT INTO gymies_trainer_profiles (
  user_id, bio, specialty, hourly_rate_cents, avatar_url, region, trainer_verified_at,
  certifications, experience_years, languages, min_session_minutes, is_available, featured, trial_session_cents,
  subscription_plan, mollie_onboarding_status, accepts_cash, accepts_online, target_audiences, service_radius_km, travels_to_client
)
SELECT @demo_trainer_id,
  'Hoi! Ik ben Alex — demo-trainer op Gymies om de app te testen. Ik coach kracht, conditie en leefstijl (thuis, op locatie en online). Dit profiel is expres gevuld met voorbeelddata: agenda, pakketten, groepsles, chat en dossier.',
  'Kracht & Leefstijl',
  6500,
  'https://images.unsplash.com/photo-1549476464-37392f717541?w=500&q=80',
  'Amsterdam',
  NOW(),
  'NASM CPT, Fitvak A, Voedingscoach (demo)',
  8,
  'NL, EN',
  60,
  1,
  1,
  3500,
  'pro',
  'completed',
  1,
  1,
  'Beginners, doorstromers, 40+, revalidatie (demo)',
  12,
  1
FROM DUAL
WHERE @demo_trainer_id IS NOT NULL
ON DUPLICATE KEY UPDATE
  bio = VALUES(bio),
  specialty = VALUES(specialty),
  hourly_rate_cents = VALUES(hourly_rate_cents),
  avatar_url = VALUES(avatar_url),
  region = VALUES(region),
  trainer_verified_at = VALUES(trainer_verified_at),
  certifications = VALUES(certifications),
  experience_years = VALUES(experience_years),
  languages = VALUES(languages),
  min_session_minutes = VALUES(min_session_minutes),
  is_available = VALUES(is_available),
  featured = VALUES(featured),
  trial_session_cents = VALUES(trial_session_cents),
  subscription_plan = VALUES(subscription_plan),
  mollie_onboarding_status = VALUES(mollie_onboarding_status),
  accepts_cash = VALUES(accepts_cash),
  accepts_online = VALUES(accepts_online),
  target_audiences = VALUES(target_audiences),
  service_radius_km = VALUES(service_radius_km),
  travels_to_client = VALUES(travels_to_client);

-- ========== 3) TRAINER MEDIA (galerijfoto's) ==========
INSERT IGNORE INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT @demo_trainer_id, 'image', 'external', 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&q=80', 'Krachttraining in de gym', 1 FROM DUAL WHERE @demo_trainer_id IS NOT NULL;
INSERT IGNORE INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT @demo_trainer_id, 'image', 'external', 'https://images.unsplash.com/photo-1581009146145-b5ef050c149e?w=800&q=80', 'Personal training sessie', 2 FROM DUAL WHERE @demo_trainer_id IS NOT NULL;
INSERT IGNORE INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT @demo_trainer_id, 'image', 'external', 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=800&q=80', 'Functionele training', 3 FROM DUAL WHERE @demo_trainer_id IS NOT NULL;
INSERT IGNORE INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT @demo_trainer_id, 'image', 'external', 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=800&q=80', 'Groepsessie outdoor', 4 FROM DUAL WHERE @demo_trainer_id IS NOT NULL;

-- ========== 4) TRAINER STOREFRONT (SEO, succesverhalen, Instagram, video) ==========
-- success_stories: foto's + 1 video voor story-viewer. image_url kan .mp4 zijn voor video.
INSERT INTO gymies_trainer_storefront (trainer_user_id, success_stories_json, video_pitch_url, instagram_handle, specializations_display, seo_title, seo_description, seo_keywords)
SELECT @demo_trainer_id,
  '[{"title":"Van 95 naar 78 kg","body":"In 6 maanden tijd met gerichte krachttraining en voedingscoaching.","image_url":"https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=400"},{"title":"Blessurevrij hardlopen","body":"Na knieblessure weer pijnvrij hardlopen door revalidatietraining.","image_url":"https://images.unsplash.com/photo-1531891437562-4301cf35b7e4?w=400"},{"title":"Workout sfeer","body":"Korte sfeerimpressie van een sessie.","image_url":"https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4"}]',
  'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  'gymies_demo_pt',
  'Krachttraining • Conditie • Leefstijlcoaching • Revalidatie',
  'Alex van den Berg – Demo personal trainer Amsterdam | Gymies',
  'Demo-profiel op Gymies: voorbeeld-etalage voor testers. Kracht, conditie en leefstijl — boek een proefsessie om de flow te proberen.',
  'personal trainer amsterdam, gymies demo, krachttraining'
FROM DUAL
WHERE @demo_trainer_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_trainer_storefront')
ON DUPLICATE KEY UPDATE
  success_stories_json = VALUES(success_stories_json),
  video_pitch_url = VALUES(video_pitch_url),
  instagram_handle = IFNULL(VALUES(instagram_handle), instagram_handle),
  specializations_display = VALUES(specializations_display),
  seo_title = VALUES(seo_title),
  seo_description = VALUES(seo_description),
  seo_keywords = VALUES(seo_keywords);

-- ========== 5) TRAINER LOCATIONS ==========
INSERT INTO gymies_trainer_locations (trainer_user_id, location_type, name, address_line1, postcode, city, is_primary)
SELECT @demo_trainer_id, 'gym', 'Gym Amsterdam Centrum', 'Damrak 1', '1012 LG', 'Amsterdam', 1
FROM DUAL WHERE @demo_trainer_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM gymies_trainer_locations WHERE trainer_user_id = @demo_trainer_id);

INSERT INTO gymies_trainer_locations (trainer_user_id, location_type, name, is_primary)
SELECT @demo_trainer_id, 'online', 'Online (Zoom)', 0
FROM DUAL WHERE @demo_trainer_id IS NOT NULL AND (SELECT COUNT(*) FROM gymies_trainer_locations WHERE trainer_user_id = @demo_trainer_id) < 2;

SET @loc_id := (SELECT id FROM gymies_trainer_locations WHERE trainer_user_id = @demo_trainer_id LIMIT 1);

-- ========== 6) AVAILABILITY SLOTS ==========
INSERT IGNORE INTO gymies_availability_slots (trainer_user_id, day_of_week, start_time, end_time)
SELECT @demo_trainer_id, 1, '07:00:00', '12:00:00' FROM DUAL WHERE @demo_trainer_id IS NOT NULL;
INSERT IGNORE INTO gymies_availability_slots (trainer_user_id, day_of_week, start_time, end_time)
SELECT @demo_trainer_id, 1, '18:00:00', '21:00:00' FROM DUAL WHERE @demo_trainer_id IS NOT NULL;
INSERT IGNORE INTO gymies_availability_slots (trainer_user_id, day_of_week, start_time, end_time)
SELECT @demo_trainer_id, 3, '07:00:00', '12:00:00' FROM DUAL WHERE @demo_trainer_id IS NOT NULL;
INSERT IGNORE INTO gymies_availability_slots (trainer_user_id, day_of_week, start_time, end_time)
SELECT @demo_trainer_id, 5, '09:00:00', '17:00:00' FROM DUAL WHERE @demo_trainer_id IS NOT NULL;
INSERT IGNORE INTO gymies_availability_slots (trainer_user_id, day_of_week, start_time, end_time)
SELECT @demo_trainer_id, 6, '09:00:00', '14:00:00' FROM DUAL WHERE @demo_trainer_id IS NOT NULL;

-- ========== 7) SUBSCRIPTION (Pro: één actieve rij, API subscription_status = active) ==========
SET @demo_sub_id := (SELECT MAX(id) FROM gymies_subscriptions WHERE trainer_user_id = @demo_trainer_id);

UPDATE gymies_subscriptions
SET status = 'cancelled',
    cancelled_at = COALESCE(cancelled_at, NOW()),
    updated_at = NOW()
WHERE trainer_user_id = @demo_trainer_id
  AND @demo_trainer_id IS NOT NULL
  AND (@demo_sub_id IS NULL OR id <> @demo_sub_id);

INSERT INTO gymies_subscriptions (trainer_user_id, plan_id, status, current_period_start, current_period_end, created_at, updated_at)
SELECT @demo_trainer_id, p.id, 'active', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 12 MONTH), NOW(), NOW()
FROM gymies_plans p
WHERE p.slug = 'pro'
  AND @demo_trainer_id IS NOT NULL
  AND @demo_sub_id IS NULL;

SET @demo_sub_active_id := COALESCE(
  @demo_sub_id,
  (SELECT MAX(id) FROM gymies_subscriptions WHERE trainer_user_id = @demo_trainer_id)
);

UPDATE gymies_subscriptions s
INNER JOIN gymies_plans p ON p.slug = 'pro'
SET s.plan_id = p.id,
    s.status = 'active',
    s.current_period_start = CURDATE(),
    s.current_period_end = DATE_ADD(CURDATE(), INTERVAL 12 MONTH),
    s.cancelled_at = NULL,
    s.updated_at = NOW()
WHERE s.trainer_user_id = @demo_trainer_id
  AND @demo_trainer_id IS NOT NULL
  AND @demo_sub_active_id IS NOT NULL
  AND s.id = @demo_sub_active_id;

-- ========== 8) PACKAGES (server gebruikt total_cents) ==========
INSERT INTO gymies_packages (trainer_user_id, name, sessions_count, total_cents, valid_days, created_at, updated_at)
SELECT @demo_trainer_id, '10-Rittenkaart', 10, 54900, 56, NOW(), NOW()
FROM DUAL WHERE @demo_trainer_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM gymies_packages WHERE trainer_user_id = @demo_trainer_id);

INSERT INTO gymies_packages (trainer_user_id, name, sessions_count, total_cents, valid_days, created_at, updated_at)
SELECT @demo_trainer_id, 'Proefsessie', 1, 3500, 7, NOW(), NOW()
FROM DUAL WHERE @demo_trainer_id IS NOT NULL AND (SELECT COUNT(*) FROM gymies_packages WHERE trainer_user_id = @demo_trainer_id) < 2;

SET @pkg_id := (SELECT id FROM gymies_packages WHERE trainer_user_id = @demo_trainer_id LIMIT 1);

-- ========== 9) BOOKINGS (demo-klant → demo-trainer, server gebruikt amount_cents) ==========
INSERT INTO gymies_bookings (client_user_id, trainer_user_id, scheduled_at, duration_minutes, status, amount_cents, trainer_location_id, payment_method, location_notes, created_at, updated_at)
SELECT @demo_client_id, @demo_trainer_id, DATE_ADD(NOW(), INTERVAL 2 DAY), 60, 'confirmed', 6500, @loc_id, 'mollie_connect', 'Gym Amsterdam Centrum', NOW(), NOW()
FROM DUAL WHERE @demo_client_id IS NOT NULL AND @demo_trainer_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_bookings WHERE client_user_id = @demo_client_id AND trainer_user_id = @demo_trainer_id AND status = 'confirmed');

INSERT INTO gymies_bookings (client_user_id, trainer_user_id, scheduled_at, duration_minutes, status, amount_cents, trainer_location_id, payment_method, location_notes, created_at, updated_at)
SELECT @demo_client_id, @demo_trainer_id, DATE_ADD(NOW(), INTERVAL 5 DAY), 60, 'pending', 6500, @loc_id, NULL, 'Online sessie', NOW(), NOW()
FROM DUAL WHERE @demo_client_id IS NOT NULL AND @demo_trainer_id IS NOT NULL
  AND (SELECT COUNT(*) FROM gymies_bookings WHERE client_user_id = @demo_client_id AND trainer_user_id = @demo_trainer_id) < 2;

INSERT INTO gymies_bookings (client_user_id, trainer_user_id, scheduled_at, duration_minutes, status, amount_cents, trainer_location_id, payment_method, paid_at, created_at, updated_at)
SELECT @demo_client_id, @demo_trainer_id, DATE_SUB(NOW(), INTERVAL 7 DAY), 60, 'completed', 6500, @loc_id, 'mollie_connect', DATE_SUB(NOW(), INTERVAL 7 DAY), DATE_SUB(NOW(), INTERVAL 7 DAY), NOW()
FROM DUAL WHERE @demo_client_id IS NOT NULL AND @demo_trainer_id IS NOT NULL
  AND (SELECT COUNT(*) FROM gymies_bookings WHERE client_user_id = @demo_client_id AND trainer_user_id = @demo_trainer_id) < 3;

SET @booking_id := (SELECT id FROM gymies_bookings WHERE client_user_id = @demo_client_id AND trainer_user_id = @demo_trainer_id ORDER BY scheduled_at ASC LIMIT 1);
SET @booking_completed_id := (SELECT id FROM gymies_bookings WHERE client_user_id = @demo_client_id AND trainer_user_id = @demo_trainer_id AND status = 'completed' ORDER BY scheduled_at DESC LIMIT 1);

-- ========== 10) CONVERSATIONS + MESSAGES ==========
INSERT INTO gymies_conversations (client_user_id, trainer_user_id, booking_id, created_at, updated_at)
SELECT @demo_client_id, @demo_trainer_id, @booking_id, NOW(), NOW()
FROM DUAL WHERE @demo_client_id IS NOT NULL AND @demo_trainer_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_conversations WHERE client_user_id = @demo_client_id AND trainer_user_id = @demo_trainer_id);

SET @conv_id := (SELECT id FROM gymies_conversations WHERE client_user_id = @demo_client_id AND trainer_user_id = @demo_trainer_id LIMIT 1);

INSERT INTO gymies_messages (conversation_id, from_user_id, body, created_at)
SELECT @conv_id, @demo_client_id, 'Hoi Demo! Ik wil graag de app testen. Kun je me vertellen hoe de boekingsflow werkt?', NOW()
FROM DUAL WHERE @conv_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM gymies_messages WHERE conversation_id = @conv_id);

INSERT INTO gymies_messages (conversation_id, from_user_id, body, created_at)
SELECT @conv_id, @demo_trainer_id, 'Hallo! Natuurlijk. Je kunt via de agenda een slot kiezen. Ik heb beschikbaarheid op ma, wo, vr en za. Laat weten als je vragen hebt!', NOW()
FROM DUAL WHERE @conv_id IS NOT NULL AND (SELECT COUNT(*) FROM gymies_messages WHERE conversation_id = @conv_id) < 2;

INSERT INTO gymies_messages (conversation_id, from_user_id, body, created_at)
SELECT @conv_id, @demo_client_id, 'Top, dankjewel! Ik heb een sessie geboekt voor overmorgen.', NOW()
FROM DUAL WHERE @conv_id IS NOT NULL AND (SELECT COUNT(*) FROM gymies_messages WHERE conversation_id = @conv_id) < 3;

INSERT INTO gymies_messages (conversation_id, from_user_id, body, created_at)
SELECT @conv_id, @demo_trainer_id, 'Perfect. Vergeet geen handdoek en water mee te nemen. Tot dan!', DATE_SUB(NOW(), INTERVAL 1 HOUR)
FROM DUAL WHERE @conv_id IS NOT NULL AND (SELECT COUNT(*) FROM gymies_messages WHERE conversation_id = @conv_id) < 4;

-- ========== 10b) KLANT-DOSSIER + VOORTGANG + DOELEN (CRM-demo) ==========
-- Dossier: kolommen notes, goals_json, preferences_json (zoals op productie; uniq trainer+client)
INSERT INTO gymies_client_dossier (trainer_user_id, client_user_id, notes, goals_json, preferences_json, created_at, updated_at)
SELECT @demo_trainer_id, @demo_client_id,
  'Demo-dossier (feb–mrt): Sam wil 4 kg vet verliezen, beter slapen en 2× per week structuur. Positief: pakt schema’s op; uitdaging: drukke baan (kantoor). Medisch: fictief — bij echte klanten PAR-Q/huisarts.',
  '[{"title":"12 weken","detail":"Sterkere core, 5 km lopen, 2× kracht + 1× conditie per week"}]',
  '{"demo":true,"slaapdoel":"7 uur","werkcontext":"kantoor"}',
  NOW(), NOW()
FROM DUAL
WHERE @demo_trainer_id IS NOT NULL AND @demo_client_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_client_dossier')
ON DUPLICATE KEY UPDATE
  notes = VALUES(notes),
  goals_json = VALUES(goals_json),
  preferences_json = VALUES(preferences_json),
  updated_at = NOW();

INSERT INTO gymies_client_progress (client_user_id, trainer_user_id, type, value, note, is_private, created_at)
SELECT @demo_client_id, @demo_trainer_id, 'weight_kg', '78.2', 'Startmeting (demo)', 0, DATE_SUB(NOW(), INTERVAL 21 DAY)
FROM DUAL
WHERE @demo_client_id IS NOT NULL AND @demo_trainer_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_client_progress')
  AND NOT EXISTS (SELECT 1 FROM gymies_client_progress WHERE client_user_id = @demo_client_id AND trainer_user_id = @demo_trainer_id AND type = 'weight_kg' AND value = '78.2');

INSERT INTO gymies_client_progress (client_user_id, trainer_user_id, type, value, note, is_private, created_at)
SELECT @demo_client_id, @demo_trainer_id, 'weight_kg', '77.4', 'Na 2 weken (demo)', 0, DATE_SUB(NOW(), INTERVAL 7 DAY)
FROM DUAL
WHERE @demo_client_id IS NOT NULL AND @demo_trainer_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_client_progress')
  AND NOT EXISTS (SELECT 1 FROM gymies_client_progress WHERE client_user_id = @demo_client_id AND trainer_user_id = @demo_trainer_id AND type = 'weight_kg' AND value = '77.4');

INSERT INTO gymies_client_goals (trainer_user_id, client_user_id, title, target_value, current_value, unit, status, due_date, created_at, updated_at)
SELECT @demo_trainer_id, @demo_client_id, 'Bankdrukken techniek', NULL, NULL, NULL, 'active', DATE_ADD(CURDATE(), INTERVAL 45 DAY), NOW(), NOW()
FROM DUAL
WHERE @demo_trainer_id IS NOT NULL AND @demo_client_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_client_goals')
  AND NOT EXISTS (SELECT 1 FROM gymies_client_goals WHERE trainer_user_id = @demo_trainer_id AND client_user_id = @demo_client_id AND title = 'Bankdrukken techniek' AND deleted_at IS NULL);

INSERT INTO gymies_client_goals (trainer_user_id, client_user_id, title, target_value, current_value, unit, status, due_date, created_at, updated_at)
SELECT @demo_trainer_id, @demo_client_id, 'Wekelijkse stappen (gem.)', 8000, 6200, 'stappen/dag', 'active', DATE_ADD(CURDATE(), INTERVAL 30 DAY), NOW(), NOW()
FROM DUAL
WHERE @demo_trainer_id IS NOT NULL AND @demo_client_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_client_goals')
  AND NOT EXISTS (SELECT 1 FROM gymies_client_goals WHERE trainer_user_id = @demo_trainer_id AND client_user_id = @demo_client_id AND title = 'Wekelijkse stappen (gem.)' AND deleted_at IS NULL);

INSERT INTO gymies_client_session_entries (trainer_user_id, client_user_id, booking_id, session_at, session_type, attendance_status, focus, positive_notes, improve_notes, homework, energy_score, visibility, created_at, updated_at)
SELECT @demo_trainer_id, @demo_client_id, @booking_completed_id, COALESCE((SELECT scheduled_at FROM gymies_bookings WHERE id = @booking_completed_id), DATE_SUB(NOW(), INTERVAL 7 DAY)), 'personal_training', 'attended', 'Full body kracht', 'Goede intentie squats; ademhaling rustiger.', 'Meer schouderblad retractie bij roeien.', '2× plank 3x40s', 7, 'shared', NOW(), NOW()
FROM DUAL
WHERE @demo_trainer_id IS NOT NULL AND @demo_client_id IS NOT NULL AND @booking_completed_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_client_session_entries')
  AND NOT EXISTS (SELECT 1 FROM gymies_client_session_entries WHERE trainer_user_id = @demo_trainer_id AND client_user_id = @demo_client_id AND booking_id = @booking_completed_id AND deleted_at IS NULL);

INSERT INTO gymies_client_session_notes (booking_id, trainer_user_id, note, created_at)
SELECT @booking_completed_id, @demo_trainer_id, 'Demo-notitie: klant voelde energiek; volgende keer focus op hip hinge uitleg.', NOW()
FROM DUAL
WHERE @booking_completed_id IS NOT NULL AND @demo_trainer_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_client_session_notes')
  AND NOT EXISTS (SELECT 1 FROM gymies_client_session_notes WHERE booking_id = @booking_completed_id);

-- ========== 11) PROMO CODE (indien tabel bestaat — schema: discount_type, value_cents, max_uses) ==========
INSERT INTO gymies_promo_codes (trainer_user_id, code, discount_type, value_cents, valid_from, valid_until, max_uses, created_at, updated_at)
SELECT @demo_trainer_id, 'DEMO20', 'percent', 20, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 30 DAY), 10, NOW(), NOW()
FROM DUAL
WHERE @demo_trainer_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_promo_codes')
  AND NOT EXISTS (SELECT 1 FROM gymies_promo_codes WHERE code = 'DEMO20');

-- ========== 12) FAVORIET (klant heeft trainer als favoriet) ==========
INSERT IGNORE INTO gymies_favorites (client_user_id, trainer_user_id, created_at)
SELECT @demo_client_id, @demo_trainer_id, NOW()
FROM DUAL
WHERE @demo_client_id IS NOT NULL AND @demo_trainer_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_favorites');

-- ========== 13) GROEPSLES (Pro-feature, status alleen als kolom bestaat) ==========
INSERT INTO gymies_group_sessions (trainer_user_id, title, description, scheduled_at, duration_minutes, max_participants, price_cents, trainer_location_id, created_at, updated_at)
SELECT @demo_trainer_id, 'Bootcamp Zaterdag', 'Energieke groepstraining met kracht en conditie. Voor alle niveaus.', DATE_ADD(DATE_ADD(CURDATE(), INTERVAL 7 DAY), INTERVAL 10 HOUR), 60, 12, 1500, @loc_id, NOW(), NOW()
FROM DUAL
WHERE @demo_trainer_id IS NOT NULL AND @loc_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_group_sessions')
  AND NOT EXISTS (SELECT 1 FROM gymies_group_sessions WHERE trainer_user_id = @demo_trainer_id AND title LIKE '%Bootcamp%');

-- ========== Klaar ==========
SELECT
  @demo_trainer_id AS demo_trainer_id,
  @demo_client_id AS demo_client_id,
  'demo@gymies.nl' AS trainer_email,
  'demo-klant@gymies.nl' AS client_email,
  'password' AS wachtwoord_beide;
