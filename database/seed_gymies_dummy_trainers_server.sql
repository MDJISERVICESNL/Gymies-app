-- Dummy trainers voor server (alleen users + trainer_profiles + trainer_media met foto's).
-- Geen afhankelijkheid van availability_slots, bookings, reviews, conversations.
-- Eerst schema draaien als dat nog niet is gedaan: create_gymies_tables_if_not_exists.sql
-- Gebruik: cd /var/www/mdjiservices.nl/laravel && php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/seed_gymies_dummy_trainers_server.sql

SET NAMES utf8mb4;

-- Wachtwoord voor alle dummy accounts: "password"
-- Hash: bcrypt voor 'password'
INSERT INTO gymies_users (
  email, password_hash, role, display_name, first_name, last_name, phone, email_verified_at, phone_verified_at, trainer_approved_at
) VALUES
  ('trainer.anne@example.com',   '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'trainer', 'Anne de Vries',   'Anne',   'de Vries',   '+31611111111', NOW(), NOW(), NOW()),
  ('trainer.rayan@example.com',   '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'trainer', 'Rayan El Amrani', 'Rayan', 'El Amrani', '+31622222222', NOW(), NOW(), NOW()),
  ('trainer.sophie@example.com',  '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'trainer', 'Sophie van Dam',  'Sophie', 'van Dam',  '+31633333333', NOW(), NOW(), NOW()),
  ('trainer.daan@example.com',    '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'trainer', 'Daan Peters',     'Daan',  'Peters',    '+31644444444', NOW(), NOW(), NOW()),
  ('trainer.ines@example.com',    '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'trainer', 'Ines Bakker',     'Ines',  'Bakker',    '+31655555555', NOW(), NOW(), NOW()),
  ('trainer.jasper@example.com',  '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'trainer', 'Jasper Boer',     'Jasper', 'Boer',    '+31666666666', NOW(), NOW(), NOW()),
  ('trainer.noura@example.com',   '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'trainer', 'Noura Kabbaj',    'Noura', 'Kabbaj',   '+31677777777', NOW(), NOW(), NOW()),
  ('trainer.milan@example.com',   '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'trainer', 'Milan Vos',       'Milan', 'Vos',      '+31688888888', NOW(), NOW(), NOW()),
  ('trainer.fatima@example.com',  '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'trainer', 'Fatima Idrissi',  'Fatima', 'Idrissi', '+31699999999', NOW(), NOW(), NOW()),
  ('trainer.thomas@example.com',  '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'trainer', 'Thomas Meijer',   'Thomas', 'Meijer',  '+31610101010', NOW(), NOW(), NOW()),
  ('trainer.jamai@example.com',   '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'trainer', 'Jamai El Madi',   'Jamai', 'El Madi',  '+31612121212', NOW(), NOW(), NOW())
ON DUPLICATE KEY UPDATE
  role = 'trainer',
  display_name = VALUES(display_name),
  first_name = VALUES(first_name),
  last_name = VALUES(last_name),
  phone = VALUES(phone),
  email_verified_at = VALUES(email_verified_at),
  phone_verified_at = VALUES(phone_verified_at),
  trainer_approved_at = NOW();

-- Zeker weten dat alle dummy-accounts als goedgekeurde trainer in de DB staan (bijv. na eerdere run met andere role)
UPDATE gymies_users SET role = 'trainer', trainer_approved_at = NOW() WHERE email LIKE 'trainer.%@example.com';

-- Trainerprofielen met bio, specialisme, tarief, avatar (Unsplash), regio, certificaten, ervaring
INSERT INTO gymies_trainer_profiles (
  user_id, bio, specialty, hourly_rate_cents, avatar_url, region, trainer_verified_at,
  certifications, experience_years, languages, min_session_minutes, is_available, featured, trial_session_cents
)
SELECT u.id, d.bio, d.specialty, d.hourly_rate_cents, d.avatar_url, d.region, NOW(),
  d.certifications, d.experience_years, d.languages, d.min_session_minutes, 1, d.featured, d.trial_session_cents
FROM (
  SELECT 'trainer.anne@example.com' AS email,   'Ik help drukke professionals met kracht, houding en duurzame energie.' AS bio, 'Krachttraining' AS specialty, 6500 AS hourly_rate_cents, 'https://images.unsplash.com/photo-1594381898411-846e7d193883?w=500&q=80' AS avatar_url, 'Amsterdam' AS region, 'Fitvak A, NASM CPT' AS certifications, 8 AS experience_years, 'NL, EN' AS languages, 60 AS min_session_minutes, 1 AS featured, 3500 AS trial_session_cents
  UNION ALL SELECT 'trainer.rayan@example.com',   'Conditie en vetverlies trajecten met meetbare progressie.',            'Conditie & Vetverlies',    5900, 'https://images.unsplash.com/photo-1546483875-ad9014c88eba?w=500&q=80', 'Rotterdam', 'ACE CPT', 6, 'NL, EN', 45, 0, 2900
  UNION ALL SELECT 'trainer.sophie@example.com',  'Mobility en revalidatiegerichte coaching voor veilig opbouwen.',       'Mobility & Revalidatie',   7200, 'https://images.unsplash.com/photo-1518310383802-640c2de311b2?w=500&q=80', 'Utrecht', 'Fysiotrainer certificaat', 10, 'NL, EN, DE', 60, 1, 3900
  UNION ALL SELECT 'trainer.daan@example.com',   'Hyrox en functionele training met focus op prestaties.',               'Hyrox & Functioneel',      6800, 'https://images.unsplash.com/photo-1566753323558-f4e0952af115?w=500&q=80', 'Den Haag', 'CrossFit L1', 7, 'NL, EN', 60, 0, 3400
  UNION ALL SELECT 'trainer.ines@example.com',  'Postnatale en vrouwenkracht trajecten, veilig en doelgericht.',        'Vrouwenkracht',            6400, 'https://images.unsplash.com/photo-1549060279-7e168fcee0c2?w=500&q=80', 'Eindhoven', 'Pre/Postnatal Certified', 9, 'NL, EN', 45, 1, 3200
  UNION ALL SELECT 'trainer.jasper@example.com', 'Marathon voorbereiding en blessurepreventie voor alle niveaus.',       'Hardlopen',                5600, 'https://images.unsplash.com/photo-1531891437562-4301cf35b7e4?w=500&q=80', 'Haarlem', 'Running Coach L2', 5, 'NL, EN', 45, 0, 2500
  UNION ALL SELECT 'trainer.noura@example.com',  'Boksen voor conditie, zelfvertrouwen en stressreductie.',              'Boksen',                   6100, 'https://images.unsplash.com/photo-1599058917212-d750089bc07e?w=500&q=80', 'Tilburg', 'Boxing Coach', 6, 'NL, EN, AR', 60, 0, 3000
  UNION ALL SELECT 'trainer.milan@example.com',  'Calisthenics en bodyweight skills met duidelijke progressie.',         'Calisthenics',             6000, 'https://images.unsplash.com/photo-1583454110551-21f2fa2afe61?w=500&q=80', 'Nijmegen', 'Street Workout Coach', 7, 'NL, EN', 60, 0, 3000
  UNION ALL SELECT 'trainer.fatima@example.com', 'Pilates en core-stability met focus op houding en balans.',           'Pilates',                  5800, 'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=500&q=80', 'Leiden', 'Pilates Mat Instructor', 8, 'NL, EN, FR', 45, 1, 2800
  UNION ALL SELECT 'trainer.thomas@example.com', 'Senior fitness en leefstijlcoaching met rustige opbouw.',              'Senior Fitness',           5400, 'https://images.unsplash.com/photo-1552674605-db6ffd4facb5?w=500&q=80', 'Breda', 'Senior Fit Coach', 12, 'NL', 45, 0, 2500
  UNION ALL SELECT 'trainer.jamai@example.com',  'Resultaatgerichte personal trainer voor kracht, conditie en leefstijl.', 'Kracht & Leefstijl',      6700, 'https://images.unsplash.com/photo-1549476464-37392f717541?w=500&q=80', 'Amsterdam', 'NASM CPT, Fitvak A', 9, 'NL, EN', 60, 1, 3200
) d
JOIN gymies_users u ON u.email = d.email
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
  trial_session_cents = VALUES(trial_session_cents);

-- Zichtbaar en boekbaar: alle dummy-trainerprofielen op is_available = 1
UPDATE gymies_trainer_profiles p
JOIN gymies_users u ON u.id = p.user_id
SET p.is_available = 1
WHERE u.email LIKE 'trainer.%@example.com';

-- Galerijfoto's per trainer (Unsplash). Als tabel gymies_trainer_media niet bestaat: deze INSERTs falen, users+profiles staan er wel.
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&q=80', 'Krachttraining', 1 FROM gymies_users u WHERE u.email = 'trainer.anne@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1581009146145-b5ef050c149e?w=800&q=80', 'Sessie in de gym', 2 FROM gymies_users u WHERE u.email = 'trainer.anne@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=800&q=80', 'Personal training', 3 FROM gymies_users u WHERE u.email = 'trainer.anne@example.com' LIMIT 1;

INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=800&q=80', 'Conditietraining', 1 FROM gymies_users u WHERE u.email = 'trainer.rayan@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1517963879433-6ad2b056d712?w=800&q=80', 'Groepsessie', 2 FROM gymies_users u WHERE u.email = 'trainer.rayan@example.com' LIMIT 1;

INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=800&q=80', 'Revalidatie', 1 FROM gymies_users u WHERE u.email = 'trainer.sophie@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1549060279-7e168fcee0c2?w=800&q=80', 'Mobility', 2 FROM gymies_users u WHERE u.email = 'trainer.sophie@example.com' LIMIT 1;

INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1566241142559-40e1dab266c8?w=800&q=80', 'CrossFit', 1 FROM gymies_users u WHERE u.email = 'trainer.daan@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1581009137042-c552e485697a?w=800&q=80', 'Functioneel', 2 FROM gymies_users u WHERE u.email = 'trainer.daan@example.com' LIMIT 1;

INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1549060279-7e168fcee0c2?w=800&q=80', 'Vrouwenkracht', 1 FROM gymies_users u WHERE u.email = 'trainer.ines@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&q=80', 'Personal training', 2 FROM gymies_users u WHERE u.email = 'trainer.ines@example.com' LIMIT 1;

INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1531891437562-4301cf35b7e4?w=800&q=80', 'Hardlopen', 1 FROM gymies_users u WHERE u.email = 'trainer.jasper@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=800&q=80', 'Conditie', 2 FROM gymies_users u WHERE u.email = 'trainer.jasper@example.com' LIMIT 1;

INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1599058917212-d750089bc07e?w=800&q=80', 'Bokstraining', 1 FROM gymies_users u WHERE u.email = 'trainer.noura@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1517963879433-6ad2b056d712?w=800&q=80', 'Conditie', 2 FROM gymies_users u WHERE u.email = 'trainer.noura@example.com' LIMIT 1;

INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1583454110551-21f2fa2afe61?w=800&q=80', 'Calisthenics', 1 FROM gymies_users u WHERE u.email = 'trainer.milan@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=800&q=80', 'Bodyweight', 2 FROM gymies_users u WHERE u.email = 'trainer.milan@example.com' LIMIT 1;

INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=800&q=80', 'Pilates', 1 FROM gymies_users u WHERE u.email = 'trainer.fatima@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=800&q=80', 'Core & balans', 2 FROM gymies_users u WHERE u.email = 'trainer.fatima@example.com' LIMIT 1;

INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1552674605-db6ffd4facb5?w=800&q=80', 'Senior fitness', 1 FROM gymies_users u WHERE u.email = 'trainer.thomas@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=800&q=80', 'Leefstijlcoaching', 2 FROM gymies_users u WHERE u.email = 'trainer.thomas@example.com' LIMIT 1;

INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1549476464-37392f717541?w=800&q=80', 'Kracht & conditie', 1 FROM gymies_users u WHERE u.email = 'trainer.jamai@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=800&q=80', 'Personal training', 2 FROM gymies_users u WHERE u.email = 'trainer.jamai@example.com' LIMIT 1;
INSERT INTO gymies_trainer_media (trainer_user_id, media_type, source_type, external_url, caption, sort_order)
SELECT u.id, 'image', 'external', 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&q=80', 'In de gym', 3 FROM gymies_users u WHERE u.email = 'trainer.jamai@example.com' LIMIT 1;
