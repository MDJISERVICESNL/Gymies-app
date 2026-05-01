-- Storefront (stories, video, Instagram) voor dummy trainers – zichtbaar op openbaar profiel.
-- Draai na: alter_gymies_trainer_storefront + alter_gymies_trainer_storefront_instagram
-- Gebruik: php gymies_deploy/run_migrate_gymies_sql_server.php gymies_deploy/seed_gymies_dummy_trainers_storefront.sql

SET NAMES utf8mb4;

INSERT INTO gymies_trainer_storefront (trainer_user_id, success_stories_json, video_pitch_url, instagram_handle, specializations_display, seo_title, seo_description, seo_keywords)
SELECT u.id, '[{"title":"Transformatie","body":"Resultaat na 3 maanden.","image_url":"https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=400"},{"title":"Sessie","body":"Personal training in actie.","image_url":"https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=400"}]', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', 'annedevries_pt', 'Krachttraining', 'Anne de Vries – Personal trainer Amsterdam | Gymies', 'Professionele personal training in Amsterdam.', 'personal trainer amsterdam'
FROM gymies_users u WHERE u.email = 'trainer.anne@example.com' LIMIT 1
ON DUPLICATE KEY UPDATE success_stories_json = VALUES(success_stories_json), video_pitch_url = VALUES(video_pitch_url), instagram_handle = VALUES(instagram_handle);

INSERT INTO gymies_trainer_storefront (trainer_user_id, success_stories_json, video_pitch_url, instagram_handle, specializations_display, seo_title, seo_description, seo_keywords)
SELECT u.id, '[{"title":"Conditie","body":"Groepsessie outdoor.","image_url":"https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=400"},{"title":"Resultaat","body":"Vetverlies traject.","image_url":"https://images.unsplash.com/photo-1531891437562-4301cf35b7e4?w=400"}]', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', 'rayanfitness', 'Conditie & Vetverlies', 'Rayan El Amrani – Personal trainer Rotterdam | Gymies', 'Conditie en vetverlies trajecten.', 'personal trainer rotterdam'
FROM gymies_users u WHERE u.email = 'trainer.rayan@example.com' LIMIT 1
ON DUPLICATE KEY UPDATE success_stories_json = VALUES(success_stories_json), video_pitch_url = VALUES(video_pitch_url), instagram_handle = VALUES(instagram_handle);

INSERT INTO gymies_trainer_storefront (trainer_user_id, success_stories_json, video_pitch_url, instagram_handle, specializations_display, seo_title, seo_description, seo_keywords)
SELECT u.id, '[{"title":"Revalidatie","body":"Blessurevrij trainen.","image_url":"https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=400"},{"title":"Mobility","body":"Beweeg beter.","image_url":"https://images.unsplash.com/photo-1549060279-7e168fcee0c2?w=400"}]', NULL, 'sophievandam_pt', 'Mobility & Revalidatie', 'Sophie van Dam – Personal trainer Utrecht | Gymies', 'Mobility en revalidatie coaching.', 'personal trainer utrecht'
FROM gymies_users u WHERE u.email = 'trainer.sophie@example.com' LIMIT 1
ON DUPLICATE KEY UPDATE success_stories_json = VALUES(success_stories_json), video_pitch_url = VALUES(video_pitch_url), instagram_handle = VALUES(instagram_handle);
