-- Finalize / herstelstap voor factuurnummering migratie
-- Veilig opnieuw uit te voeren.

SET NAMES utf8mb4;

UPDATE gymies_trainer_invoices
SET trainer_invoice_number = invoice_number
WHERE trainer_invoice_number IS NULL OR trainer_invoice_number = '';

UPDATE gymies_trainer_invoices
SET invoice_date = DATE(COALESCE(created_at, NOW()))
WHERE invoice_date IS NULL;

UPDATE gymies_trainer_invoices
SET due_date = DATE_ADD(invoice_date, INTERVAL 14 DAY)
WHERE due_date IS NULL;

UPDATE gymies_trainer_invoices
SET service_date = invoice_date
WHERE service_date IS NULL;

UPDATE gymies_trainer_invoices
SET service_type = 'personal_training'
WHERE service_type IS NULL OR service_type = '';

UPDATE gymies_trainer_invoices
SET price_ex_vat_cents = amount_cents
WHERE price_ex_vat_cents IS NULL;

UPDATE gymies_trainer_invoices
SET price_inc_vat_cents = total_cents
WHERE price_inc_vat_cents IS NULL;

UPDATE gymies_trainer_invoices
SET company_name = COALESCE(NULLIF(business_name, ''), 'Gymies')
WHERE company_name IS NULL OR company_name = '';

UPDATE gymies_trainer_invoices
SET gymies_invoice_number = CONCAT('GYM-', DATE_FORMAT(COALESCE(created_at, NOW()), '%Y'), '-', LPAD(id, 8, '0'))
WHERE gymies_invoice_number IS NULL OR gymies_invoice_number = '';

SET @gym_idx_exists := (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'gymies_trainer_invoices'
      AND index_name = 'gymies_trainer_invoices_gymies_number_unique'
);
SET @create_gym_idx_sql := IF(
    @gym_idx_exists = 0,
    'CREATE UNIQUE INDEX gymies_trainer_invoices_gymies_number_unique ON gymies_trainer_invoices (gymies_invoice_number)',
    'SELECT 1'
);
PREPARE stmt_create_gym_idx FROM @create_gym_idx_sql;
EXECUTE stmt_create_gym_idx;
DEALLOCATE PREPARE stmt_create_gym_idx;

SET @trainer_idx_exists := (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'gymies_trainer_invoices'
      AND index_name = 'gymies_trainer_invoices_trainer_number_unique'
);
SET @create_trainer_idx_sql := IF(
    @trainer_idx_exists = 0,
    'CREATE UNIQUE INDEX gymies_trainer_invoices_trainer_number_unique ON gymies_trainer_invoices (trainer_user_id, trainer_invoice_number)',
    'SELECT 1'
);
PREPARE stmt_create_trainer_idx FROM @create_trainer_idx_sql;
EXECUTE stmt_create_trainer_idx;
DEALLOCATE PREPARE stmt_create_trainer_idx;

