-- ============================================================
-- Volledige dummy data voor jamai1210@live.nl als trainer
-- Storefront (stories, video, Instagram), dossiers, health, etc.
-- Zet dummy data op ALLE trainers zodat alles getest kan worden.
--
-- Gebruik op server:
--   cd /var/www/gymies && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/seed_gymies_jamai1210_full_dummy.sql
--
-- Vereisten: alter_gymies_trainer_storefront, alter_gymies_client_dossier,
--            alter_gymies_pro_client_health_and_upsell
-- ============================================================

SET NAMES utf8mb4;

-- bcrypt voor 'password'
SET @pw := '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi';

-- ========== 1) JAMAI1210@LIVE.NL ALS TRAINER (indien nog niet aanwezig) ==========
INSERT INTO gymies_users (
  email, password_hash, role, display_name, first_name, last_name, phone,
  email_verified_at, phone_verified_at, trainer_approved_at
) VALUES (
  'jamai1210@live.nl', @pw, 'trainer', 'Jamai El Madi', 'Jamai', 'El Madi', '+31612121212',
  NOW(), NOW(), NOW()
)
ON DUPLICATE KEY UPDATE
  role = 'trainer',
  display_name = VALUES(display_name),
  first_name = VALUES(first_name),
  last_name = VALUES(last_name),
  phone = VALUES(phone),
  email_verified_at = COALESCE(email_verified_at, NOW()),
  trainer_approved_at = COALESCE(trainer_approved_at, NOW());

SET @jamai_id := (SELECT id FROM gymies_users WHERE LOWER(TRIM(email)) = 'jamai1210@live.nl' LIMIT 1);

-- Trainerprofiel jamai1210 (Pro)
INSERT INTO gymies_trainer_profiles (
  user_id, bio, specialty, hourly_rate_cents, avatar_url, region, trainer_verified_at,
  certifications, experience_years, languages, min_session_minutes, is_available, featured,
  trial_session_cents, subscription_plan, mollie_onboarding_status
)
SELECT @jamai_id,
  'Resultaatgerichte personal trainer voor kracht, conditie en leefstijl. Werk zowel op locatie als online.',
  'Kracht & Leefstijl',
  6700,
  'https://images.unsplash.com/photo-1549476464-37392f717541?w=500&q=80',
  'Amsterdam',
  NOW(),
  'NASM CPT, Fitvak A',
  9,
  'NL, EN',
  60,
  1,
  1,
  3200,
  'pro',
  'not_started'
FROM DUAL
WHERE @jamai_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_trainer_profiles p WHERE p.user_id = @jamai_id);

UPDATE gymies_trainer_profiles
SET subscription_plan = 'pro', bio = 'Resultaatgerichte personal trainer voor kracht, conditie en leefstijl.', updated_at = NOW()
WHERE user_id = @jamai_id AND @jamai_id IS NOT NULL;

-- Pro-abonnement actief
SET @plan_id := (SELECT id FROM gymies_plans WHERE slug = 'pro' LIMIT 1);

INSERT INTO gymies_subscriptions (trainer_user_id, plan_id, status, current_period_start, current_period_end, created_at, updated_at)
SELECT @jamai_id, @plan_id, 'active', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 1 MONTH), NOW(), NOW()
FROM DUAL
WHERE @jamai_id IS NOT NULL AND @plan_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_subscriptions s WHERE s.trainer_user_id = @jamai_id AND s.status IN ('active','trialing'));

UPDATE gymies_subscriptions s
INNER JOIN gymies_plans p ON p.slug = 'pro'
SET s.plan_id = p.id, s.status = 'active', s.updated_at = NOW()
WHERE s.trainer_user_id = @jamai_id AND @jamai_id IS NOT NULL;

-- ========== 2) DUMMY KLANTEN VOOR JAMAI (voor dossiers, health, boekingen) ==========
INSERT INTO gymies_users (email, password_hash, role, display_name, first_name, last_name, phone, email_verified_at, phone_verified_at)
VALUES
  ('klant.femke@example.com', @pw, 'klant', 'Femke Vermeer', 'Femke', 'Vermeer', '+31614141414', NOW(), NOW()),
  ('klant.luca@example.com',  @pw, 'klant', 'Luca de Jong',  'Luca',  'de Jong',  '+31615151515', NOW(), NOW()),
  ('klant.noah@example.com',  @pw, 'klant', 'Noah Smit',    'Noah',  'Smit',    '+31630303030', NOW(), NOW()),
  ('klant.emma@example.com',  @pw, 'klant', 'Emma de Wit',  'Emma',  'de Wit',  '+31640404040', NOW(), NOW())
ON DUPLICATE KEY UPDATE role = 'klant', display_name = VALUES(display_name);

-- ========== 3) STOREFRONT OP ALLE TRAINERS (stories, video, Instagram) ==========
-- Success stories: foto's + 1 video. image_url kan .mp4 zijn voor video.
SET @stories_json := '[{"title":"Van 95 naar 78 kg","body":"In 6 maanden tijd met gerichte krachttraining en voedingscoaching.","image_url":"https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=400"},{"title":"Blessurevrij hardlopen","body":"Na knieblessure weer pijnvrij hardlopen door revalidatietraining.","image_url":"https://images.unsplash.com/photo-1531891437562-4301cf35b7e4?w=400"},{"title":"Workout sfeer","body":"Korte sfeerimpressie van een sessie.","image_url":"https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4"}]';
SET @video_url := 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';

-- Storefront voor jamai1210@live.nl
INSERT INTO gymies_trainer_storefront (trainer_user_id, success_stories_json, video_pitch_url, instagram_handle, specializations_display, seo_title, seo_description, seo_keywords)
SELECT @jamai_id, @stories_json, @video_url, 'jamai_pt', 'Krachttraining • Conditie • Leefstijlcoaching • Revalidatie',
  'Jamai El Madi – Personal trainer Amsterdam | Gymies',
  'Professionele personal training in Amsterdam. Persoonlijke begeleiding voor kracht, conditie en duurzame leefstijl.',
  'personal trainer amsterdam, krachttraining, conditietraining'
FROM DUAL
WHERE @jamai_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_trainer_storefront')
ON DUPLICATE KEY UPDATE
  success_stories_json = VALUES(success_stories_json),
  video_pitch_url = VALUES(video_pitch_url),
  instagram_handle = COALESCE(VALUES(instagram_handle), instagram_handle),
  specializations_display = VALUES(specializations_display),
  seo_title = VALUES(seo_title),
  seo_description = VALUES(seo_description),
  seo_keywords = VALUES(seo_keywords);

-- Storefront voor alle overige trainers (trainer.anne, trainer.rayan, etc.)
INSERT INTO gymies_trainer_storefront (trainer_user_id, success_stories_json, video_pitch_url, instagram_handle, specializations_display, seo_title, seo_description, seo_keywords)
SELECT u.id, @stories_json, @video_url, CONCAT(LOWER(REPLACE(SUBSTRING_INDEX(u.display_name,' ',1),' ','')), '_pt'),
  COALESCE(p.specialty, 'Personal training'),
  CONCAT(u.display_name, ' – Personal trainer | Gymies'),
  CONCAT('Professionele personal training. ', COALESCE(p.bio, '')),
  'personal trainer'
FROM gymies_users u
LEFT JOIN gymies_trainer_profiles p ON p.user_id = u.id
WHERE u.role = 'trainer' AND u.id != @jamai_id
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'gymies_trainer_storefront')
  AND NOT EXISTS (SELECT 1 FROM gymies_trainer_storefront s WHERE s.trainer_user_id = u.id);

-- Update bestaande storefronts van andere trainers (zonder te overschrijven als ze al data hebben)
UPDATE gymies_trainer_storefront s
JOIN gymies_users u ON u.id = s.trainer_user_id
SET
  success_stories_json = COALESCE(NULLIF(TRIM(s.success_stories_json), ''), @stories_json),
  video_pitch_url = COALESCE(s.video_pitch_url, @video_url),
  instagram_handle = COALESCE(NULLIF(TRIM(s.instagram_handle), ''), CONCAT(LOWER(REPLACE(SUBSTRING_INDEX(u.display_name,' ',1),' ','')), '_pt'))
WHERE u.role = 'trainer' AND u.id != @jamai_id
  AND (s.success_stories_json IS NULL OR s.success_stories_json = '' OR s.video_pitch_url IS NULL);

-- ========== 4) TRAINER MEDIA (galerijfoto's) VOOR JAMAI ==========
INSERT IGNORE INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT @jamai_id, 'image', 'external', 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&q=80', 'Krachttraining in de gym', 1 FROM DUAL WHERE @jamai_id IS NOT NULL;
INSERT IGNORE INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT @jamai_id, 'image', 'external', 'https://images.unsplash.com/photo-1581009146145-b5ef050c149e?w=800&q=80', 'Personal training sessie', 2 FROM DUAL WHERE @jamai_id IS NOT NULL;
INSERT IGNORE INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT @jamai_id, 'image', 'external', 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=800&q=80', 'Functionele training', 3 FROM DUAL WHERE @jamai_id IS NOT NULL;

-- ========== 5) DOSSIERS VOOR JAMAI'S KLANTEN ==========
INSERT INTO gymies_client_dossier (trainer_user_id, client_user_id, internal_notes, medical_background, goals_long_term)
SELECT @jamai_id, c.id,
  'Intake gedaan. Focus op krachtopbouw en conditie. Wekelijks 2 sessies.',
  'Geen bijzonderheden. Licht rugklachten in het verleden, nu onder controle.',
  '10 kg afvallen, spieropbouw, duurzame leefstijl.'
FROM gymies_users c WHERE c.email = 'klant.femke@example.com' AND @jamai_id IS NOT NULL
ON DUPLICATE KEY UPDATE internal_notes = VALUES(internal_notes), medical_background = VALUES(medical_background), goals_long_term = VALUES(goals_long_term);

INSERT INTO gymies_client_dossier (trainer_user_id, client_user_id, internal_notes, medical_background, goals_long_term)
SELECT @jamai_id, c.id,
  'Hardloper. Wil blessurevrij blijven en snelheid verbeteren.',
  'Knie-operatie 2 jaar geleden. Revalidatie afgerond.',
  'Marathon onder 4 uur, geen blessures.'
FROM gymies_users c WHERE c.email = 'klant.luca@example.com' AND @jamai_id IS NOT NULL
ON DUPLICATE KEY UPDATE internal_notes = VALUES(internal_notes), medical_background = VALUES(medical_background), goals_long_term = VALUES(goals_long_term);

INSERT INTO gymies_client_dossier (trainer_user_id, client_user_id, internal_notes, medical_background, goals_long_term)
SELECT @jamai_id, c.id,
  'Beginnende sporter. Motivatie hoog. Focus op basis oefeningen.',
  NULL,
  'Gezond gewicht, meer energie, 2x per week trainen.'
FROM gymies_users c WHERE c.email = 'klant.noah@example.com' AND @jamai_id IS NOT NULL
ON DUPLICATE KEY UPDATE internal_notes = VALUES(internal_notes), medical_background = VALUES(medical_background), goals_long_term = VALUES(goals_long_term);

INSERT INTO gymies_client_dossier (trainer_user_id, client_user_id, internal_notes, medical_background, goals_long_term)
SELECT @jamai_id, c.id,
  'Postnataal traject. Voorzichtig opbouwen.',
  'Bevalling 4 maanden geleden. Geen complicaties.',
  'Core herstel, kracht opbouwen, 5 km hardlopen.'
FROM gymies_users c WHERE c.email = 'klant.emma@example.com' AND @jamai_id IS NOT NULL
ON DUPLICATE KEY UPDATE internal_notes = VALUES(internal_notes), medical_background = VALUES(medical_background), goals_long_term = VALUES(goals_long_term);

-- ========== 6) HEALTH SNAPSHOTS (Pro Health) VOOR JAMAI'S KLANTEN ==========
INSERT INTO gymies_trainer_client_health_snapshots (trainer_user_id, client_user_id, health_score, retention_risk, no_show_risk, churn_alert, signals_json)
SELECT @jamai_id, c.id, 85, 'low', 'low', 0, '{"sessions_last_30d":4,"last_session_days_ago":3}'
FROM gymies_users c WHERE c.email = 'klant.femke@example.com' AND @jamai_id IS NOT NULL
ON DUPLICATE KEY UPDATE health_score = VALUES(health_score), retention_risk = VALUES(retention_risk), no_show_risk = VALUES(no_show_risk), signals_json = VALUES(signals_json);

INSERT INTO gymies_trainer_client_health_snapshots (trainer_user_id, client_user_id, health_score, retention_risk, no_show_risk, churn_alert, signals_json)
SELECT @jamai_id, c.id, 72, 'medium', 'low', 0, '{"sessions_last_30d":2,"last_session_days_ago":14}'
FROM gymies_users c WHERE c.email = 'klant.luca@example.com' AND @jamai_id IS NOT NULL
ON DUPLICATE KEY UPDATE health_score = VALUES(health_score), retention_risk = VALUES(retention_risk), no_show_risk = VALUES(no_show_risk), signals_json = VALUES(signals_json);

INSERT INTO gymies_trainer_client_health_snapshots (trainer_user_id, client_user_id, health_score, retention_risk, no_show_risk, churn_alert, signals_json)
SELECT @jamai_id, c.id, 45, 'high', 'medium', 1, '{"sessions_last_30d":0,"last_session_days_ago":28,"no_shows":1}'
FROM gymies_users c WHERE c.email = 'klant.noah@example.com' AND @jamai_id IS NOT NULL
ON DUPLICATE KEY UPDATE health_score = VALUES(health_score), retention_risk = VALUES(retention_risk), no_show_risk = VALUES(no_show_risk), churn_alert = VALUES(churn_alert), signals_json = VALUES(signals_json);

INSERT INTO gymies_trainer_client_health_snapshots (trainer_user_id, client_user_id, health_score, retention_risk, no_show_risk, churn_alert, signals_json)
SELECT @jamai_id, c.id, 90, 'low', 'low', 0, '{"sessions_last_30d":6,"last_session_days_ago":1}'
FROM gymies_users c WHERE c.email = 'klant.emma@example.com' AND @jamai_id IS NOT NULL
ON DUPLICATE KEY UPDATE health_score = VALUES(health_score), retention_risk = VALUES(retention_risk), no_show_risk = VALUES(no_show_risk), signals_json = VALUES(signals_json);

-- Health scores (trainer_client_health_scores) voor Pro Health dashboard
INSERT INTO trainer_client_health_scores (trainer_user_id, client_user_id, health_score, retention_risk, no_show_risk, churn_alert, signals_json)
SELECT trainer_user_id, client_user_id, health_score, retention_risk, no_show_risk, churn_alert, signals_json
FROM gymies_trainer_client_health_snapshots
WHERE trainer_user_id = @jamai_id AND @jamai_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'trainer_client_health_scores')
ON DUPLICATE KEY UPDATE health_score = VALUES(health_score), retention_risk = VALUES(retention_risk), no_show_risk = VALUES(no_show_risk), churn_alert = VALUES(churn_alert), signals_json = VALUES(signals_json);

-- ========== 7) BOEKINGEN JAMAI ↔ KLANTEN (voor dashboard, conversaties) ==========
INSERT INTO gymies_bookings (client_user_id, trainer_user_id, scheduled_at, duration_minutes, status, amount_cents, paid_at, location_type, location_notes)
SELECT c.id, @jamai_id, CONCAT(CURDATE() + INTERVAL 1 DAY, ' 10:00:00'), 60, 'pending', 6700, NULL, 'gym', 'Vondelgym Zuid'
FROM gymies_users c
WHERE c.email = 'klant.femke@example.com' AND @jamai_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_bookings b WHERE b.client_user_id = c.id AND b.trainer_user_id = @jamai_id AND DATE(b.scheduled_at) = CURDATE() + INTERVAL 1 DAY);

INSERT INTO gymies_bookings (client_user_id, trainer_user_id, scheduled_at, duration_minutes, status, amount_cents, paid_at, location_type, location_notes)
SELECT c.id, @jamai_id, CONCAT(CURDATE() + INTERVAL 2 DAY, ' 14:00:00'), 60, 'confirmed', 6700, NULL, 'on_site', 'Amsterdam Bos'
FROM gymies_users c
WHERE c.email = 'klant.luca@example.com' AND @jamai_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_bookings b WHERE b.client_user_id = c.id AND b.trainer_user_id = @jamai_id AND DATE(b.scheduled_at) = CURDATE() + INTERVAL 2 DAY);

INSERT INTO gymies_bookings (client_user_id, trainer_user_id, scheduled_at, duration_minutes, status, amount_cents, paid_at, location_type, location_notes)
SELECT c.id, @jamai_id, CONCAT(CURDATE() - INTERVAL 5 DAY, ' 09:00:00'), 60, 'completed', 6700, NOW(), 'gym', 'Vondelgym Zuid'
FROM gymies_users c
WHERE c.email = 'klant.femke@example.com' AND @jamai_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_bookings b WHERE b.client_user_id = c.id AND b.trainer_user_id = @jamai_id AND DATE(b.scheduled_at) = CURDATE() - INTERVAL 5 DAY);

-- ========== 8) CONVERSATIE + BERICHTEN (berichtenwidget) ==========
INSERT INTO gymies_conversations (client_user_id, trainer_user_id, booking_id, created_at, updated_at)
SELECT c.id, @jamai_id, (SELECT id FROM gymies_bookings WHERE client_user_id = c.id AND trainer_user_id = @jamai_id ORDER BY scheduled_at DESC LIMIT 1), NOW(), NOW()
FROM gymies_users c WHERE c.email = 'klant.femke@example.com' AND @jamai_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_conversations conv WHERE conv.client_user_id = c.id AND conv.trainer_user_id = @jamai_id);

INSERT INTO gymies_messages (conversation_id, from_user_id, body, created_at)
SELECT conv.id, sender.id, d.body, d.created_at
FROM (
  SELECT 'klant.femke@example.com' AS sender_email, 'Hi Jamai, ik wil volgende week extra focus op core.' AS body, DATE_SUB(NOW(), INTERVAL 3 HOUR) AS created_at
  UNION ALL SELECT 'jamai1210@live.nl', 'Top! Ik zet een aangepast schema voor je klaar.' AS body, DATE_SUB(NOW(), INTERVAL 2 HOUR)
) d
JOIN gymies_users sender ON sender.email = d.sender_email
JOIN gymies_users c ON c.email = 'klant.femke@example.com'
JOIN gymies_conversations conv ON conv.client_user_id = c.id AND conv.trainer_user_id = @jamai_id
WHERE @jamai_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_messages m WHERE m.conversation_id = conv.id AND m.body = d.body LIMIT 1);

-- ========== 9) BESCHIKBAARHEID JAMAI ==========
INSERT IGNORE INTO gymies_availability_slots (trainer_user_id, day_of_week, start_time, end_time)
SELECT @jamai_id, d.dow, d.start_t, d.end_t
FROM (
  SELECT 1 AS dow, '07:30:00' AS start_t, '11:30:00' AS end_t
  UNION ALL SELECT 3, '18:00:00', '21:00:00'
  UNION ALL SELECT 5, '09:00:00', '17:00:00'
  UNION ALL SELECT 6, '09:00:00', '13:00:00'
) d
WHERE @jamai_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM gymies_availability_slots s WHERE s.trainer_user_id = @jamai_id AND s.day_of_week = d.dow AND s.start_time = d.start_t);

-- ========== 10) PACKAGES VOOR JAMAI ==========
INSERT INTO gymies_packages (trainer_user_id, name, sessions_count, total_cents, valid_days, created_at, updated_at)
SELECT @jamai_id, '10-Rittenkaart', 10, 54900, 56, NOW(), NOW()
FROM DUAL WHERE @jamai_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM gymies_packages WHERE trainer_user_id = @jamai_id);

INSERT INTO gymies_packages (trainer_user_id, name, sessions_count, total_cents, valid_days, created_at, updated_at)
SELECT @jamai_id, 'Proefsessie', 1, 3200, 7, NOW(), NOW()
FROM DUAL WHERE @jamai_id IS NOT NULL AND (SELECT COUNT(*) FROM gymies_packages WHERE trainer_user_id = @jamai_id) < 2;

-- ========== Klaar ==========
SELECT
  @jamai_id AS jamai_user_id,
  'jamai1210@live.nl' AS trainer_email,
  'password' AS wachtwoord_dummy_klanten,
  'Storefront, dossiers, health, boekingen, conversaties toegevoegd.' AS status;
