-- Plan-filter (Starter/Pro/Studio) verwijderen voor klanten bij trainerzoeken.
-- Klanten hoeven dit niet te zien; het is intern abonnementsinformatie.
-- Alleen nodig als plan eerder was toegevoegd; nieuwe installs hebben het niet.

UPDATE gymies_filter_definitions
SET is_active = 0
WHERE context = 'trainers' AND filter_key = 'plan';
