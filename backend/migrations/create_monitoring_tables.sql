-- Performance Monitoring Tables for Gymies API

-- Performance logs (request timing)
CREATE TABLE IF NOT EXISTS `gymies_performance_logs` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `method` VARCHAR(10) NOT NULL COMMENT 'GET, POST, etc',
    `path` VARCHAR(255) NOT NULL COMMENT 'Request path',
    `status_code` SMALLINT UNSIGNED COMMENT 'HTTP status code',
    `duration_ms` INT UNSIGNED COMMENT 'Request duration in ms',
    `query_count` INT UNSIGNED COMMENT 'Number of DB queries',
    `user_id` BIGINT UNSIGNED COMMENT 'User ID if authenticated',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_created_at` (`created_at`),
    INDEX `idx_duration_ms` (`duration_ms`),
    INDEX `idx_method_path` (`method`, `path`),
    INDEX `idx_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='API request performance metrics for monitoring slow requests';

-- Slow queries log
CREATE TABLE IF NOT EXISTS `gymies_slow_queries` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `sql` VARCHAR(2000) COMMENT 'SQL query (truncated)',
    `bindings_json` JSON COMMENT 'Query bindings',
    `duration_ms` INT UNSIGNED COMMENT 'Query duration in ms',
    `connection` VARCHAR(50) COMMENT 'Database connection name',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_created_at` (`created_at`),
    INDEX `idx_duration_ms` (`duration_ms`),
    FULLTEXT INDEX `ft_sql` (`sql`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Slow query log for performance debugging';

-- Cron job execution log
CREATE TABLE IF NOT EXISTS `gymies_cron_logs` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `job_name` VARCHAR(100) NOT NULL COMMENT 'Cron job name',
    `status` ENUM('success', 'failed', 'skipped') DEFAULT 'success',
    `duration_ms` INT UNSIGNED COMMENT 'Execution duration in ms',
    `message` VARCHAR(1000),
    `result_json` JSON COMMENT 'Job result data',
    `error_message` TEXT COMMENT 'Error details if failed',
    `executed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_job_name` (`job_name`),
    INDEX `idx_status` (`status`),
    INDEX `idx_executed_at` (`executed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Cron job execution tracking for monitoring and debugging';

-- Health check history (for tracking availability)
CREATE TABLE IF NOT EXISTS `gymies_health_check_history` (
    `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `status` ENUM('ok', 'degraded', 'down') NOT NULL,
    `database_ok` BOOLEAN,
    `cache_ok` BOOLEAN,
    `queue_ok` BOOLEAN,
    `storage_ok` BOOLEAN,
    `mollie_ok` BOOLEAN,
    `mail_ok` BOOLEAN,
    `response_time_ms` INT UNSIGNED,
    `timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_timestamp` (`timestamp`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Health check history for uptime monitoring and SLA tracking';
