-- Seed: 10 dummy trainers voor TrainMaat (demo/test)
-- Gebruik: mysql -u USER -p DATABASE < seed_gymies_dummy_trainers.sql

SET NAMES utf8mb4;

START TRANSACTION;

INSERT INTO gymies_users (
  email, password_hash, role, display_name, phone, email_verified_at, phone_verified_at
) VALUES
  ('trainer.anne@example.com',   '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'trainer', 'Anne de Vries',   '+31611111111', NOW(), NOW()),
  ('trainer.rayan@example.com',  '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'trainer', 'Rayan El Amrani', '+31622222222', NOW(), NOW()),
  ('trainer.sophie@example.com', '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'trainer', 'Sophie van Dam',  '+31633333333', NOW(), NOW()),
  ('trainer.daan@example.com',   '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'trainer', 'Daan Peters',     '+31644444444', NOW(), NOW()),
  ('trainer.ines@example.com',   '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'trainer', 'Ines Bakker',     '+31655555555', NOW(), NOW()),
  ('trainer.jasper@example.com', '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'trainer', 'Jasper Boer',     '+31666666666', NOW(), NOW()),
  ('trainer.noura@example.com',  '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'trainer', 'Noura Kabbaj',    '+31677777777', NOW(), NOW()),
  ('trainer.milan@example.com',  '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'trainer', 'Milan Vos',       '+31688888888', NOW(), NOW()),
  ('trainer.fatima@example.com', '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'trainer', 'Fatima Idrissi',  '+31699999999', NOW(), NOW()),
  ('trainer.thomas@example.com', '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'trainer', 'Thomas Meijer',   '+31610101010', NOW(), NOW()),
  ('jamai1210@live.nl',          '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'trainer', 'Jamai El Madi',   '+31612121212', NOW(), NOW())
ON DUPLICATE KEY UPDATE
  role='trainer',
  display_name=VALUES(display_name),
  phone=VALUES(phone),
  email_verified_at=VALUES(email_verified_at),
  phone_verified_at=VALUES(phone_verified_at);

INSERT INTO gymies_trainer_profiles (
  user_id, bio, specialty, hourly_rate_cents, avatar_url, region, trainer_verified_at,
  certifications, experience_years, languages, min_session_minutes, is_available, featured,
  trial_session_cents
)
SELECT
  u.id,
  d.bio,
  d.specialty,
  d.hourly_rate_cents,
  d.avatar_url,
  d.region,
  NOW(),
  d.certifications,
  d.experience_years,
  d.languages,
  d.min_session_minutes,
  1,
  d.featured,
  d.trial_session_cents
FROM (
  SELECT 'trainer.anne@example.com' AS email,   'Ik help drukke professionals met kracht, houding en duurzame energie.' AS bio, 'Krachttraining' AS specialty, 6500 AS hourly_rate_cents, 'https://images.unsplash.com/photo-1594381898411-846e7d193883?w=500&q=80' AS avatar_url, 'Amsterdam' AS region, 'Fitvak A, NASM CPT' AS certifications, 8 AS experience_years, 'NL, EN' AS languages, 60 AS min_session_minutes, 1 AS featured, 3500 AS trial_session_cents
  UNION ALL SELECT 'trainer.rayan@example.com',  'Conditie en vetverlies trajecten met meetbare progressie.',            'Conditie & Vetverlies',    5900, 'https://images.unsplash.com/photo-1546483875-ad9014c88eba?w=500&q=80', 'Rotterdam', 'ACE CPT', 6, 'NL, EN', 45, 0, 2900
  UNION ALL SELECT 'trainer.sophie@example.com', 'Mobility en revalidatiegerichte coaching voor veilig opbouwen.',       'Mobility & Revalidatie',   7200, 'https://images.unsplash.com/photo-1518310383802-640c2de311b2?w=500&q=80', 'Utrecht', 'Fysiotrainer certificaat', 10, 'NL, EN, DE', 60, 1, 3900
  UNION ALL SELECT 'trainer.daan@example.com',   'Hyrox en functionele training met focus op prestaties.',               'Hyrox & Functioneel',      6800, 'https://images.unsplash.com/photo-1566753323558-f4e0952af115?w=500&q=80', 'Den Haag', 'CrossFit L1', 7, 'NL, EN', 60, 0, 3400
  UNION ALL SELECT 'trainer.ines@example.com',   'Postnatale en vrouwenkracht trajecten, veilig en doelgericht.',        'Vrouwenkracht',            6400, 'https://images.unsplash.com/photo-1549060279-7e168fcee0c2?w=500&q=80', 'Eindhoven', 'Pre/Postnatal Certified', 9, 'NL, EN', 45, 1, 3200
  UNION ALL SELECT 'trainer.jasper@example.com', 'Marathon voorbereiding en blessurepreventie voor alle niveaus.',       'Hardlopen',                5600, 'https://images.unsplash.com/photo-1531891437562-4301cf35b7e4?w=500&q=80', 'Haarlem', 'Running Coach L2', 5, 'NL, EN', 45, 0, 2500
  UNION ALL SELECT 'trainer.noura@example.com',  'Boksen voor conditie, zelfvertrouwen en stressreductie.',              'Boksen',                   6100, 'https://images.unsplash.com/photo-1599058917212-d750089bc07e?w=500&q=80', 'Tilburg', 'Boxing Coach', 6, 'NL, EN, AR', 60, 0, 3000
  UNION ALL SELECT 'trainer.milan@example.com',  'Calisthenics en bodyweight skills met duidelijke progressie.',         'Calisthenics',             6000, 'https://images.unsplash.com/photo-1583454110551-21f2fa2afe61?w=500&q=80', 'Nijmegen', 'Street Workout Coach', 7, 'NL, EN', 60, 0, 3000
  UNION ALL SELECT 'trainer.fatima@example.com', 'Pilates en core-stability met focus op houding en balans.',            'Pilates',                  5800, 'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=500&q=80', 'Leiden', 'Pilates Mat Instructor', 8, 'NL, EN, FR', 45, 1, 2800
  UNION ALL SELECT 'trainer.thomas@example.com', 'Senior fitness en leefstijlcoaching met rustige opbouw.',              'Senior Fitness',           5400, 'https://images.unsplash.com/photo-1552674605-db6ffd4facb5?w=500&q=80', 'Breda', 'Senior Fit Coach', 12, 'NL', 45, 0, 2500
  UNION ALL SELECT 'jamai1210@live.nl',          'Resultaatgerichte personal trainer voor kracht, conditie en leefstijl.', 'Kracht & Leefstijl',      6700, 'https://images.unsplash.com/photo-1549476464-37392f717541?w=500&q=80', 'Amsterdam', 'NASM CPT, Fitvak A', 9, 'NL, EN', 60, 1, 3200
) d
JOIN gymies_users u ON u.email = d.email
ON DUPLICATE KEY UPDATE
  bio=VALUES(bio),
  specialty=VALUES(specialty),
  hourly_rate_cents=VALUES(hourly_rate_cents),
  avatar_url=VALUES(avatar_url),
  region=VALUES(region),
  trainer_verified_at=VALUES(trainer_verified_at),
  certifications=VALUES(certifications),
  experience_years=VALUES(experience_years),
  languages=VALUES(languages),
  min_session_minutes=VALUES(min_session_minutes),
  is_available=VALUES(is_available),
  featured=VALUES(featured),
  trial_session_cents=VALUES(trial_session_cents);

COMMIT;

START TRANSACTION;

-- Extra dashboard-data voor Jamai traineraccount
INSERT INTO gymies_users (
  email, password_hash, role, display_name, phone, email_verified_at, phone_verified_at
) VALUES
  ('klant.femke@example.com', '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'klant', 'Femke Vermeer', '+31614141414', NOW(), NOW()),
  ('klant.luca@example.com',  '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'klant', 'Luca de Jong',  '+31615151515', NOW(), NOW())
ON DUPLICATE KEY UPDATE
  role='klant',
  display_name=VALUES(display_name),
  phone=VALUES(phone),
  email_verified_at=VALUES(email_verified_at),
  phone_verified_at=VALUES(phone_verified_at);

-- Beschikbaarheid Jamai
INSERT INTO gymies_availability_slots (
  trainer_user_id, day_of_week, start_time, end_time
)
SELECT u.id, d.day_of_week, d.start_time, d.end_time
FROM (
  SELECT 1 AS day_of_week, '07:30:00' AS start_time, '11:30:00' AS end_time
  UNION ALL SELECT 3, '18:00:00', '21:00:00'
  UNION ALL SELECT 6, '09:00:00', '13:00:00'
) d
JOIN gymies_users u ON u.email = 'jamai1210@live.nl'
WHERE NOT EXISTS (
  SELECT 1
  FROM gymies_availability_slots s
  WHERE s.trainer_user_id = u.id
    AND s.day_of_week = d.day_of_week
    AND s.start_time = d.start_time
    AND s.end_time = d.end_time
);

-- Uitzondering: volgende vrijdag niet beschikbaar
INSERT INTO gymies_availability_exceptions (
  trainer_user_id, exception_date, is_available, start_time, end_time
)
SELECT u.id, DATE_ADD(CURDATE(), INTERVAL (12 - DAYOFWEEK(CURDATE())) DAY), 0, NULL, NULL
FROM gymies_users u
WHERE u.email = 'jamai1210@live.nl'
  AND NOT EXISTS (
    SELECT 1
    FROM gymies_availability_exceptions e
    WHERE e.trainer_user_id = u.id
      AND e.exception_date = DATE_ADD(CURDATE(), INTERVAL (12 - DAYOFWEEK(CURDATE())) DAY)
  );

-- Mix van pending/confirmed/completed boekingen voor dashboardcards
INSERT INTO gymies_bookings (
  client_user_id, trainer_user_id, scheduled_at, duration_minutes, status, amount_cents, paid_at, location_type, location_notes
)
SELECT
  c.id,
  t.id,
  d.scheduled_at,
  d.duration_minutes,
  d.status,
  d.amount_cents,
  d.paid_at,
  d.location_type,
  d.location_notes
FROM (
  SELECT 'klant.femke@example.com' AS client_email, DATE_ADD(NOW(), INTERVAL 1 DAY) AS scheduled_at, 60 AS duration_minutes, 'pending' AS status, 6700 AS amount_cents, NULL AS paid_at, 'gym' AS location_type, 'Vondelgym Zuid' AS location_notes
  UNION ALL SELECT 'klant.luca@example.com', DATE_ADD(NOW(), INTERVAL 2 DAY), 60, 'confirmed', 6700, NULL, 'on_site', 'Buitenpark Amsterdam Bos'
  UNION ALL SELECT 'klant.noah@example.com', DATE_ADD(NOW(), INTERVAL 4 DAY), 90, 'confirmed', 9900, NULL, 'online', 'Zoom strength check-in'
  UNION ALL SELECT 'klant.femke@example.com', DATE_SUB(NOW(), INTERVAL 5 DAY), 60, 'completed', 6700, NOW(), 'gym', 'Vondelgym Zuid'
  UNION ALL SELECT 'klant.luca@example.com', DATE_SUB(NOW(), INTERVAL 12 DAY), 60, 'completed', 6700, NOW(), 'on_site', 'Amsterdam Bos'
) d
JOIN gymies_users c ON c.email = d.client_email
JOIN gymies_users t ON t.email = 'jamai1210@live.nl'
WHERE NOT EXISTS (
  SELECT 1
  FROM gymies_bookings b
  WHERE b.client_user_id = c.id
    AND b.trainer_user_id = t.id
    AND b.scheduled_at = d.scheduled_at
);

-- Reviews op afgeronde sessies Jamai
INSERT INTO gymies_reviews (
  booking_id, client_user_id, trainer_user_id, rating, review_text, status, created_at
)
SELECT b.id, b.client_user_id, b.trainer_user_id, d.rating, d.review_text, 'approved', NOW()
FROM (
  SELECT 'klant.femke@example.com' AS client_email, 5 AS rating, 'Super motiverend en duidelijk schema, top coach.' AS review_text, DATE_SUB(NOW(), INTERVAL 5 DAY) AS scheduled_at
  UNION ALL SELECT 'klant.luca@example.com', 4, 'Goede techniek-correcties en fijne energie.', DATE_SUB(NOW(), INTERVAL 12 DAY)
) d
JOIN gymies_users c ON c.email = d.client_email
JOIN gymies_users t ON t.email = 'jamai1210@live.nl'
JOIN gymies_bookings b
  ON b.client_user_id = c.id
 AND b.trainer_user_id = t.id
 AND b.scheduled_at = d.scheduled_at
 AND b.status = 'completed'
WHERE NOT EXISTS (
  SELECT 1 FROM gymies_reviews r WHERE r.booking_id = b.id
);

-- Conversatie + berichten zodat berichtenwidget gevuld is
INSERT INTO gymies_conversations (client_user_id, trainer_user_id, booking_id, created_at, updated_at)
SELECT c.id, t.id, b.id, NOW(), NOW()
FROM gymies_users c
JOIN gymies_users t ON t.email = 'jamai1210@live.nl'
LEFT JOIN gymies_bookings b
  ON b.client_user_id = c.id
 AND b.trainer_user_id = t.id
WHERE c.email = 'klant.femke@example.com'
  AND NOT EXISTS (
    SELECT 1
    FROM gymies_conversations conv
    WHERE conv.client_user_id = c.id
      AND conv.trainer_user_id = t.id
  );

INSERT INTO gymies_messages (conversation_id, from_user_id, body, created_at)
SELECT conv.id, sender.id, d.body, d.created_at
FROM (
  SELECT 'klant.femke@example.com' AS sender_email, 'Hi Jamai, ik wil volgende week extra focus op core.' AS body, DATE_SUB(NOW(), INTERVAL 3 HOUR) AS created_at
  UNION ALL SELECT 'jamai1210@live.nl', 'Top! Ik zet een aangepast schema voor je klaar.' AS body, DATE_SUB(NOW(), INTERVAL 2 HOUR)
) d
JOIN gymies_users sender ON sender.email = d.sender_email
JOIN gymies_users c ON c.email = 'klant.femke@example.com'
JOIN gymies_users t ON t.email = 'jamai1210@live.nl'
JOIN gymies_conversations conv ON conv.client_user_id = c.id AND conv.trainer_user_id = t.id
WHERE NOT EXISTS (
  SELECT 1
  FROM gymies_messages m
  WHERE m.conversation_id = conv.id
    AND m.from_user_id = sender.id
    AND m.body = d.body
);

COMMIT;

START TRANSACTION;

-- Dummy klanten voor review/bookings testdata
INSERT INTO gymies_users (
  email, password_hash, role, display_name, phone, email_verified_at, phone_verified_at
) VALUES
  ('klant.lisa@example.com',  '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'klant', 'Lisa Jansen',  '+31620202020', NOW(), NOW()),
  ('klant.noah@example.com',  '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'klant', 'Noah Smit',    '+31630303030', NOW(), NOW()),
  ('klant.emma@example.com',  '$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C', 'klant', 'Emma de Wit',  '+31640404040', NOW(), NOW())
ON DUPLICATE KEY UPDATE
  role='klant',
  display_name=VALUES(display_name),
  phone=VALUES(phone),
  email_verified_at=VALUES(email_verified_at),
  phone_verified_at=VALUES(phone_verified_at);

-- Completed demo boekingen zodat reviews geldig gekoppeld zijn
INSERT INTO gymies_bookings (
  client_user_id, trainer_user_id, scheduled_at, duration_minutes, status, amount_cents, paid_at, location_type, location_notes
)
SELECT
  c.id,
  t.id,
  d.scheduled_at,
  d.duration_minutes,
  'completed',
  d.amount_cents,
  NOW(),
  d.location_type,
  d.location_notes
FROM (
  SELECT 'klant.lisa@example.com' AS client_email, 'trainer.anne@example.com' AS trainer_email, '2025-01-15 10:00:00' AS scheduled_at, 60 AS duration_minutes, 6500 AS amount_cents, 'on_site' AS location_type, 'Gym Amsterdam Centrum' AS location_notes
  UNION ALL SELECT 'klant.noah@example.com', 'trainer.rayan@example.com', '2025-01-16 19:00:00', 60, 5900, 'online', 'Zoom sessie'
  UNION ALL SELECT 'klant.emma@example.com', 'trainer.sophie@example.com', '2025-01-17 08:30:00', 90, 10800, 'on_site', 'Utrecht Leidsche Rijn'
  UNION ALL SELECT 'klant.lisa@example.com', 'trainer.daan@example.com', '2025-01-18 18:30:00', 60, 6800, 'gym', 'CrossGym Den Haag'
  UNION ALL SELECT 'klant.noah@example.com', 'trainer.ines@example.com', '2025-01-19 11:15:00', 45, 6400, 'on_site', 'Eindhoven Woensel'
  UNION ALL SELECT 'klant.emma@example.com', 'trainer.jasper@example.com', '2025-01-20 07:00:00', 60, 5600, 'on_site', 'Kennemerduinen route'
  UNION ALL SELECT 'klant.lisa@example.com', 'trainer.noura@example.com', '2025-01-21 20:00:00', 60, 6100, 'gym', 'Boksstudio Tilburg'
  UNION ALL SELECT 'klant.noah@example.com', 'trainer.milan@example.com', '2025-01-22 17:45:00', 60, 6000, 'on_site', 'Calisthenics park Nijmegen'
  UNION ALL SELECT 'klant.emma@example.com', 'trainer.fatima@example.com', '2025-01-23 09:00:00', 45, 5800, 'on_site', 'Pilates studio Leiden'
  UNION ALL SELECT 'klant.lisa@example.com', 'trainer.thomas@example.com', '2025-01-24 10:30:00', 45, 5400, 'on_site', 'Breda centrum'
) d
JOIN gymies_users c ON c.email = d.client_email
JOIN gymies_users t ON t.email = d.trainer_email
WHERE NOT EXISTS (
  SELECT 1
  FROM gymies_bookings b
  WHERE b.client_user_id = c.id
    AND b.trainer_user_id = t.id
    AND b.scheduled_at = d.scheduled_at
);

-- Reviews op bovengenoemde completed boekingen
INSERT INTO gymies_reviews (
  booking_id, client_user_id, trainer_user_id, rating, review_text, status, created_at
)
SELECT
  b.id,
  c.id,
  t.id,
  d.rating,
  d.review_text,
  'approved',
  NOW()
FROM (
  SELECT 'klant.lisa@example.com' AS client_email, 'trainer.anne@example.com' AS trainer_email, '2025-01-15 10:00:00' AS scheduled_at, 5 AS rating, 'Super duidelijke uitleg en fijne energie.' AS review_text
  UNION ALL SELECT 'klant.noah@example.com', 'trainer.rayan@example.com', '2025-01-16 19:00:00', 4, 'Goede opbouw en strak schema.'
  UNION ALL SELECT 'klant.emma@example.com', 'trainer.sophie@example.com', '2025-01-17 08:30:00', 5, 'Heel professioneel en blessurevrij opgebouwd.'
  UNION ALL SELECT 'klant.lisa@example.com', 'trainer.daan@example.com', '2025-01-18 18:30:00', 4, 'Intensieve sessie, precies wat ik nodig had.'
  UNION ALL SELECT 'klant.noah@example.com', 'trainer.ines@example.com', '2025-01-19 11:15:00', 5, 'Empathisch en toch resultaatgericht.'
  UNION ALL SELECT 'klant.emma@example.com', 'trainer.jasper@example.com', '2025-01-20 07:00:00', 4, 'Fijne hardloopcoaching met praktische tips.'
  UNION ALL SELECT 'klant.lisa@example.com', 'trainer.noura@example.com', '2025-01-21 20:00:00', 5, 'Top bokstraining, motiverend en veilig.'
  UNION ALL SELECT 'klant.noah@example.com', 'trainer.milan@example.com', '2025-01-22 17:45:00', 4, 'Heldere progressie in oefeningen.'
  UNION ALL SELECT 'klant.emma@example.com', 'trainer.fatima@example.com', '2025-01-23 09:00:00', 5, 'Rustige coach, veel aandacht voor techniek.'
  UNION ALL SELECT 'klant.lisa@example.com', 'trainer.thomas@example.com', '2025-01-24 10:30:00', 4, 'Geduldig en goed afgestemd op niveau.'
) d
JOIN gymies_users c ON c.email = d.client_email
JOIN gymies_users t ON t.email = d.trainer_email
JOIN gymies_bookings b
  ON b.client_user_id = c.id
 AND b.trainer_user_id = t.id
 AND b.scheduled_at = d.scheduled_at
 AND b.status = 'completed'
WHERE NOT EXISTS (
  SELECT 1 FROM gymies_reviews r WHERE r.booking_id = b.id
);

COMMIT;

