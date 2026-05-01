-- MySQL dump 10.13  Distrib 8.4.7, for Linux (x86_64)
--
-- Host: 127.0.0.1    Database: mdjiservices
-- ------------------------------------------------------
-- Server version	8.4.7-0ubuntu0.25.04.2

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `gymies_admin_alerts`
--

DROP TABLE IF EXISTS `gymies_admin_alerts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_admin_alerts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `alert_type` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  `severity` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'low',
  `title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `message` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `entity_type` varchar(80) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `entity_id` bigint unsigned DEFAULT NULL,
  `status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'open',
  `created_by_user_id` bigint unsigned DEFAULT NULL,
  `acknowledged_by_user_id` bigint unsigned DEFAULT NULL,
  `acknowledged_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_admin_alerts_status_idx` (`status`),
  KEY `gymies_admin_alerts_type_idx` (`alert_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_admin_alerts`
--

LOCK TABLES `gymies_admin_alerts` WRITE;
/*!40000 ALTER TABLE `gymies_admin_alerts` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_admin_alerts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_admin_ip_allowlist`
--

DROP TABLE IF EXISTS `gymies_admin_ip_allowlist`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_admin_ip_allowlist` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `ip_pattern` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'active',
  `created_by_user_id` bigint unsigned DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_admin_ip_allowlist_status_idx` (`status`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_admin_ip_allowlist`
--

LOCK TABLES `gymies_admin_ip_allowlist` WRITE;
/*!40000 ALTER TABLE `gymies_admin_ip_allowlist` DISABLE KEYS */;
INSERT INTO `gymies_admin_ip_allowlist` VALUES (1,'89.205.255.117','active',58,'2026-02-28 04:03:39','2026-02-28 04:03:39');
/*!40000 ALTER TABLE `gymies_admin_ip_allowlist` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_admin_note_templates`
--

DROP TABLE IF EXISTS `gymies_admin_note_templates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_admin_note_templates` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(120) COLLATE utf8mb4_unicode_ci NOT NULL,
  `body` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `category` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'general',
  `sort_order` smallint NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_admin_note_templates_name_category` (`name`,`category`),
  KEY `gymies_admin_note_templates_category` (`category`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_admin_note_templates`
--

LOCK TABLES `gymies_admin_note_templates` WRITE;
/*!40000 ALTER TABLE `gymies_admin_note_templates` DISABLE KEYS */;
INSERT INTO `gymies_admin_note_templates` VALUES (1,'KYC check pending','KYC-check loopt. Klant is geïnformeerd.','ticket',10,'2026-02-28 04:36:41'),(2,'Client contacted','Klant is gecontacteerd; wacht op reactie.','ticket',20,'2026-02-28 04:36:41'),(3,'Refund approved','Terugbetaling goedgekeurd. Verwerkt binnen 5 werkdagen.','ticket',30,'2026-02-28 04:36:41'),(4,'Escalated to specialist','Doorgestuurd naar specialist voor verdere afhandeling.','ticket',40,'2026-02-28 04:36:41'),(5,'Booking incident – no-show','No-show geregistreerd. Trainer heeft klant proberen te bereiken.','booking',10,'2026-02-28 04:36:41'),(6,'Booking incident – dispute','Geschil gemeld. Beide partijen gehoord; follow-up volgt.','booking',20,'2026-02-28 04:36:41'),(7,'Payout blocked – verification','Uitbetaling gepauzeerd tot verificatie is afgerond.','general',10,'2026-02-28 04:36:41'),(8,'Fraude review in progress','Fraudecheck loopt. Geen actie tot conclusie.','general',20,'2026-02-28 04:36:41');
/*!40000 ALTER TABLE `gymies_admin_note_templates` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_admin_permissions`
--

DROP TABLE IF EXISTS `gymies_admin_permissions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_admin_permissions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `permission_key` varchar(160) COLLATE utf8mb4_unicode_ci NOT NULL,
  `permission_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_admin_permissions_permission_key_unique` (`permission_key`)
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_admin_permissions`
--

LOCK TABLES `gymies_admin_permissions` WRITE;
/*!40000 ALTER TABLE `gymies_admin_permissions` DISABLE KEYS */;
INSERT INTO `gymies_admin_permissions` VALUES (1,'admin.access','Admin toegang','2026-02-28 04:02:19','2026-02-28 04:03:06'),(2,'admin.super','Super admin','2026-02-28 04:02:19','2026-02-28 04:03:06'),(3,'admin.users.view','Users bekijken','2026-02-28 04:02:19','2026-02-28 04:03:06'),(4,'admin.users.manage','Users beheren','2026-02-28 04:02:19','2026-02-28 04:03:06'),(5,'admin.payments.view','Payments bekijken','2026-02-28 04:02:19','2026-02-28 04:03:06'),(6,'admin.payouts.view','Payouts bekijken','2026-02-28 04:02:19','2026-02-28 04:03:06'),(7,'admin.payouts.manage','Payouts beheren','2026-02-28 04:02:19','2026-02-28 04:03:06'),(8,'admin.tickets.view','Tickets bekijken','2026-02-28 04:02:19','2026-02-28 04:03:06'),(9,'admin.tickets.manage','Tickets beheren','2026-02-28 04:02:19','2026-02-28 04:03:06'),(10,'admin.bookings.view','Bookings bekijken','2026-02-28 04:02:19','2026-02-28 04:03:06'),(11,'admin.bookings.manage','Bookings beheren','2026-02-28 04:02:19','2026-02-28 04:03:06'),(12,'admin.security.view','Security bekijken','2026-02-28 04:02:19','2026-02-28 04:03:06'),(13,'admin.security.manage','Security beheren','2026-02-28 04:02:19','2026-02-28 04:03:06'),(14,'admin.audit.view','Audit bekijken','2026-02-28 04:02:19','2026-02-28 04:03:06'),(15,'admin.organisations.view','Organisaties bekijken','2026-02-28 04:02:19','2026-02-28 04:03:06'),(16,'admin.organisations.manage','Organisaties beheren','2026-02-28 04:02:19','2026-02-28 04:03:06');
/*!40000 ALTER TABLE `gymies_admin_permissions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_admin_role_permissions`
--

DROP TABLE IF EXISTS `gymies_admin_role_permissions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_admin_role_permissions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `role_id` bigint unsigned NOT NULL,
  `permission_id` bigint unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_admin_role_permissions_role_perm_unique` (`role_id`,`permission_id`),
  KEY `gymies_admin_role_permissions_role_idx` (`role_id`),
  KEY `gymies_admin_role_permissions_perm_idx` (`permission_id`)
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_admin_role_permissions`
--

LOCK TABLES `gymies_admin_role_permissions` WRITE;
/*!40000 ALTER TABLE `gymies_admin_role_permissions` DISABLE KEYS */;
INSERT INTO `gymies_admin_role_permissions` VALUES (1,1,1,'2026-02-28 04:02:19'),(2,1,14,'2026-02-28 04:02:19'),(3,1,11,'2026-02-28 04:02:19'),(4,1,10,'2026-02-28 04:02:19'),(5,1,16,'2026-02-28 04:02:19'),(6,1,15,'2026-02-28 04:02:19'),(7,1,5,'2026-02-28 04:02:19'),(8,1,7,'2026-02-28 04:02:19'),(9,1,6,'2026-02-28 04:02:19'),(10,1,13,'2026-02-28 04:02:19'),(11,1,12,'2026-02-28 04:02:19'),(12,1,2,'2026-02-28 04:02:19'),(13,1,9,'2026-02-28 04:02:19'),(14,1,8,'2026-02-28 04:02:19'),(15,1,4,'2026-02-28 04:02:19'),(16,1,3,'2026-02-28 04:02:19');
/*!40000 ALTER TABLE `gymies_admin_role_permissions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_admin_roles`
--

DROP TABLE IF EXISTS `gymies_admin_roles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_admin_roles` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `role_key` varchar(120) COLLATE utf8mb4_unicode_ci NOT NULL,
  `role_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'active',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_admin_roles_role_key_unique` (`role_key`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_admin_roles`
--

LOCK TABLES `gymies_admin_roles` WRITE;
/*!40000 ALTER TABLE `gymies_admin_roles` DISABLE KEYS */;
INSERT INTO `gymies_admin_roles` VALUES (1,'super_admin','Super Admin','active','2026-02-28 04:02:19','2026-02-28 04:03:06');
/*!40000 ALTER TABLE `gymies_admin_roles` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_admin_saved_views`
--

DROP TABLE IF EXISTS `gymies_admin_saved_views`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_admin_saved_views` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned DEFAULT NULL,
  `name` varchar(120) COLLATE utf8mb4_unicode_ci NOT NULL,
  `entity_type` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL,
  `filters` json NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_admin_saved_views_user_entity` (`user_id`,`entity_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_admin_saved_views`
--

LOCK TABLES `gymies_admin_saved_views` WRITE;
/*!40000 ALTER TABLE `gymies_admin_saved_views` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_admin_saved_views` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_api_error_logs`
--

DROP TABLE IF EXISTS `gymies_api_error_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_api_error_logs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned DEFAULT NULL,
  `endpoint` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `error_code` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `message` text COLLATE utf8mb4_unicode_ci,
  `context_json` json DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_api_error_logs_user` (`user_id`),
  CONSTRAINT `gymies_api_error_logs_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_api_error_logs`
--

LOCK TABLES `gymies_api_error_logs` WRITE;
/*!40000 ALTER TABLE `gymies_api_error_logs` DISABLE KEYS */;
INSERT INTO `gymies_api_error_logs` VALUES (1,27,'api/gymies/ops/run-backup','HTTP_500','Server error response',NULL,'2026-02-27 21:17:43'),(2,27,'api/gymies/ops/run-backup','HTTP_500','Server error response',NULL,'2026-02-27 21:17:46'),(3,27,'trainer/report-issue','TRAINER_REPORTED_ISSUE','Trainer meldde probleem vanuit dashboard','{\"screen\": \"trainer_dashboard\", \"last_error\": null, \"upcoming_count\": 3, \"pending_bookings\": 0}','2026-02-27 21:17:49'),(4,46,'api/gymies/gym/dashboard','HTTP_500','Server error response',NULL,'2026-02-28 00:50:16'),(5,46,'gym/cache-invalidation-event','GYM_CACHE_INVALIDATION_EVENT','Gym cache invalidation event logged','{\"reason\": \"organisation_renamed\", \"metadata\": {\"trigger\": \"update_settings\", \"new_name\": \"Powerhousegym\", \"previous_name\": \"powerhousegym\"}, \"requested_at\": \"2026-02-28T00:54:48+00:00\", \"organisation_id\": 2}','2026-02-28 00:54:48'),(6,58,'GET api/gymies/vault-console/users','HTTP_500','Server error response',NULL,'2026-02-28 04:17:09'),(7,58,'GET api/gymies/vault-console/payouts','HTTP_500','Server error response',NULL,'2026-02-28 04:17:09');
/*!40000 ALTER TABLE `gymies_api_error_logs` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_app_versions`
--

DROP TABLE IF EXISTS `gymies_app_versions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_app_versions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `platform` enum('web','ios','android','api') COLLATE utf8mb4_unicode_ci NOT NULL,
  `version` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL,
  `build_number` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `released_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_app_versions_platform` (`platform`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_app_versions`
--

LOCK TABLES `gymies_app_versions` WRITE;
/*!40000 ALTER TABLE `gymies_app_versions` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_app_versions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_audit_log`
--

DROP TABLE IF EXISTS `gymies_audit_log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_audit_log` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned DEFAULT NULL COMMENT 'Wie (nullable bij systeem)',
  `action` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'created, updated, cancelled, etc.',
  `entity_type` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'booking, user, invoice, etc.',
  `entity_id` bigint unsigned DEFAULT NULL,
  `old_values` json DEFAULT NULL,
  `new_values` json DEFAULT NULL,
  `ip_address` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_audit_log_user` (`user_id`),
  KEY `gymies_audit_log_entity` (`entity_type`,`entity_id`),
  KEY `gymies_audit_log_created` (`created_at`),
  CONSTRAINT `gymies_audit_log_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_audit_log`
--

LOCK TABLES `gymies_audit_log` WRITE;
/*!40000 ALTER TABLE `gymies_audit_log` DISABLE KEYS */;
INSERT INTO `gymies_audit_log` VALUES (1,27,'trainer_reported_issue','support',NULL,NULL,'{\"context\": {\"screen\": \"trainer_dashboard\", \"last_error\": null, \"upcoming_count\": 3, \"pending_bookings\": 0}, \"message\": \"Trainer meldde probleem vanuit dashboard\"}','89.205.255.117','2026-02-27 21:17:49'),(2,46,'gym_settings_updated','organisation',2,NULL,'{\"name\": \"Powerhousegym\", \"updated_at\": \"2026-02-28T00:54:48.240668Z\", \"contact_email\": \"powerhousegym@trainmate.app\"}','89.205.255.117','2026-02-28 00:54:48'),(3,46,'gym_cache_invalidation_event','organisation',2,NULL,'{\"reason\": \"organisation_renamed\", \"metadata\": {\"trigger\": \"update_settings\", \"new_name\": \"Powerhousegym\", \"previous_name\": \"powerhousegym\"}, \"requested_at\": \"2026-02-28T00:54:48+00:00\", \"organisation_id\": 2}','89.205.255.117','2026-02-28 00:54:48'),(4,46,'gym_trainer_status_updated','organisation_trainer',1,'{\"status\": \"active\"}','{\"status\": \"inactive\", \"organisation_id\": 2, \"trainer_user_id\": 47}','89.205.255.117','2026-02-28 01:16:28'),(5,46,'gym_trainer_status_updated','organisation_trainer',1,'{\"status\": \"inactive\"}','{\"status\": \"active\", \"organisation_id\": 2, \"trainer_user_id\": 47}','89.205.255.117','2026-02-28 01:16:28'),(6,46,'gym_booking_reminder_requested','booking',30,NULL,'{\"organisation_id\": 2}','89.205.255.117','2026-02-28 02:13:28'),(7,46,'gym_client_reengagement_requested','user',55,NULL,'{\"organisation_id\": 2}','89.205.255.117','2026-02-28 02:13:29');
/*!40000 ALTER TABLE `gymies_audit_log` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_auth_attempts`
--

DROP TABLE IF EXISTS `gymies_auth_attempts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_auth_attempts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `ip_address` varchar(45) COLLATE utf8mb4_unicode_ci NOT NULL,
  `was_success` tinyint(1) NOT NULL DEFAULT '0',
  `blocked_until` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_auth_attempts_email_created_idx` (`email`,`created_at`),
  KEY `gymies_auth_attempts_ip_created_idx` (`ip_address`,`created_at`),
  KEY `gymies_auth_attempts_blocked_idx` (`blocked_until`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_auth_attempts`
--

LOCK TABLES `gymies_auth_attempts` WRITE;
/*!40000 ALTER TABLE `gymies_auth_attempts` DISABLE KEYS */;
INSERT INTO `gymies_auth_attempts` VALUES (1,'admin@trainmate.app','89.205.255.117',1,NULL,'2026-02-28 04:07:43'),(2,'admin@trainmate.app','89.205.255.117',1,NULL,'2026-02-28 04:12:14'),(3,'admin@trainmate.app','89.205.255.117',1,NULL,'2026-02-28 04:17:09'),(4,'admin@trainmate.app','89.205.255.117',1,NULL,'2026-02-28 04:21:39'),(5,'admin@trainmate.app','89.205.255.117',1,NULL,'2026-02-28 04:39:28'),(6,'admin@trainmate.app','89.205.255.117',1,NULL,'2026-02-28 04:40:47');
/*!40000 ALTER TABLE `gymies_auth_attempts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_availability_exceptions`
--

DROP TABLE IF EXISTS `gymies_availability_exceptions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_availability_exceptions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_user_id` bigint unsigned NOT NULL,
  `exception_date` date NOT NULL,
  `is_available` tinyint(1) NOT NULL DEFAULT '0' COMMENT '0=niet beschikbaar, 1=extra beschikbaar',
  `start_time` time DEFAULT NULL COMMENT 'Bij is_available=1: specifieke slot',
  `end_time` time DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_availability_exceptions_trainer` (`trainer_user_id`),
  KEY `gymies_availability_exceptions_date` (`exception_date`),
  CONSTRAINT `gymies_availability_exceptions_user_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_availability_exceptions`
--

LOCK TABLES `gymies_availability_exceptions` WRITE;
/*!40000 ALTER TABLE `gymies_availability_exceptions` DISABLE KEYS */;
INSERT INTO `gymies_availability_exceptions` VALUES (1,27,'2026-03-05',0,NULL,NULL,'2026-02-27 14:10:11');
/*!40000 ALTER TABLE `gymies_availability_exceptions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_availability_slots`
--

DROP TABLE IF EXISTS `gymies_availability_slots`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_availability_slots` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_user_id` bigint unsigned NOT NULL,
  `day_of_week` tinyint unsigned NOT NULL COMMENT '1=maandag t/m 7=zondag',
  `start_time` time NOT NULL,
  `end_time` time NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_availability_slots_trainer` (`trainer_user_id`),
  KEY `gymies_availability_slots_day` (`day_of_week`),
  CONSTRAINT `gymies_availability_slots_user_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_availability_slots`
--

LOCK TABLES `gymies_availability_slots` WRITE;
/*!40000 ALTER TABLE `gymies_availability_slots` DISABLE KEYS */;
INSERT INTO `gymies_availability_slots` VALUES (1,27,1,'07:30:00','11:30:00','2026-02-27 14:10:11'),(2,27,3,'18:00:00','21:00:00','2026-02-27 14:10:11'),(3,27,6,'09:00:00','13:00:00','2026-02-27 14:10:11');
/*!40000 ALTER TABLE `gymies_availability_slots` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_backup_runs`
--

DROP TABLE IF EXISTS `gymies_backup_runs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_backup_runs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `started_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `finished_at` timestamp NULL DEFAULT NULL,
  `status` enum('running','success','failed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'running',
  `backup_location` varchar(512) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `notes` text COLLATE utf8mb4_unicode_ci,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_backup_runs`
--

LOCK TABLES `gymies_backup_runs` WRITE;
/*!40000 ALTER TABLE `gymies_backup_runs` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_backup_runs` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_booking_participants`
--

DROP TABLE IF EXISTS `gymies_booking_participants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_booking_participants` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `booking_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned DEFAULT NULL COMMENT 'Kan leeg zijn totdat invite geaccepteerd is',
  `invited_email` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `participant_role` enum('initiator','invitee') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'invitee',
  `amount_cents` int unsigned NOT NULL,
  `payment_status` enum('pending','paid','failed','expired') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `paid_at` timestamp NULL DEFAULT NULL,
  `invite_token` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `invite_expires_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_booking_participants_booking_user_unique` (`booking_id`,`user_id`),
  KEY `gymies_booking_participants_booking` (`booking_id`),
  KEY `gymies_booking_participants_invited_email` (`invited_email`),
  KEY `gymies_booking_participants_user_fk` (`user_id`),
  CONSTRAINT `gymies_booking_participants_booking_fk` FOREIGN KEY (`booking_id`) REFERENCES `gymies_bookings` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_booking_participants_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_booking_participants`
--

LOCK TABLES `gymies_booking_participants` WRITE;
/*!40000 ALTER TABLE `gymies_booking_participants` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_booking_participants` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_booking_promo`
--

DROP TABLE IF EXISTS `gymies_booking_promo`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_booking_promo` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `booking_id` bigint unsigned NOT NULL,
  `promo_code_id` bigint unsigned NOT NULL,
  `discount_applied_cents` int unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_booking_promo_booking_unique` (`booking_id`),
  KEY `gymies_booking_promo_code_fk` (`promo_code_id`),
  CONSTRAINT `gymies_booking_promo_booking_fk` FOREIGN KEY (`booking_id`) REFERENCES `gymies_bookings` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_booking_promo_code_fk` FOREIGN KEY (`promo_code_id`) REFERENCES `gymies_promo_codes` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_booking_promo`
--

LOCK TABLES `gymies_booking_promo` WRITE;
/*!40000 ALTER TABLE `gymies_booking_promo` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_booking_promo` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_bookings`
--

DROP TABLE IF EXISTS `gymies_bookings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_bookings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `client_user_id` bigint unsigned NOT NULL,
  `trainer_user_id` bigint unsigned NOT NULL,
  `scheduled_at` datetime NOT NULL,
  `duration_minutes` int unsigned NOT NULL DEFAULT '60',
  `status` enum('pending','confirmed','cancelled','completed','no_show') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `recurrence_parent_booking_id` bigint unsigned DEFAULT NULL COMMENT 'Bovenliggende boeking in reeks',
  `recurrence_interval_weeks` tinyint unsigned DEFAULT NULL COMMENT '1=wekelijks, 2=tweewekelijks',
  `recurrence_count` int unsigned DEFAULT NULL COMMENT 'Aantal sessies in reeks',
  `amount_cents` int unsigned DEFAULT NULL,
  `payment_provider_id` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Mollie/Stripe payment id',
  `paid_at` timestamp NULL DEFAULT NULL,
  `split_payment_enabled` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Betaling in delen/deelnemers',
  `split_paid_cents` int unsigned DEFAULT NULL COMMENT 'Totaal betaald via delen',
  `platform_fee_cents` int unsigned DEFAULT NULL COMMENT 'Platform fee per boeking',
  `trainer_payout_cents` int unsigned DEFAULT NULL COMMENT 'Uitbetaling trainer na fee',
  `auto_confirm_at` timestamp NULL DEFAULT NULL COMMENT 'Automatisch bevestigen na deadline',
  `confirmation_expires_at` timestamp NULL DEFAULT NULL COMMENT 'Als niet gehaald: annuleren',
  `reminder_24h_sent_at` timestamp NULL DEFAULT NULL,
  `reminder_1h_sent_at` timestamp NULL DEFAULT NULL,
  `cancellation_policy_id` bigint unsigned DEFAULT NULL,
  `location_type` enum('online','on_site','gym') COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Waar vindt de sessie plaats',
  `location_notes` text COLLATE utf8mb4_unicode_ci COMMENT 'Adres, Zoom-link, sportschoolnaam, etc.',
  `client_notes` text COLLATE utf8mb4_unicode_ci COMMENT 'Opmerking van klant bij boeken',
  `trainer_notes` text COLLATE utf8mb4_unicode_ci COMMENT 'Interne opmerking trainer (niet zichtbaar voor klant)',
  `cancelled_at` timestamp NULL DEFAULT NULL,
  `cancelled_by_user_id` bigint unsigned DEFAULT NULL COMMENT 'Wie heeft geannuleerd (user_id)',
  `package_id` bigint unsigned DEFAULT NULL COMMENT 'Indien boeking van strippenkaart',
  `sessions_remaining` int unsigned DEFAULT NULL COMMENT 'Resterende sessies van pakket na deze boeking',
  `trainer_location_id` bigint unsigned DEFAULT NULL COMMENT 'Gekozen locatie van trainer',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `organisation_id` bigint unsigned DEFAULT NULL COMMENT 'Gym/organisatie voor payout flow',
  `payout_route` enum('direct_trainer','via_organisation') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'direct_trainer',
  PRIMARY KEY (`id`),
  KEY `gymies_bookings_client` (`client_user_id`),
  KEY `gymies_bookings_trainer` (`trainer_user_id`),
  KEY `gymies_bookings_scheduled` (`scheduled_at`),
  KEY `gymies_bookings_status` (`status`),
  KEY `gymies_bookings_package` (`package_id`),
  KEY `gymies_bookings_recurrence_parent` (`recurrence_parent_booking_id`),
  KEY `gymies_bookings_cancelled_by_fk` (`cancelled_by_user_id`),
  KEY `gymies_bookings_location_fk` (`trainer_location_id`),
  KEY `gymies_bookings_cancellation_policy_fk` (`cancellation_policy_id`),
  KEY `gymies_bookings_organisation` (`organisation_id`),
  CONSTRAINT `gymies_bookings_cancellation_policy_fk` FOREIGN KEY (`cancellation_policy_id`) REFERENCES `gymies_cancellation_policies` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_bookings_cancelled_by_fk` FOREIGN KEY (`cancelled_by_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_bookings_client_fk` FOREIGN KEY (`client_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_bookings_location_fk` FOREIGN KEY (`trainer_location_id`) REFERENCES `gymies_trainer_locations` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_bookings_organisation_fk` FOREIGN KEY (`organisation_id`) REFERENCES `gymies_organisations` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_bookings_package_fk` FOREIGN KEY (`package_id`) REFERENCES `gymies_packages` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_bookings_recurrence_parent_fk` FOREIGN KEY (`recurrence_parent_booking_id`) REFERENCES `gymies_bookings` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_bookings_trainer_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=32 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_bookings`
--

LOCK TABLES `gymies_bookings` WRITE;
/*!40000 ALTER TABLE `gymies_bookings` DISABLE KEYS */;
INSERT INTO `gymies_bookings` VALUES (1,2,3,'2026-02-28 10:00:00',60,'pending',NULL,NULL,NULL,NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 03:18:23','2026-02-27 03:18:23',NULL,'direct_trainer'),(2,2,6,'2026-02-28 08:00:00',60,'pending',NULL,NULL,NULL,NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 03:55:38','2026-02-27 03:55:38',NULL,'direct_trainer'),(3,23,3,'2025-01-15 10:00:00',60,'completed',NULL,NULL,NULL,6500,NULL,'2026-02-27 04:14:26',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'on_site','Gym Amsterdam Centrum',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 04:14:26',NULL,'direct_trainer'),(4,24,4,'2025-01-16 19:00:00',60,'completed',NULL,NULL,NULL,5900,NULL,'2026-02-27 04:14:26',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'online','Zoom sessie',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 04:14:26',NULL,'direct_trainer'),(5,25,5,'2025-01-17 08:30:00',90,'completed',NULL,NULL,NULL,10800,NULL,'2026-02-27 04:14:26',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'on_site','Utrecht Leidsche Rijn',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 04:14:26',NULL,'direct_trainer'),(6,23,6,'2025-01-18 18:30:00',60,'completed',NULL,NULL,NULL,6800,NULL,'2026-02-27 04:14:26',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'gym','CrossGym Den Haag',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 04:14:26',NULL,'direct_trainer'),(7,24,7,'2025-01-19 11:15:00',45,'completed',NULL,NULL,NULL,6400,NULL,'2026-02-27 04:14:26',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'on_site','Eindhoven Woensel',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 04:14:26',NULL,'direct_trainer'),(8,25,8,'2025-01-20 07:00:00',60,'completed',NULL,NULL,NULL,5600,NULL,'2026-02-27 04:14:26',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'on_site','Kennemerduinen route',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 04:14:26',NULL,'direct_trainer'),(9,23,9,'2025-01-21 20:00:00',60,'completed',NULL,NULL,NULL,6100,NULL,'2026-02-27 04:14:26',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'gym','Boksstudio Tilburg',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 04:14:26',NULL,'direct_trainer'),(10,24,10,'2025-01-22 17:45:00',60,'completed',NULL,NULL,NULL,6000,NULL,'2026-02-27 04:14:26',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'on_site','Calisthenics park Nijmegen',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 04:14:26',NULL,'direct_trainer'),(11,25,11,'2025-01-23 09:00:00',45,'completed',NULL,NULL,NULL,5800,NULL,'2026-02-27 04:14:26',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'on_site','Pilates studio Leiden',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 04:14:26',NULL,'direct_trainer'),(12,23,12,'2025-01-24 10:30:00',45,'completed',NULL,NULL,NULL,5400,NULL,'2026-02-27 04:14:26',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'on_site','Breda centrum',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 04:14:26',NULL,'direct_trainer'),(18,39,27,'2026-02-28 14:10:11',60,'confirmed',NULL,NULL,NULL,6700,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'gym','Vondelgym Zuid',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 14:10:11','2026-02-27 14:11:08',NULL,'direct_trainer'),(19,40,27,'2026-03-01 14:10:11',60,'confirmed',NULL,NULL,NULL,6700,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'on_site','Buitenpark Amsterdam Bos',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'direct_trainer'),(20,24,27,'2026-03-03 14:10:11',90,'confirmed',NULL,NULL,NULL,9900,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'online','Zoom strength check-in',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'direct_trainer'),(21,39,27,'2026-02-22 14:10:11',60,'completed',NULL,NULL,NULL,6700,NULL,'2026-02-27 14:10:11',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'gym','Vondelgym Zuid',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'direct_trainer'),(22,40,27,'2026-02-15 14:10:11',60,'completed',NULL,NULL,NULL,6700,NULL,'2026-02-27 14:10:11',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'on_site','Amsterdam Bos',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'direct_trainer'),(25,2,11,'2026-02-28 10:00:00',60,'pending',NULL,NULL,NULL,NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 19:06:44','2026-02-27 19:06:44',NULL,'direct_trainer'),(26,2,3,'2026-02-28 08:45:00',60,'pending',NULL,NULL,NULL,NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-27 19:56:25','2026-02-27 19:56:25',NULL,'direct_trainer'),(27,52,47,'2026-02-26 10:00:00',60,'completed',NULL,NULL,NULL,6500,NULL,'2026-02-28 00:55:45',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'gym','Powerhouse Gym zaal A [seed-powerhouse]','seed booking powerhousegym',NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45',2,'via_organisation'),(28,53,48,'2026-02-27 13:30:00',60,'confirmed',NULL,NULL,NULL,7000,NULL,'2026-02-28 00:55:45',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'gym','Powerhouse Gym zaal B [seed-powerhouse]','seed booking powerhousegym',NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45',2,'via_organisation'),(29,54,49,'2026-03-01 17:00:00',45,'pending',NULL,NULL,NULL,5500,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'gym','Powerhouse Gym zone cardio [seed-powerhouse]','seed booking powerhousegym',NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45',2,'via_organisation'),(30,55,47,'2026-03-03 09:00:00',60,'cancelled',NULL,NULL,NULL,6500,NULL,NULL,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'gym','Powerhouse Gym zaal A [seed-powerhouse]','seed booking powerhousegym',NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45',2,'via_organisation'),(31,57,47,'2026-02-23 12:00:00',60,'no_show',NULL,NULL,NULL,6800,NULL,'2026-02-28 00:57:19',0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'gym','Powerhouse no-show edge-case seed','No-show test booking',NULL,NULL,NULL,NULL,NULL,NULL,'2026-02-28 00:57:19','2026-02-28 00:57:19',2,'via_organisation');
/*!40000 ALTER TABLE `gymies_bookings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_cancellation_policies`
--

DROP TABLE IF EXISTS `gymies_cancellation_policies`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_cancellation_policies` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_user_id` bigint unsigned DEFAULT NULL COMMENT 'NULL = globaal platformbeleid',
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `hours_before` int unsigned NOT NULL COMMENT 'Minimaal X uur van tevoren annuleren',
  `refund_percent` tinyint unsigned NOT NULL COMMENT '0-100',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_cancellation_policies_trainer` (`trainer_user_id`),
  CONSTRAINT `gymies_cancellation_policies_user_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_cancellation_policies`
--

LOCK TABLES `gymies_cancellation_policies` WRITE;
/*!40000 ALTER TABLE `gymies_cancellation_policies` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_cancellation_policies` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_conversations`
--

DROP TABLE IF EXISTS `gymies_conversations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_conversations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `client_user_id` bigint unsigned NOT NULL,
  `trainer_user_id` bigint unsigned NOT NULL,
  `booking_id` bigint unsigned DEFAULT NULL COMMENT 'Optioneel: gesprek over een boeking',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_conversations_client` (`client_user_id`),
  KEY `gymies_conversations_trainer` (`trainer_user_id`),
  KEY `gymies_conversations_booking` (`booking_id`),
  CONSTRAINT `gymies_conversations_booking_fk` FOREIGN KEY (`booking_id`) REFERENCES `gymies_bookings` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_conversations_client_fk` FOREIGN KEY (`client_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_conversations_trainer_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_conversations`
--

LOCK TABLES `gymies_conversations` WRITE;
/*!40000 ALTER TABLE `gymies_conversations` DISABLE KEYS */;
INSERT INTO `gymies_conversations` VALUES (1,39,27,18,'2026-02-27 14:10:11','2026-02-27 14:10:11'),(2,39,27,21,'2026-02-27 14:10:11','2026-02-27 14:10:11'),(4,40,27,22,'2026-02-27 15:12:54','2026-02-27 21:19:34');
/*!40000 ALTER TABLE `gymies_conversations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_cookie_preferences`
--

DROP TABLE IF EXISTS `gymies_cookie_preferences`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_cookie_preferences` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `analytics_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `marketing_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `functional_enabled` tinyint(1) NOT NULL DEFAULT '1',
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_cookie_preferences_user_unique` (`user_id`),
  CONSTRAINT `gymies_cookie_preferences_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_cookie_preferences`
--

LOCK TABLES `gymies_cookie_preferences` WRITE;
/*!40000 ALTER TABLE `gymies_cookie_preferences` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_cookie_preferences` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_dashboard_widgets`
--

DROP TABLE IF EXISTS `gymies_dashboard_widgets`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_dashboard_widgets` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `widget_type` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `position` int unsigned NOT NULL DEFAULT '0',
  `config_json` json DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_dashboard_widgets_user` (`user_id`),
  CONSTRAINT `gymies_dashboard_widgets_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_dashboard_widgets`
--

LOCK TABLES `gymies_dashboard_widgets` WRITE;
/*!40000 ALTER TABLE `gymies_dashboard_widgets` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_dashboard_widgets` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_disputes`
--

DROP TABLE IF EXISTS `gymies_disputes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_disputes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `booking_id` bigint unsigned NOT NULL,
  `raised_by_user_id` bigint unsigned NOT NULL,
  `reason` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `details` text COLLATE utf8mb4_unicode_ci,
  `status` enum('open','in_progress','resolved','rejected') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'open',
  `resolution_notes` text COLLATE utf8mb4_unicode_ci,
  `closed_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_disputes_booking` (`booking_id`),
  KEY `gymies_disputes_user_fk` (`raised_by_user_id`),
  CONSTRAINT `gymies_disputes_booking_fk` FOREIGN KEY (`booking_id`) REFERENCES `gymies_bookings` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_disputes_user_fk` FOREIGN KEY (`raised_by_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_disputes`
--

LOCK TABLES `gymies_disputes` WRITE;
/*!40000 ALTER TABLE `gymies_disputes` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_disputes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_document_uploads`
--

DROP TABLE IF EXISTS `gymies_document_uploads`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_document_uploads` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `type` enum('insurance','id','contract','certificate','other') COLLATE utf8mb4_unicode_ci NOT NULL,
  `file_url` varchar(512) COLLATE utf8mb4_unicode_ci NOT NULL,
  `verified_at` timestamp NULL DEFAULT NULL,
  `verified_by_user_id` bigint unsigned DEFAULT NULL,
  `expires_at` date DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_document_uploads_user` (`user_id`),
  KEY `gymies_document_uploads_verifier_fk` (`verified_by_user_id`),
  CONSTRAINT `gymies_document_uploads_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_document_uploads_verifier_fk` FOREIGN KEY (`verified_by_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_document_uploads`
--

LOCK TABLES `gymies_document_uploads` WRITE;
/*!40000 ALTER TABLE `gymies_document_uploads` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_document_uploads` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_favorites`
--

DROP TABLE IF EXISTS `gymies_favorites`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_favorites` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `client_user_id` bigint unsigned NOT NULL,
  `trainer_user_id` bigint unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_favorites_unique` (`client_user_id`,`trainer_user_id`),
  KEY `gymies_favorites_client` (`client_user_id`),
  KEY `gymies_favorites_trainer` (`trainer_user_id`),
  CONSTRAINT `gymies_favorites_client_fk` FOREIGN KEY (`client_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_favorites_trainer_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_favorites`
--

LOCK TABLES `gymies_favorites` WRITE;
/*!40000 ALTER TABLE `gymies_favorites` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_favorites` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_group_session_participants`
--

DROP TABLE IF EXISTS `gymies_group_session_participants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_group_session_participants` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `group_session_id` bigint unsigned NOT NULL,
  `client_user_id` bigint unsigned NOT NULL,
  `status` enum('pending','confirmed','cancelled','waitlist') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `amount_cents` int unsigned DEFAULT NULL,
  `paid_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_group_session_participants_unique` (`group_session_id`,`client_user_id`),
  KEY `gymies_group_session_participants_user_fk` (`client_user_id`),
  CONSTRAINT `gymies_group_session_participants_session_fk` FOREIGN KEY (`group_session_id`) REFERENCES `gymies_group_sessions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_group_session_participants_user_fk` FOREIGN KEY (`client_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_group_session_participants`
--

LOCK TABLES `gymies_group_session_participants` WRITE;
/*!40000 ALTER TABLE `gymies_group_session_participants` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_group_session_participants` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_group_sessions`
--

DROP TABLE IF EXISTS `gymies_group_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_group_sessions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_user_id` bigint unsigned NOT NULL,
  `title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `scheduled_at` datetime NOT NULL,
  `duration_minutes` int unsigned NOT NULL DEFAULT '60',
  `max_participants` int unsigned NOT NULL DEFAULT '10',
  `price_cents` int unsigned NOT NULL,
  `location_type` enum('online','on_site','gym') COLLATE utf8mb4_unicode_ci DEFAULT 'gym',
  `trainer_location_id` bigint unsigned DEFAULT NULL,
  `recurrence_interval_weeks` tinyint unsigned DEFAULT NULL COMMENT '1=wekelijks,2=tweewekelijks',
  `recurrence_count` int unsigned DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_group_sessions_trainer` (`trainer_user_id`),
  KEY `gymies_group_sessions_scheduled` (`scheduled_at`),
  KEY `gymies_group_sessions_location_fk` (`trainer_location_id`),
  CONSTRAINT `gymies_group_sessions_location_fk` FOREIGN KEY (`trainer_location_id`) REFERENCES `gymies_trainer_locations` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_group_sessions_user_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_group_sessions`
--

LOCK TABLES `gymies_group_sessions` WRITE;
/*!40000 ALTER TABLE `gymies_group_sessions` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_group_sessions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_idempotency_keys`
--

DROP TABLE IF EXISTS `gymies_idempotency_keys`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_idempotency_keys` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned DEFAULT NULL,
  `endpoint` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `idempotency_key` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `request_hash` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status_code` int NOT NULL,
  `response_json` json DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_idempotency_unique` (`user_id`,`endpoint`,`idempotency_key`),
  KEY `gymies_idempotency_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_idempotency_keys`
--

LOCK TABLES `gymies_idempotency_keys` WRITE;
/*!40000 ALTER TABLE `gymies_idempotency_keys` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_idempotency_keys` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_invoice_batches`
--

DROP TABLE IF EXISTS `gymies_invoice_batches`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_invoice_batches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `period_year` smallint unsigned NOT NULL,
  `period_month` tinyint unsigned NOT NULL,
  `total_cents` int unsigned NOT NULL,
  `vat_cents` int unsigned NOT NULL DEFAULT '0',
  `status` enum('draft','issued','paid') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'draft',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_invoice_batches_unique` (`user_id`,`period_year`,`period_month`),
  CONSTRAINT `gymies_invoice_batches_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_invoice_batches`
--

LOCK TABLES `gymies_invoice_batches` WRITE;
/*!40000 ALTER TABLE `gymies_invoice_batches` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_invoice_batches` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_invoices`
--

DROP TABLE IF EXISTS `gymies_invoices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_invoices` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `invoice_number` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Uniek factuurnummer',
  `user_id` bigint unsigned NOT NULL COMMENT 'Klant of trainer (aan wie/van wie)',
  `booking_id` bigint unsigned DEFAULT NULL,
  `amount_cents` int unsigned NOT NULL,
  `vat_cents` int unsigned DEFAULT '0',
  `status` enum('draft','sent','paid','cancelled') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'draft',
  `pdf_url` varchar(512) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_invoices_number_unique` (`invoice_number`),
  KEY `gymies_invoices_user` (`user_id`),
  KEY `gymies_invoices_booking` (`booking_id`),
  CONSTRAINT `gymies_invoices_booking_fk` FOREIGN KEY (`booking_id`) REFERENCES `gymies_bookings` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_invoices_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_invoices`
--

LOCK TABLES `gymies_invoices` WRITE;
/*!40000 ALTER TABLE `gymies_invoices` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_invoices` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_legal_documents`
--

DROP TABLE IF EXISTS `gymies_legal_documents`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_legal_documents` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `doc_type` enum('terms','privacy','cookie') COLLATE utf8mb4_unicode_ci NOT NULL,
  `version` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL,
  `content_url` varchar(512) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `published_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_legal_documents_unique` (`doc_type`,`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_legal_documents`
--

LOCK TABLES `gymies_legal_documents` WRITE;
/*!40000 ALTER TABLE `gymies_legal_documents` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_legal_documents` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_loyalty_points_ledger`
--

DROP TABLE IF EXISTS `gymies_loyalty_points_ledger`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_loyalty_points_ledger` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `source_type` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'booking, referral, admin_adjustment',
  `source_id` bigint unsigned DEFAULT NULL,
  `points_delta` int NOT NULL COMMENT 'Kan + of - zijn',
  `notes` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_loyalty_points_user` (`user_id`),
  CONSTRAINT `gymies_loyalty_points_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_loyalty_points_ledger`
--

LOCK TABLES `gymies_loyalty_points_ledger` WRITE;
/*!40000 ALTER TABLE `gymies_loyalty_points_ledger` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_loyalty_points_ledger` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_messages`
--

DROP TABLE IF EXISTS `gymies_messages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_messages` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `conversation_id` bigint unsigned NOT NULL,
  `from_user_id` bigint unsigned NOT NULL,
  `body` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `read_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_messages_conversation` (`conversation_id`),
  KEY `gymies_messages_from` (`from_user_id`),
  CONSTRAINT `gymies_messages_conversation_fk` FOREIGN KEY (`conversation_id`) REFERENCES `gymies_conversations` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_messages_user_fk` FOREIGN KEY (`from_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_messages`
--

LOCK TABLES `gymies_messages` WRITE;
/*!40000 ALTER TABLE `gymies_messages` DISABLE KEYS */;
INSERT INTO `gymies_messages` VALUES (1,2,39,'Hi Jamai, ik wil volgende week extra focus op core.',NULL,'2026-02-27 11:10:11'),(2,1,39,'Hi Jamai, ik wil volgende week extra focus op core.',NULL,'2026-02-27 11:10:11'),(3,2,27,'Top! Ik zet een aangepast schema voor je klaar.',NULL,'2026-02-27 12:10:11'),(4,1,27,'Top! Ik zet een aangepast schema voor je klaar.',NULL,'2026-02-27 12:10:11'),(8,4,27,'Hi',NULL,'2026-02-27 15:12:58'),(9,4,27,'Hoe gaat het',NULL,'2026-02-27 15:52:32'),(10,4,27,'Wil je een alternatief moment voorstellen? Dan kijk ik direct met je mee.',NULL,'2026-02-27 21:19:34');
/*!40000 ALTER TABLE `gymies_messages` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_notification_preferences`
--

DROP TABLE IF EXISTS `gymies_notification_preferences`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_notification_preferences` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `channel` enum('email','push','sms') COLLATE utf8mb4_unicode_ci NOT NULL,
  `type` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'reminder, booking_confirmed, marketing, etc.',
  `enabled` tinyint(1) NOT NULL DEFAULT '1',
  `priority_mode` enum('all','important_only') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'all',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_notification_preferences_unique` (`user_id`,`channel`,`type`),
  CONSTRAINT `gymies_notification_preferences_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_notification_preferences`
--

LOCK TABLES `gymies_notification_preferences` WRITE;
/*!40000 ALTER TABLE `gymies_notification_preferences` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_notification_preferences` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_notification_queue`
--

DROP TABLE IF EXISTS `gymies_notification_queue`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_notification_queue` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `channel` enum('email','push','sms','in_app') COLLATE utf8mb4_unicode_ci NOT NULL,
  `event_type` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'booking_created, booking_cancelled, review_received, etc.',
  `payload_json` json DEFAULT NULL,
  `scheduled_for` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `sent_at` timestamp NULL DEFAULT NULL,
  `failed_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_notification_queue_user` (`user_id`),
  KEY `gymies_notification_queue_scheduled` (`scheduled_for`),
  CONSTRAINT `gymies_notification_queue_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_notification_queue`
--

LOCK TABLES `gymies_notification_queue` WRITE;
/*!40000 ALTER TABLE `gymies_notification_queue` DISABLE KEYS */;
INSERT INTO `gymies_notification_queue` VALUES (1,3,'in_app','booking_created_for_trainer','{\"booking_id\": \"1\", \"scheduled_at\": \"2026-02-28T10:00:00.000\", \"client_user_id\": \"2\", \"duration_minutes\": 60}','2026-02-27 03:18:23',NULL,NULL,'2026-02-27 03:18:23'),(2,2,'in_app','booking_pending_for_client','{\"booking_id\": \"1\", \"scheduled_at\": \"2026-02-28T10:00:00.000\", \"trainer_user_id\": \"3\", \"duration_minutes\": 60}','2026-02-27 03:18:23',NULL,NULL,'2026-02-27 03:18:23'),(3,6,'in_app','booking_created_for_trainer','{\"booking_id\": \"2\", \"scheduled_at\": \"2026-02-28T08:00:00.000\", \"client_user_id\": \"2\", \"duration_minutes\": 60}','2026-02-27 03:55:38',NULL,NULL,'2026-02-27 03:55:38'),(4,2,'in_app','booking_pending_for_client','{\"booking_id\": \"2\", \"scheduled_at\": \"2026-02-28T08:00:00.000\", \"trainer_user_id\": \"6\", \"duration_minutes\": 60}','2026-02-27 03:55:38',NULL,NULL,'2026-02-27 03:55:38'),(5,39,'in_app','booking_confirmed_for_client','{\"booking_id\": \"18\", \"event_type\": \"booking_confirmed\"}','2026-02-27 14:11:08',NULL,NULL,'2026-02-27 14:11:08'),(6,27,'in_app','booking_confirmed_for_trainer','{\"booking_id\": \"18\", \"event_type\": \"booking_confirmed\"}','2026-02-27 14:11:08',NULL,NULL,'2026-02-27 14:11:08'),(7,11,'in_app','booking_created_for_trainer','{\"booking_id\": \"25\", \"scheduled_at\": \"2026-02-28T10:00:00.000\", \"client_user_id\": \"2\", \"duration_minutes\": 60}','2026-02-27 19:06:44',NULL,NULL,'2026-02-27 19:06:44'),(8,2,'in_app','booking_pending_for_client','{\"booking_id\": \"25\", \"scheduled_at\": \"2026-02-28T10:00:00.000\", \"trainer_user_id\": \"11\", \"duration_minutes\": 60}','2026-02-27 19:06:44',NULL,NULL,'2026-02-27 19:06:44'),(9,3,'in_app','booking_created_for_trainer','{\"booking_id\": \"26\", \"scheduled_at\": \"2026-02-28T08:45:00.000\", \"client_user_id\": \"2\", \"duration_minutes\": 60}','2026-02-27 19:56:25',NULL,NULL,'2026-02-27 19:56:25'),(10,2,'in_app','booking_pending_for_client','{\"booking_id\": \"26\", \"scheduled_at\": \"2026-02-28T08:45:00.000\", \"trainer_user_id\": \"3\", \"duration_minutes\": 60}','2026-02-27 19:56:25',NULL,NULL,'2026-02-27 19:56:25');
/*!40000 ALTER TABLE `gymies_notification_queue` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_notification_user_settings`
--

DROP TABLE IF EXISTS `gymies_notification_user_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_notification_user_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `quiet_hours_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `quiet_hours_start` varchar(5) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '22:00',
  `quiet_hours_end` varchar(5) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '07:00',
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_notification_user_settings_user_unique` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_notification_user_settings`
--

LOCK TABLES `gymies_notification_user_settings` WRITE;
/*!40000 ALTER TABLE `gymies_notification_user_settings` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_notification_user_settings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_organisation_alert_states`
--

DROP TABLE IF EXISTS `gymies_organisation_alert_states`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_organisation_alert_states` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organisation_id` bigint unsigned NOT NULL,
  `alert_key` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` varchar(16) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'open',
  `handled_by` bigint unsigned DEFAULT NULL,
  `handled_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_org_alert_unique` (`organisation_id`,`alert_key`),
  KEY `gymies_org_alert_status` (`organisation_id`,`status`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_organisation_alert_states`
--

LOCK TABLES `gymies_organisation_alert_states` WRITE;
/*!40000 ALTER TABLE `gymies_organisation_alert_states` DISABLE KEYS */;
INSERT INTO `gymies_organisation_alert_states` VALUES (1,2,'open_settlements','done',46,'2026-02-28 02:18:01','2026-02-28 02:18:01','2026-02-28 02:18:01'),(2,2,'no_show_followups','done',46,'2026-02-28 02:18:07','2026-02-28 02:18:07','2026-02-28 02:18:07'),(3,2,'trainers_without_availability','done',46,'2026-02-28 02:18:10','2026-02-28 02:18:10','2026-02-28 02:18:10'),(4,2,'expired_payment_method','done',46,'2026-02-28 02:18:11','2026-02-28 02:18:11','2026-02-28 02:18:11');
/*!40000 ALTER TABLE `gymies_organisation_alert_states` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_organisation_members`
--

DROP TABLE IF EXISTS `gymies_organisation_members`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_organisation_members` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organisation_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `role` enum('owner','manager','viewer') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'viewer',
  `status` enum('active','inactive') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'active',
  `invited_at` timestamp NULL DEFAULT NULL,
  `joined_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_organisation_members_unique` (`organisation_id`,`user_id`),
  KEY `gymies_organisation_members_user` (`user_id`),
  KEY `gymies_organisation_members_role` (`role`),
  CONSTRAINT `gymies_organisation_members_org_fk` FOREIGN KEY (`organisation_id`) REFERENCES `gymies_organisations` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_organisation_members_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_organisation_members`
--

LOCK TABLES `gymies_organisation_members` WRITE;
/*!40000 ALTER TABLE `gymies_organisation_members` DISABLE KEYS */;
INSERT INTO `gymies_organisation_members` VALUES (1,1,45,'owner','active','2026-02-28 00:21:43','2026-02-28 00:21:43','2026-02-28 00:21:43','2026-02-28 00:21:43'),(2,2,46,'owner','active','2026-02-28 00:36:57','2026-02-28 00:36:57','2026-02-28 00:36:57','2026-02-28 00:36:57'),(3,2,50,'manager','active','2026-02-28 00:55:45','2026-02-28 00:55:45','2026-02-28 00:55:45','2026-02-28 00:55:45'),(4,2,51,'viewer','active','2026-02-28 00:55:45','2026-02-28 00:55:45','2026-02-28 00:55:45','2026-02-28 00:55:45');
/*!40000 ALTER TABLE `gymies_organisation_members` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_organisation_settlement_lines`
--

DROP TABLE IF EXISTS `gymies_organisation_settlement_lines`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_organisation_settlement_lines` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `settlement_id` bigint unsigned NOT NULL,
  `booking_id` bigint unsigned DEFAULT NULL,
  `trainer_user_id` bigint unsigned DEFAULT NULL,
  `line_type` enum('booking','refund','chargeback','manual_adjustment') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'booking',
  `gross_cents` int NOT NULL DEFAULT '0',
  `platform_fee_cents` int NOT NULL DEFAULT '0',
  `adjustment_cents` int NOT NULL DEFAULT '0',
  `net_cents` int NOT NULL DEFAULT '0',
  `metadata_json` json DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_organisation_settlement_lines_settlement` (`settlement_id`),
  KEY `gymies_organisation_settlement_lines_booking` (`booking_id`),
  KEY `gymies_organisation_settlement_lines_trainer_fk` (`trainer_user_id`),
  CONSTRAINT `gymies_organisation_settlement_lines_booking_fk` FOREIGN KEY (`booking_id`) REFERENCES `gymies_bookings` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_organisation_settlement_lines_settlement_fk` FOREIGN KEY (`settlement_id`) REFERENCES `gymies_organisation_settlements` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_organisation_settlement_lines_trainer_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_organisation_settlement_lines`
--

LOCK TABLES `gymies_organisation_settlement_lines` WRITE;
/*!40000 ALTER TABLE `gymies_organisation_settlement_lines` DISABLE KEYS */;
INSERT INTO `gymies_organisation_settlement_lines` VALUES (1,1,27,47,'booking',6500,780,0,5720,'{\"source\": \"seed_powerhouse\"}','2026-02-28 00:55:45'),(2,1,28,48,'booking',7000,840,0,6160,'{\"source\": \"seed_powerhouse\"}','2026-02-28 00:55:45');
/*!40000 ALTER TABLE `gymies_organisation_settlement_lines` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_organisation_settlements`
--

DROP TABLE IF EXISTS `gymies_organisation_settlements`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_organisation_settlements` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organisation_id` bigint unsigned NOT NULL,
  `period_start` date NOT NULL,
  `period_end` date NOT NULL,
  `gross_cents` int unsigned NOT NULL DEFAULT '0',
  `fee_cents` int unsigned NOT NULL DEFAULT '0',
  `adjustments_cents` int NOT NULL DEFAULT '0',
  `net_cents` int NOT NULL DEFAULT '0',
  `status` enum('draft','approved','paid','reconciled') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'draft',
  `approved_at` timestamp NULL DEFAULT NULL,
  `paid_at` timestamp NULL DEFAULT NULL,
  `reconciled_at` timestamp NULL DEFAULT NULL,
  `created_by_user_id` bigint unsigned DEFAULT NULL,
  `payout_reference` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_organisation_settlements_period` (`organisation_id`,`period_start`,`period_end`),
  KEY `gymies_organisation_settlements_status` (`status`),
  KEY `gymies_organisation_settlements_creator_fk` (`created_by_user_id`),
  CONSTRAINT `gymies_organisation_settlements_creator_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_organisation_settlements_org_fk` FOREIGN KEY (`organisation_id`) REFERENCES `gymies_organisations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_organisation_settlements`
--

LOCK TABLES `gymies_organisation_settlements` WRITE;
/*!40000 ALTER TABLE `gymies_organisation_settlements` DISABLE KEYS */;
INSERT INTO `gymies_organisation_settlements` VALUES (1,2,'2026-02-01','2026-02-28',13500,1620,0,11880,'draft',NULL,NULL,NULL,46,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(2,2,'2026-01-01','2026-01-31',38000,4560,0,33440,'approved','2026-02-28 00:57:19',NULL,NULL,46,NULL,'2026-02-28 00:57:19','2026-02-28 00:57:19'),(3,2,'2025-12-01','2025-12-31',41200,4944,1200,37456,'paid','2026-02-28 00:57:19','2026-02-28 00:57:19',NULL,46,'SEED-PAID','2026-02-28 00:57:19','2026-02-28 00:57:19'),(4,2,'2025-11-01','2025-11-30',36500,4380,-500,31620,'reconciled','2026-02-28 00:57:19','2026-02-28 00:57:19','2026-02-28 00:57:19',46,'SEED-RECONCILED','2026-02-28 00:57:19','2026-02-28 00:57:19');
/*!40000 ALTER TABLE `gymies_organisation_settlements` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_organisation_trainers`
--

DROP TABLE IF EXISTS `gymies_organisation_trainers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_organisation_trainers` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organisation_id` bigint unsigned NOT NULL,
  `trainer_user_id` bigint unsigned NOT NULL,
  `employment_type` enum('employee','contractor') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'employee',
  `payout_route` enum('direct_trainer','via_organisation') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'via_organisation',
  `is_primary` tinyint(1) NOT NULL DEFAULT '0',
  `status` enum('active','inactive') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'active',
  `active_from` date DEFAULT NULL,
  `active_until` date DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_organisation_trainers_unique` (`organisation_id`,`trainer_user_id`),
  KEY `gymies_organisation_trainers_trainer` (`trainer_user_id`),
  KEY `gymies_organisation_trainers_org` (`organisation_id`),
  KEY `gymies_organisation_trainers_primary` (`is_primary`),
  CONSTRAINT `gymies_organisation_trainers_org_fk` FOREIGN KEY (`organisation_id`) REFERENCES `gymies_organisations` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_organisation_trainers_trainer_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_organisation_trainers`
--

LOCK TABLES `gymies_organisation_trainers` WRITE;
/*!40000 ALTER TABLE `gymies_organisation_trainers` DISABLE KEYS */;
INSERT INTO `gymies_organisation_trainers` VALUES (1,2,47,'employee','via_organisation',1,'active','2026-02-28',NULL,'2026-02-28 00:55:45','2026-02-28 01:16:28'),(2,2,48,'employee','via_organisation',0,'active','2026-02-28',NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(3,2,49,'employee','via_organisation',0,'active','2026-02-28',NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(4,2,56,'employee','via_organisation',0,'inactive','2026-02-28','2026-02-28','2026-02-28 00:57:19','2026-02-28 00:57:19');
/*!40000 ALTER TABLE `gymies_organisation_trainers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_organisations`
--

DROP TABLE IF EXISTS `gymies_organisations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_organisations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `type` enum('gym','company') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'gym',
  `status` enum('active','inactive','suspended') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'active',
  `contact_email` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `invoice_prefix` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `payout_frequency` enum('weekly','biweekly','monthly') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'weekly',
  `payout_iban_masked` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `payout_minimum_cents` int unsigned NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_organisations_type` (`type`),
  KEY `gymies_organisations_status` (`status`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_organisations`
--

LOCK TABLES `gymies_organisations` WRITE;
/*!40000 ALTER TABLE `gymies_organisations` DISABLE KEYS */;
INSERT INTO `gymies_organisations` VALUES (1,'elotmanigym','gym','active','elotmanigym@trainmate.app',NULL,'weekly',NULL,0,'2026-02-28 00:21:43','2026-02-28 00:21:43'),(2,'Powerhousegym','gym','active','powerhousegym@trainmate.app',NULL,'weekly',NULL,0,'2026-02-28 00:36:57','2026-02-28 00:54:48');
/*!40000 ALTER TABLE `gymies_organisations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_packages`
--

DROP TABLE IF EXISTS `gymies_packages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_packages` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_user_id` bigint unsigned NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Bijv. 10 sessies',
  `sessions_count` int unsigned NOT NULL,
  `total_cents` int unsigned NOT NULL,
  `valid_days` int unsigned DEFAULT NULL COMMENT 'Geldig tot X dagen na aankoop',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_packages_trainer` (`trainer_user_id`),
  CONSTRAINT `gymies_packages_user_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_packages`
--

LOCK TABLES `gymies_packages` WRITE;
/*!40000 ALTER TABLE `gymies_packages` DISABLE KEYS */;
INSERT INTO `gymies_packages` VALUES (1,27,'PACAKGE XS',10,29900,56,'2026-02-27 16:31:33','2026-02-27 16:31:33');
/*!40000 ALTER TABLE `gymies_packages` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_password_reset_tokens`
--

DROP TABLE IF EXISTS `gymies_password_reset_tokens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_password_reset_tokens` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `token` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `expires_at` timestamp NOT NULL,
  `used_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_password_reset_user` (`user_id`),
  KEY `gymies_password_reset_token` (`token`),
  KEY `gymies_password_reset_expires` (`expires_at`),
  CONSTRAINT `gymies_password_reset_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_password_reset_tokens`
--

LOCK TABLES `gymies_password_reset_tokens` WRITE;
/*!40000 ALTER TABLE `gymies_password_reset_tokens` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_password_reset_tokens` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_payment_transactions`
--

DROP TABLE IF EXISTS `gymies_payment_transactions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_payment_transactions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `booking_id` bigint unsigned DEFAULT NULL,
  `user_id` bigint unsigned DEFAULT NULL,
  `counterparty_user_id` bigint unsigned DEFAULT NULL,
  `provider` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'unknown',
  `provider_transaction_id` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `amount_cents` int NOT NULL DEFAULT '0',
  `status` varchar(40) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `payment_method` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `paid_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_payment_transactions_booking_idx` (`booking_id`),
  KEY `gymies_payment_transactions_status_idx` (`status`),
  KEY `gymies_payment_transactions_created_idx` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_payment_transactions`
--

LOCK TABLES `gymies_payment_transactions` WRITE;
/*!40000 ALTER TABLE `gymies_payment_transactions` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_payment_transactions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_payouts`
--

DROP TABLE IF EXISTS `gymies_payouts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_payouts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_user_id` bigint unsigned NOT NULL,
  `amount_cents` int unsigned NOT NULL,
  `status` enum('pending','paid','failed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `paid_at` timestamp NULL DEFAULT NULL,
  `reference` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Bank/Stripe reference',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_payouts_trainer` (`trainer_user_id`),
  KEY `gymies_payouts_status` (`status`),
  CONSTRAINT `gymies_payouts_user_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_payouts`
--

LOCK TABLES `gymies_payouts` WRITE;
/*!40000 ALTER TABLE `gymies_payouts` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_payouts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_plans`
--

DROP TABLE IF EXISTS `gymies_plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_plans` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `price_cents_per_month` int unsigned NOT NULL,
  `sessions_included` int unsigned DEFAULT NULL COMMENT 'Aantal sessies per maand',
  `discount_percent_on_extra` decimal(5,2) DEFAULT NULL COMMENT 'Korting op extra sessies',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_plans`
--

LOCK TABLES `gymies_plans` WRITE;
/*!40000 ALTER TABLE `gymies_plans` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_plans` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_promo_codes`
--

DROP TABLE IF EXISTS `gymies_promo_codes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_promo_codes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Unieke code, bijv. INTRO20',
  `discount_type` enum('percent','fixed') COLLATE utf8mb4_unicode_ci NOT NULL,
  `value_cents` int unsigned NOT NULL COMMENT 'Percentage (1-100) of bedrag in centen',
  `valid_from` date DEFAULT NULL,
  `valid_until` date DEFAULT NULL,
  `max_uses` int unsigned DEFAULT NULL COMMENT 'Maximaal aantal keer inwisselen',
  `use_count` int unsigned NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_promo_codes_code_unique` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_promo_codes`
--

LOCK TABLES `gymies_promo_codes` WRITE;
/*!40000 ALTER TABLE `gymies_promo_codes` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_promo_codes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_rate_limit_events`
--

DROP TABLE IF EXISTS `gymies_rate_limit_events`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_rate_limit_events` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `ip_address` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_id` bigint unsigned DEFAULT NULL,
  `endpoint` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `blocked_until` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_rate_limit_events_user` (`user_id`),
  CONSTRAINT `gymies_rate_limit_events_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=536 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_rate_limit_events`
--

LOCK TABLES `gymies_rate_limit_events` WRITE;
/*!40000 ALTER TABLE `gymies_rate_limit_events` DISABLE KEYS */;
INSERT INTO `gymies_rate_limit_events` VALUES (1,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-27 21:16:54'),(2,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-27 21:16:54'),(3,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-27 21:17:08'),(4,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-27 21:17:09'),(5,'89.205.255.117',2,'api/gymies/notifications',NULL,'2026-02-27 21:17:11'),(6,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-27 21:17:14'),(7,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-27 21:17:15'),(8,'89.205.255.117',2,'api/gymies/auth/sessions',NULL,'2026-02-27 21:17:30'),(9,'89.205.255.117',2,'api/gymies/auth/logout-device',NULL,'2026-02-27 21:17:30'),(10,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-27 21:17:37'),(11,'89.205.255.117',27,'api/gymies/trainer/summary',NULL,'2026-02-27 21:17:37'),(12,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:17:37'),(13,'89.205.255.117',27,'api/gymies/bookings',NULL,'2026-02-27 21:17:38'),(14,'89.205.255.117',27,'api/gymies/trainer/revenue',NULL,'2026-02-27 21:17:38'),(15,'89.205.255.117',27,'api/gymies/trainer/availability',NULL,'2026-02-27 21:17:38'),(16,'89.205.255.117',27,'api/gymies/trainer/conversations',NULL,'2026-02-27 21:17:38'),(17,'89.205.255.117',27,'api/gymies/ops/run-backup',NULL,'2026-02-27 21:17:43'),(18,'89.205.255.117',27,'api/gymies/ops/run-backup',NULL,'2026-02-27 21:17:46'),(19,'89.205.255.117',27,'api/gymies/trainer/report-issue',NULL,'2026-02-27 21:17:49'),(20,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:18:07'),(21,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:18:37'),(22,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:19:07'),(23,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:19:26'),(24,'89.205.255.117',27,'api/gymies/trainer/conversations',NULL,'2026-02-27 21:19:26'),(25,'89.205.255.117',27,'api/gymies/trainer/conversations/4/messages',NULL,'2026-02-27 21:19:26'),(26,'89.205.255.117',27,'api/gymies/trainer/conversations/4/messages',NULL,'2026-02-27 21:19:34'),(27,'89.205.255.117',27,'api/gymies/trainer/conversations/4/messages',NULL,'2026-02-27 21:19:34'),(28,'89.205.255.117',27,'api/gymies/trainer/conversations',NULL,'2026-02-27 21:19:34'),(29,'89.205.255.117',27,'api/gymies/trainer/conversations/4/messages',NULL,'2026-02-27 21:19:34'),(30,'89.205.255.117',27,'api/gymies/trainer/conversations/1/messages',NULL,'2026-02-27 21:19:35'),(31,'89.205.255.117',27,'api/gymies/trainer/conversations/1/messages',NULL,'2026-02-27 21:19:36'),(32,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:19:37'),(33,'89.205.255.117',27,'api/gymies/bookings',NULL,'2026-02-27 21:19:37'),(34,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:19:38'),(35,'89.205.255.117',27,'api/gymies/trainer/summary',NULL,'2026-02-27 21:19:38'),(36,'89.205.255.117',27,'api/gymies/bookings',NULL,'2026-02-27 21:19:38'),(37,'89.205.255.117',27,'api/gymies/trainer/revenue',NULL,'2026-02-27 21:19:38'),(38,'89.205.255.117',27,'api/gymies/trainer/availability',NULL,'2026-02-27 21:19:38'),(39,'89.205.255.117',27,'api/gymies/trainer/conversations',NULL,'2026-02-27 21:19:38'),(40,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:20:07'),(41,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:20:37'),(42,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:21:07'),(43,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:21:37'),(44,'89.205.255.117',27,'api/gymies/bookings',NULL,'2026-02-27 21:21:44'),(45,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:21:50'),(46,'89.205.255.117',27,'api/gymies/trainer/me',NULL,'2026-02-27 21:21:50'),(47,'89.205.255.117',27,'api/gymies/trainer/media',NULL,'2026-02-27 21:21:50'),(48,'89.205.255.117',27,'api/gymies/trainer/packages',NULL,'2026-02-27 21:21:50'),(49,'89.205.255.117',27,'api/gymies/bookings',NULL,'2026-02-27 21:21:55'),(50,'89.205.255.117',27,'api/gymies/trainer/live-counters',NULL,'2026-02-27 21:22:07'),(51,'89.205.255.117',27,'api/gymies/auth/sessions',NULL,'2026-02-27 21:22:13'),(52,'89.205.255.117',27,'api/gymies/auth/logout-device',NULL,'2026-02-27 21:22:13'),(53,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-27 21:26:05'),(54,'89.205.255.117',2,'api/gymies/auth/sessions',NULL,'2026-02-27 21:33:42'),(55,'89.205.255.117',2,'api/gymies/auth/logout-device',NULL,'2026-02-27 21:33:42'),(56,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-27 22:34:57'),(57,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-27 22:34:58'),(58,'89.205.255.117',2,'api/gymies/auth/sessions',NULL,'2026-02-27 22:35:00'),(59,'89.205.255.117',2,'api/gymies/auth/logout-device',NULL,'2026-02-27 22:35:00'),(60,'178.231.104.108',44,'api/gymies/trainer/live-counters',NULL,'2026-02-27 22:38:08'),(61,'178.231.104.108',44,'api/gymies/trainer/summary',NULL,'2026-02-27 22:38:08'),(62,'178.231.104.108',44,'api/gymies/bookings',NULL,'2026-02-27 22:38:08'),(63,'178.231.104.108',44,'api/gymies/trainer/revenue',NULL,'2026-02-27 22:38:08'),(64,'178.231.104.108',44,'api/gymies/trainer/availability',NULL,'2026-02-27 22:38:08'),(65,'178.231.104.108',44,'api/gymies/trainer/conversations',NULL,'2026-02-27 22:38:08'),(66,'178.231.104.108',44,'api/gymies/trainer/live-counters',NULL,'2026-02-27 22:38:13'),(67,'178.231.104.108',44,'api/gymies/bookings',NULL,'2026-02-27 22:38:13'),(68,'178.231.104.108',44,'api/gymies/trainer/live-counters',NULL,'2026-02-27 22:38:15'),(69,'178.231.104.108',44,'api/gymies/bookings',NULL,'2026-02-27 22:38:15'),(70,'178.231.104.108',44,'api/gymies/trainer/live-counters',NULL,'2026-02-27 22:38:16'),(71,'178.231.104.108',44,'api/gymies/trainer/conversations',NULL,'2026-02-27 22:38:16'),(72,'178.231.104.108',44,'api/gymies/trainer/live-counters',NULL,'2026-02-27 22:38:17'),(73,'178.231.104.108',44,'api/gymies/trainer/media',NULL,'2026-02-27 22:38:17'),(74,'178.231.104.108',44,'api/gymies/trainer/packages',NULL,'2026-02-27 22:38:17'),(75,'178.231.104.108',44,'api/gymies/trainer/me',NULL,'2026-02-27 22:38:17'),(76,'178.231.104.108',44,'api/gymies/trainer/live-counters',NULL,'2026-02-27 22:38:38'),(77,'178.231.104.108',44,'api/gymies/trainer/live-counters',NULL,'2026-02-27 22:38:40'),(78,'178.231.104.108',44,'api/gymies/trainer/conversations',NULL,'2026-02-27 22:38:40'),(79,'178.231.104.108',44,'api/gymies/trainer/live-counters',NULL,'2026-02-27 22:38:40'),(80,'178.231.104.108',44,'api/gymies/bookings',NULL,'2026-02-27 22:38:41'),(81,'178.231.104.108',44,'api/gymies/trainer/live-counters',NULL,'2026-02-27 22:38:41'),(82,'178.231.104.108',44,'api/gymies/bookings',NULL,'2026-02-27 22:38:41'),(83,'178.231.104.108',44,'api/gymies/trainer/live-counters',NULL,'2026-02-27 22:38:42'),(84,'178.231.104.108',44,'api/gymies/trainer/summary',NULL,'2026-02-27 22:38:42'),(85,'178.231.104.108',44,'api/gymies/bookings',NULL,'2026-02-27 22:38:42'),(86,'178.231.104.108',44,'api/gymies/trainer/revenue',NULL,'2026-02-27 22:38:42'),(87,'178.231.104.108',44,'api/gymies/trainer/availability',NULL,'2026-02-27 22:38:42'),(88,'178.231.104.108',44,'api/gymies/trainer/conversations',NULL,'2026-02-27 22:38:42'),(89,'178.231.104.108',44,'api/gymies/trainer/live-counters',NULL,'2026-02-27 22:38:47'),(90,'178.231.104.108',44,'api/gymies/trainer/me',NULL,'2026-02-27 22:38:47'),(91,'178.231.104.108',44,'api/gymies/trainer/packages',NULL,'2026-02-27 22:38:47'),(92,'178.231.104.108',44,'api/gymies/trainer/media',NULL,'2026-02-27 22:38:47'),(93,'178.231.104.108',44,'api/gymies/auth/sessions',NULL,'2026-02-27 22:38:49'),(94,'178.231.104.108',44,'api/gymies/auth/logout-device',NULL,'2026-02-27 22:38:49'),(95,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-27 23:34:10'),(96,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-27 23:34:10'),(97,'89.205.255.117',2,'api/gymies/notifications',NULL,'2026-02-27 23:34:24'),(98,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-27 23:34:25'),(99,'89.205.255.117',2,'api/gymies/notifications',NULL,'2026-02-27 23:34:34'),(100,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-27 23:34:34'),(101,'89.205.255.117',2,'api/gymies/notifications',NULL,'2026-02-27 23:34:35'),(102,'89.205.255.117',2,'api/gymies/notifications',NULL,'2026-02-27 23:34:36'),(103,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-27 23:34:37'),(104,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:22:08'),(105,'89.205.255.117',45,'api/gymies/bookings',NULL,'2026-02-28 00:22:09'),(106,'89.205.255.117',45,'api/gymies/bookings',NULL,'2026-02-28 00:22:36'),(107,'89.205.255.117',45,'api/gymies/auth/sessions',NULL,'2026-02-28 00:27:31'),(108,'89.205.255.117',45,'api/gymies/auth/logout-device',NULL,'2026-02-28 00:27:31'),(109,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:28:02'),(110,'89.205.255.117',45,'api/gymies/bookings',NULL,'2026-02-28 00:28:03'),(111,'89.205.255.117',45,'api/gymies/auth/sessions',NULL,'2026-02-28 00:33:42'),(112,'89.205.255.117',45,'api/gymies/auth/logout-device',NULL,'2026-02-28 00:33:42'),(113,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:37:36'),(114,'89.205.255.117',46,'api/gymies/bookings',NULL,'2026-02-28 00:37:37'),(115,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:38:25'),(116,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 00:38:28'),(117,'89.205.255.117',46,'api/gymies/auth/sessions',NULL,'2026-02-28 00:40:25'),(118,'89.205.255.117',46,'api/gymies/auth/logout-device',NULL,'2026-02-28 00:40:25'),(119,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:40:43'),(120,'89.205.255.117',46,'api/gymies/bookings',NULL,'2026-02-28 00:40:43'),(121,'89.205.255.117',46,'api/gymies/auth/sessions',NULL,'2026-02-28 00:42:34'),(122,'89.205.255.117',46,'api/gymies/auth/logout-device',NULL,'2026-02-28 00:42:34'),(123,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:42:52'),(124,'89.205.255.117',46,'api/gymies/bookings',NULL,'2026-02-28 00:42:52'),(125,'89.205.255.117',46,'api/gymies/auth/sessions',NULL,'2026-02-28 00:45:53'),(126,'89.205.255.117',46,'api/gymies/auth/logout-device',NULL,'2026-02-28 00:45:53'),(127,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:46:02'),(128,'89.205.255.117',46,'api/gymies/bookings',NULL,'2026-02-28 00:46:03'),(129,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:50:16'),(130,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 00:50:16'),(131,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 00:50:16'),(132,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 00:50:16'),(133,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:52:04'),(134,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 00:52:09'),(135,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:53:18'),(136,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 00:53:18'),(137,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 00:53:18'),(138,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 00:53:18'),(139,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 00:53:30'),(140,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 00:53:32'),(141,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 00:53:32'),(142,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 00:54:22'),(143,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 00:54:44'),(144,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 00:54:48'),(145,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 00:54:48'),(146,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 00:54:50'),(147,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:55:55'),(148,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 00:55:55'),(149,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 00:55:56'),(150,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 00:55:56'),(151,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 00:55:56'),(152,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:57:27'),(153,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 00:57:28'),(154,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 00:57:28'),(155,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 00:57:28'),(156,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 00:58:58'),(157,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 00:58:59'),(158,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 00:58:59'),(159,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 00:58:59'),(160,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:00:06'),(161,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:00:16'),(162,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:00:20'),(163,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:00:21'),(164,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 01:00:24'),(165,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:00:27'),(166,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:01:04'),(167,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:01:06'),(168,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:01:15'),(169,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:01:16'),(170,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 01:02:58'),(171,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:03:08'),(172,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:04:04'),(173,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:04:13'),(174,'89.205.255.117',46,'api/gymies/me',NULL,'2026-02-28 01:08:22'),(175,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:08:22'),(176,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:08:23'),(177,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:08:23'),(178,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:08:26'),(179,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:08:28'),(180,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:08:30'),(181,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 01:08:31'),(182,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:08:31'),(183,'89.205.255.117',46,'api/gymies/auth/sessions',NULL,'2026-02-28 01:09:06'),(184,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:09:06'),(185,'89.205.255.117',46,'api/gymies/auth/logout-device',NULL,'2026-02-28 01:09:06'),(186,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:09:19'),(187,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:09:19'),(188,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:09:20'),(189,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:09:20'),(190,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:09:21'),(191,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:09:22'),(192,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 01:09:23'),(193,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:09:24'),(194,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:09:24'),(195,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:09:24'),(196,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:09:25'),(197,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:09:31'),(198,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:09:32'),(199,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:09:33'),(200,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:15:31'),(201,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:16:18'),(202,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:16:19'),(203,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:16:27'),(204,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:16:27'),(205,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:16:27'),(206,'89.205.255.117',46,'api/gymies/gym/trainers/47/status',NULL,'2026-02-28 01:16:28'),(207,'89.205.255.117',46,'api/gymies/gym/trainers/47/status',NULL,'2026-02-28 01:16:28'),(208,'89.205.255.117',46,'api/gymies/me',NULL,'2026-02-28 01:16:57'),(209,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:16:57'),(210,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:16:57'),(211,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:16:57'),(212,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:16:59'),(213,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:17:02'),(214,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:18:38'),(215,'89.205.255.117',46,'api/gymies/me',NULL,'2026-02-28 01:18:40'),(216,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:18:40'),(217,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:18:40'),(218,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:18:40'),(219,'89.205.255.117',46,'api/gymies/me',NULL,'2026-02-28 01:18:41'),(220,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:18:51'),(221,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:18:51'),(222,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:18:52'),(223,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:18:52'),(224,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:18:55'),(225,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:18:55'),(226,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:18:57'),(227,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:19:00'),(228,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:19:00'),(229,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:19:03'),(230,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:21:12'),(231,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:21:12'),(232,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:21:12'),(233,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:21:12'),(234,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:21:41'),(235,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:21:42'),(236,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:21:43'),(237,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:21:44'),(238,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:21:46'),(239,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:21:49'),(240,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:21:49'),(241,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 01:21:50'),(242,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:21:51'),(243,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:25:21'),(244,'89.205.255.117',46,'api/gymies/bookings',NULL,'2026-02-28 01:25:22'),(245,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:26:29'),(246,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:26:36'),(247,'89.205.255.117',46,'api/gymies/auth/sessions',NULL,'2026-02-28 01:30:19'),(248,'89.205.255.117',46,'api/gymies/auth/logout-device',NULL,'2026-02-28 01:30:19'),(249,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:30:32'),(250,'89.205.255.117',46,'api/gymies/bookings',NULL,'2026-02-28 01:30:32'),(251,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:33:21'),(252,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:33:48'),(253,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:34:14'),(254,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:34:14'),(255,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:34:14'),(256,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:34:14'),(257,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:34:14'),(258,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:34:18'),(259,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:34:20'),(260,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:34:23'),(261,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:34:33'),(262,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:34:34'),(263,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:34:34'),(264,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:35:14'),(265,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 01:35:15'),(266,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:35:19'),(267,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:35:22'),(268,'89.205.255.117',46,'api/gymies/me',NULL,'2026-02-28 01:35:45'),(269,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:35:45'),(270,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:35:45'),(271,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:35:45'),(272,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:35:48'),(273,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:35:48'),(274,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:36:36'),(275,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:36:37'),(276,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:36:37'),(277,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 01:36:38'),(278,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:36:39'),(279,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:55:15'),(280,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:55:19'),(281,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:55:24'),(282,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:55:25'),(283,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:55:25'),(284,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:57:25'),(285,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:57:26'),(286,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:57:26'),(287,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 01:57:26'),(288,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:57:26'),(289,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:57:26'),(290,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 01:57:27'),(291,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:57:27'),(292,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 01:57:27'),(293,'89.205.255.117',46,'api/gymies/gym/clients',NULL,'2026-02-28 01:57:27'),(294,'89.205.255.117',46,'api/gymies/gym/bookings/export',NULL,'2026-02-28 01:57:28'),(295,'89.205.255.117',46,'api/gymies/gym/revenue/export',NULL,'2026-02-28 01:57:28'),(296,'89.205.255.117',46,'api/gymies/gym/trainers/export',NULL,'2026-02-28 01:57:28'),(297,'89.205.255.117',46,'api/gymies/gym/bookings/30',NULL,'2026-02-28 01:57:28'),(298,'89.205.255.117',46,'api/gymies/gym/settlements/1',NULL,'2026-02-28 01:57:29'),(299,'89.205.255.117',46,'api/gymies/gym/trainers/47/stats',NULL,'2026-02-28 01:57:29'),(300,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 01:57:29'),(301,'89.205.255.117',46,'api/gymies/gym/clients',NULL,'2026-02-28 01:57:29'),(302,'89.205.255.117',46,'api/gymies/me',NULL,'2026-02-28 01:58:30'),(303,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:58:30'),(304,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:58:31'),(305,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:58:31'),(306,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:58:37'),(307,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 01:58:38'),(308,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 01:58:39'),(309,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 01:58:39'),(310,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 01:58:40'),(311,'89.205.255.117',46,'api/gymies/auth/sessions',NULL,'2026-02-28 01:58:43'),(312,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:58:43'),(313,'89.205.255.117',46,'api/gymies/auth/logout-device',NULL,'2026-02-28 01:58:43'),(314,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 01:59:57'),(315,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:59:57'),(316,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:59:57'),(317,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 01:59:57'),(318,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 01:59:57'),(319,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 02:00:02'),(320,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:00:03'),(321,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 02:00:04'),(322,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:00:04'),(323,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 02:00:06'),(324,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:00:18'),(325,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 02:03:45'),(326,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:03:46'),(327,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:03:46'),(328,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:03:46'),(329,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:03:46'),(330,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:03:46'),(331,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 02:03:51'),(332,'89.205.255.117',46,'api/gymies/gym/trainers/47/stats',NULL,'2026-02-28 02:03:53'),(333,'89.205.255.117',46,'api/gymies/gym/trainers/56/stats',NULL,'2026-02-28 02:04:00'),(334,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:04:03'),(335,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 02:04:03'),(336,'89.205.255.117',46,'api/gymies/gym/bookings/30',NULL,'2026-02-28 02:04:05'),(337,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:04:11'),(338,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 02:04:11'),(339,'89.205.255.117',46,'api/gymies/gym/clients',NULL,'2026-02-28 02:04:15'),(340,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 02:04:16'),(341,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 02:04:23'),(342,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:04:23'),(343,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 02:04:23'),(344,'89.205.255.117',46,'api/gymies/gym/settings',NULL,'2026-02-28 02:04:38'),(345,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 02:04:39'),(346,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:04:42'),(347,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:04:49'),(348,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:04:49'),(349,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:04:54'),(350,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:04:54'),(351,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 02:05:05'),(352,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:05:05'),(353,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 02:05:05'),(354,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:05:09'),(355,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:05:10'),(356,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 02:13:27'),(357,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:13:28'),(358,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:13:28'),(359,'89.205.255.117',46,'api/gymies/gym/bookings/30/send-reminder',NULL,'2026-02-28 02:13:28'),(360,'89.205.255.117',46,'api/gymies/gym/alerts/open_settlements/complete',NULL,'2026-02-28 02:13:29'),(361,'89.205.255.117',46,'api/gymies/gym/alerts/open_settlements/complete',NULL,'2026-02-28 02:13:29'),(362,'89.205.255.117',46,'api/gymies/gym/clients',NULL,'2026-02-28 02:13:29'),(363,'89.205.255.117',46,'api/gymies/gym/clients/55/reengagement',NULL,'2026-02-28 02:13:29'),(364,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 02:17:41'),(365,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:17:41'),(366,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:17:42'),(367,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:17:42'),(368,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:17:42'),(369,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:17:42'),(370,'89.205.255.117',46,'api/gymies/gym/alerts/open_settlements/complete',NULL,'2026-02-28 02:18:01'),(371,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:18:01'),(372,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:18:01'),(373,'89.205.255.117',46,'api/gymies/gym/alerts/no_show_followups/complete',NULL,'2026-02-28 02:18:07'),(374,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:18:07'),(375,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:18:07'),(376,'89.205.255.117',46,'api/gymies/gym/alerts/trainers_without_availability/complete',NULL,'2026-02-28 02:18:10'),(377,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:18:10'),(378,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:18:10'),(379,'89.205.255.117',46,'api/gymies/gym/alerts/expired_payment_method/complete',NULL,'2026-02-28 02:18:11'),(380,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:18:11'),(381,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:18:11'),(382,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 02:26:27'),(383,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:26:27'),(384,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:26:28'),(385,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:26:28'),(386,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:26:28'),(387,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:26:28'),(388,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 02:28:28'),(389,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:28:28'),(390,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:28:28'),(391,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:28:28'),(392,'89.205.255.117',46,'api/gymies/gym/membership',NULL,'2026-02-28 02:28:28'),(393,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:28:28'),(394,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:28:47'),(395,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:28:47'),(396,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:28:49'),(397,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 02:28:49'),(398,'89.205.255.117',46,'api/gymies/gym/bookings/30',NULL,'2026-02-28 02:28:51'),(399,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:28:55'),(400,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 02:28:55'),(401,'89.205.255.117',46,'api/gymies/gym/clients',NULL,'2026-02-28 02:28:56'),(402,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:28:58'),(403,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 02:28:58'),(404,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 02:28:59'),(405,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:28:59'),(406,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 02:28:59'),(407,'89.205.255.117',46,'api/gymies/gym/bookings/export',NULL,'2026-02-28 02:29:08'),(408,'89.205.255.117',46,'api/gymies/gym/trainers/export',NULL,'2026-02-28 02:29:14'),(409,'89.205.255.117',46,'api/gymies/gym/trainers',NULL,'2026-02-28 02:33:41'),(410,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:33:41'),(411,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 02:33:41'),(412,'89.205.255.117',46,'api/gymies/gym/clients',NULL,'2026-02-28 02:33:42'),(413,'89.205.255.117',46,'api/gymies/gym/settlements',NULL,'2026-02-28 02:33:43'),(414,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:33:43'),(415,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 02:33:43'),(416,'89.205.255.117',46,'api/gymies/gym/clients',NULL,'2026-02-28 02:33:44'),(417,'89.205.255.117',46,'api/gymies/gym/bookings',NULL,'2026-02-28 02:33:53'),(418,'89.205.255.117',46,'api/gymies/gym/bookings/stats',NULL,'2026-02-28 02:33:53'),(419,'89.205.255.117',46,'api/gymies/gym/dashboard',NULL,'2026-02-28 02:34:00'),(420,'89.205.255.117',46,'api/gymies/gym/dashboard-stats',NULL,'2026-02-28 02:34:00'),(421,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 03:13:03'),(422,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:13:04'),(423,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:13:04'),(424,'89.205.255.117',2,'api/gymies/gym/dashboard',NULL,'2026-02-28 03:13:04'),(425,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:13:04'),(426,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 03:13:47'),(427,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:13:47'),(428,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:13:47'),(429,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:13:48'),(430,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-28 03:13:48'),(431,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:14:00'),(432,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-28 03:14:00'),(433,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-28 03:14:02'),(434,'89.205.255.117',2,'api/gymies/notifications',NULL,'2026-02-28 03:14:02'),(435,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-28 03:14:03'),(436,'89.205.255.117',2,'api/gymies/notifications',NULL,'2026-02-28 03:14:04'),(437,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:14:11'),(438,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-28 03:14:30'),(439,'89.205.255.117',2,'api/gymies/consent',NULL,'2026-02-28 03:15:02'),(440,'89.205.255.117',2,'api/gymies/notifications/preferences',NULL,'2026-02-28 03:15:02'),(441,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:15:08'),(442,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-28 03:16:23'),(443,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:16:26'),(444,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-28 03:16:40'),(445,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-28 03:16:51'),(446,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:16:51'),(447,'89.205.255.117',2,'api/gymies/gdpr/export',NULL,'2026-02-28 03:16:58'),(448,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:17:02'),(449,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-28 03:17:07'),(450,'89.205.255.117',2,'api/gymies/bookings',NULL,'2026-02-28 03:17:07'),(451,'89.205.255.117',2,'api/gymies/gym/membership',NULL,'2026-02-28 03:17:22'),(452,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 04:04:29'),(453,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 04:07:43'),(454,'89.205.255.117',58,'api/gymies/bookings',NULL,'2026-02-28 04:07:44'),(455,'89.205.255.117',2,'api/gymies/auth/sessions',NULL,'2026-02-28 04:08:16'),(456,'89.205.255.117',2,'api/gymies/auth/logout-device',NULL,'2026-02-28 04:08:16'),(457,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 04:12:13'),(458,'89.205.255.117',58,'api/gymies/gym/membership',NULL,'2026-02-28 04:12:14'),(459,'89.205.255.117',58,'api/gymies/gym/membership',NULL,'2026-02-28 04:12:14'),(460,'89.205.255.117',58,'api/gymies/gym/membership',NULL,'2026-02-28 04:12:14'),(461,'89.205.255.117',58,'api/gymies/bookings',NULL,'2026-02-28 04:12:14'),(462,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 04:17:09'),(463,'89.205.255.117',58,'api/gymies/gym/membership',NULL,'2026-02-28 04:17:09'),(464,'89.205.255.117',58,'api/gymies/gym/membership',NULL,'2026-02-28 04:17:09'),(465,'89.205.255.117',58,'api/gymies/vault-console/overview',NULL,'2026-02-28 04:17:09'),(466,'89.205.255.117',58,'api/gymies/vault-console/payments',NULL,'2026-02-28 04:17:09'),(467,'89.205.255.117',58,'api/gymies/vault-console/users',NULL,'2026-02-28 04:17:09'),(468,'89.205.255.117',58,'api/gymies/vault-console/audit',NULL,'2026-02-28 04:17:09'),(469,'89.205.255.117',58,'api/gymies/vault-console/tickets',NULL,'2026-02-28 04:17:09'),(470,'89.205.255.117',58,'api/gymies/vault-console/security/ip-allowlist',NULL,'2026-02-28 04:17:09'),(471,'89.205.255.117',58,'api/gymies/vault-console/payouts',NULL,'2026-02-28 04:17:09'),(472,'89.205.255.117',58,'api/gymies/vault-console/bookings-monitor',NULL,'2026-02-28 04:17:09'),(473,'89.205.255.117',58,'api/gymies/vault-console/security/events',NULL,'2026-02-28 04:17:09'),(474,'89.205.255.117',58,'api/gymies/vault-console/organisations',NULL,'2026-02-28 04:17:09'),(475,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 04:21:39'),(476,'89.205.255.117',58,'api/gymies/gym/membership',NULL,'2026-02-28 04:21:39'),(477,'89.205.255.117',58,'api/gymies/gym/membership',NULL,'2026-02-28 04:21:40'),(478,'89.205.255.117',58,'api/gymies/vault-console/payments',NULL,'2026-02-28 04:21:40'),(479,'89.205.255.117',58,'api/gymies/vault-console/users',NULL,'2026-02-28 04:21:40'),(480,'89.205.255.117',58,'api/gymies/vault-console/security/events',NULL,'2026-02-28 04:21:40'),(481,'89.205.255.117',58,'api/gymies/vault-console/security/ip-allowlist',NULL,'2026-02-28 04:21:40'),(482,'89.205.255.117',58,'api/gymies/vault-console/bookings-monitor',NULL,'2026-02-28 04:21:40'),(483,'89.205.255.117',58,'api/gymies/vault-console/tickets',NULL,'2026-02-28 04:21:40'),(484,'89.205.255.117',58,'api/gymies/vault-console/audit',NULL,'2026-02-28 04:21:40'),(485,'89.205.255.117',58,'api/gymies/vault-console/overview',NULL,'2026-02-28 04:21:40'),(486,'89.205.255.117',58,'api/gymies/vault-console/payouts',NULL,'2026-02-28 04:21:40'),(487,'89.205.255.117',58,'api/gymies/vault-console/organisations',NULL,'2026-02-28 04:21:40'),(488,'89.205.255.117',58,'api/gymies/vault-console/organisations/2/members',NULL,'2026-02-28 04:22:19'),(489,'89.205.255.117',58,'api/gymies/vault-console/organisations/1/members',NULL,'2026-02-28 04:22:30'),(490,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 04:39:28'),(491,'89.205.255.117',58,'api/gymies/gym/membership',NULL,'2026-02-28 04:39:28'),(492,'89.205.255.117',58,'api/gymies/vault-console/payments',NULL,'2026-02-28 04:39:28'),(493,'89.205.255.117',58,'api/gymies/vault-console/payouts',NULL,'2026-02-28 04:39:28'),(494,'89.205.255.117',58,'api/gymies/gym/membership',NULL,'2026-02-28 04:39:28'),(495,'89.205.255.117',58,'api/gymies/vault-console/bookings-monitor',NULL,'2026-02-28 04:39:28'),(496,'89.205.255.117',58,'api/gymies/vault-console/tickets',NULL,'2026-02-28 04:39:28'),(497,'89.205.255.117',58,'api/gymies/vault-console/overview',NULL,'2026-02-28 04:39:28'),(498,'89.205.255.117',58,'api/gymies/vault-console/users',NULL,'2026-02-28 04:39:28'),(499,'89.205.255.117',58,'api/gymies/vault-console/audit',NULL,'2026-02-28 04:39:28'),(500,'89.205.255.117',58,'api/gymies/vault-console/security/events',NULL,'2026-02-28 04:39:28'),(501,'89.205.255.117',58,'api/gymies/vault-console/security/ip-allowlist',NULL,'2026-02-28 04:39:28'),(502,'89.205.255.117',58,'api/gymies/vault-console/organisations',NULL,'2026-02-28 04:39:28'),(503,'89.205.255.117',NULL,'api/gymies/login',NULL,'2026-02-28 04:40:47'),(504,'89.205.255.117',58,'api/gymies/gym/membership',NULL,'2026-02-28 04:40:47'),(505,'89.205.255.117',58,'api/gymies/gym/membership',NULL,'2026-02-28 04:40:48'),(506,'89.205.255.117',58,'api/gymies/vault-console/bookings-monitor',NULL,'2026-02-28 04:40:48'),(507,'89.205.255.117',58,'api/gymies/vault-console/overview',NULL,'2026-02-28 04:40:48'),(508,'89.205.255.117',58,'api/gymies/vault-console/payouts',NULL,'2026-02-28 04:40:48'),(509,'89.205.255.117',58,'api/gymies/vault-console/security/events',NULL,'2026-02-28 04:40:48'),(510,'89.205.255.117',58,'api/gymies/vault-console/tickets',NULL,'2026-02-28 04:40:48'),(511,'89.205.255.117',58,'api/gymies/vault-console/users',NULL,'2026-02-28 04:40:48'),(512,'89.205.255.117',58,'api/gymies/vault-console/payments',NULL,'2026-02-28 04:40:48'),(513,'89.205.255.117',58,'api/gymies/vault-console/security/ip-allowlist',NULL,'2026-02-28 04:40:48'),(514,'89.205.255.117',58,'api/gymies/vault-console/organisations',NULL,'2026-02-28 04:40:48'),(515,'89.205.255.117',58,'api/gymies/vault-console/audit',NULL,'2026-02-28 04:40:48'),(516,'89.205.255.117',58,'api/gymies/vault-console/organisations',NULL,'2026-02-28 04:40:58'),(517,'89.205.255.117',58,'api/gymies/vault-console/security/ip-allowlist',NULL,'2026-02-28 04:40:58'),(518,'89.205.255.117',58,'api/gymies/vault-console/security/events',NULL,'2026-02-28 04:40:58'),(519,'89.205.255.117',58,'api/gymies/vault-console/bookings-monitor',NULL,'2026-02-28 04:40:58'),(520,'89.205.255.117',58,'api/gymies/vault-console/payments',NULL,'2026-02-28 04:40:58'),(521,'89.205.255.117',58,'api/gymies/vault-console/tickets',NULL,'2026-02-28 04:40:58'),(522,'89.205.255.117',58,'api/gymies/vault-console/users',NULL,'2026-02-28 04:40:58'),(523,'89.205.255.117',58,'api/gymies/vault-console/overview',NULL,'2026-02-28 04:40:58'),(524,'89.205.255.117',58,'api/gymies/vault-console/audit',NULL,'2026-02-28 04:40:58'),(525,'89.205.255.117',58,'api/gymies/vault-console/payouts',NULL,'2026-02-28 04:40:58'),(526,'89.205.255.117',58,'api/gymies/vault-console/users',NULL,'2026-02-28 04:41:00'),(527,'89.205.255.117',58,'api/gymies/vault-console/payments',NULL,'2026-02-28 04:41:00'),(528,'89.205.255.117',58,'api/gymies/vault-console/bookings-monitor',NULL,'2026-02-28 04:41:00'),(529,'89.205.255.117',58,'api/gymies/vault-console/tickets',NULL,'2026-02-28 04:41:00'),(530,'89.205.255.117',58,'api/gymies/vault-console/organisations',NULL,'2026-02-28 04:41:00'),(531,'89.205.255.117',58,'api/gymies/vault-console/payouts',NULL,'2026-02-28 04:41:00'),(532,'89.205.255.117',58,'api/gymies/vault-console/overview',NULL,'2026-02-28 04:41:00'),(533,'89.205.255.117',58,'api/gymies/vault-console/audit',NULL,'2026-02-28 04:41:00'),(534,'89.205.255.117',58,'api/gymies/vault-console/security/events',NULL,'2026-02-28 04:41:00'),(535,'89.205.255.117',58,'api/gymies/vault-console/security/ip-allowlist',NULL,'2026-02-28 04:41:00');
/*!40000 ALTER TABLE `gymies_rate_limit_events` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_referrals`
--

DROP TABLE IF EXISTS `gymies_referrals`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_referrals` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `referrer_user_id` bigint unsigned NOT NULL,
  `referred_user_id` bigint unsigned DEFAULT NULL,
  `referred_email` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `referral_code` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('pending','completed','expired') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `reward_cents` int unsigned DEFAULT NULL,
  `rewarded_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_referrals_code_unique` (`referral_code`),
  KEY `gymies_referrals_referrer` (`referrer_user_id`),
  KEY `gymies_referrals_referred_fk` (`referred_user_id`),
  CONSTRAINT `gymies_referrals_referred_fk` FOREIGN KEY (`referred_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_referrals_referrer_fk` FOREIGN KEY (`referrer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_referrals`
--

LOCK TABLES `gymies_referrals` WRITE;
/*!40000 ALTER TABLE `gymies_referrals` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_referrals` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_report_cache`
--

DROP TABLE IF EXISTS `gymies_report_cache`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_report_cache` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `report_type` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `period_key` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Bijv. 2026-02 of week-2026-08',
  `data_json` json NOT NULL,
  `generated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_report_cache_unique` (`report_type`,`period_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_report_cache`
--

LOCK TABLES `gymies_report_cache` WRITE;
/*!40000 ALTER TABLE `gymies_report_cache` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_report_cache` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_review_reports`
--

DROP TABLE IF EXISTS `gymies_review_reports`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_review_reports` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `review_id` bigint unsigned NOT NULL,
  `reported_by_user_id` bigint unsigned NOT NULL,
  `reason` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('open','resolved','rejected') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'open',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_review_reports_review_fk` (`review_id`),
  KEY `gymies_review_reports_user_fk` (`reported_by_user_id`),
  CONSTRAINT `gymies_review_reports_review_fk` FOREIGN KEY (`review_id`) REFERENCES `gymies_reviews` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_review_reports_user_fk` FOREIGN KEY (`reported_by_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_review_reports`
--

LOCK TABLES `gymies_review_reports` WRITE;
/*!40000 ALTER TABLE `gymies_review_reports` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_review_reports` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_review_responses`
--

DROP TABLE IF EXISTS `gymies_review_responses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_review_responses` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `review_id` bigint unsigned NOT NULL,
  `trainer_user_id` bigint unsigned NOT NULL,
  `body` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_review_responses_review_unique` (`review_id`),
  KEY `gymies_review_responses_trainer_fk` (`trainer_user_id`),
  CONSTRAINT `gymies_review_responses_review_fk` FOREIGN KEY (`review_id`) REFERENCES `gymies_reviews` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_review_responses_trainer_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_review_responses`
--

LOCK TABLES `gymies_review_responses` WRITE;
/*!40000 ALTER TABLE `gymies_review_responses` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_review_responses` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_reviews`
--

DROP TABLE IF EXISTS `gymies_reviews`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_reviews` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `booking_id` bigint unsigned NOT NULL,
  `client_user_id` bigint unsigned NOT NULL COMMENT 'Klant die de review schrijft',
  `trainer_user_id` bigint unsigned NOT NULL COMMENT 'Trainer die beoordeeld wordt',
  `rating` tinyint unsigned NOT NULL COMMENT '1-5 sterren',
  `review_text` text COLLATE utf8mb4_unicode_ci,
  `status` enum('pending','approved','rejected') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'approved',
  `moderated_at` timestamp NULL DEFAULT NULL,
  `moderated_by_user_id` bigint unsigned DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_reviews_booking_unique` (`booking_id`) COMMENT 'Eén review per boeking',
  KEY `gymies_reviews_trainer` (`trainer_user_id`),
  KEY `gymies_reviews_rating` (`rating`),
  KEY `gymies_reviews_status` (`status`),
  KEY `gymies_reviews_client_fk` (`client_user_id`),
  KEY `gymies_reviews_moderator_fk` (`moderated_by_user_id`),
  CONSTRAINT `gymies_reviews_booking_fk` FOREIGN KEY (`booking_id`) REFERENCES `gymies_bookings` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_reviews_client_fk` FOREIGN KEY (`client_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_reviews_moderator_fk` FOREIGN KEY (`moderated_by_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_reviews_trainer_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_reviews`
--

LOCK TABLES `gymies_reviews` WRITE;
/*!40000 ALTER TABLE `gymies_reviews` DISABLE KEYS */;
INSERT INTO `gymies_reviews` VALUES (1,3,23,3,5,'Super duidelijke uitleg en fijne energie.','approved',NULL,NULL,'2026-02-27 04:14:26'),(2,4,24,4,4,'Goede opbouw en strak schema.','approved',NULL,NULL,'2026-02-27 04:14:26'),(3,5,25,5,5,'Heel professioneel en blessurevrij opgebouwd.','approved',NULL,NULL,'2026-02-27 04:14:26'),(4,6,23,6,4,'Intensieve sessie, precies wat ik nodig had.','approved',NULL,NULL,'2026-02-27 04:14:26'),(5,7,24,7,5,'Empathisch en toch resultaatgericht.','approved',NULL,NULL,'2026-02-27 04:14:26'),(6,8,25,8,4,'Fijne hardloopcoaching met praktische tips.','approved',NULL,NULL,'2026-02-27 04:14:26'),(7,9,23,9,5,'Top bokstraining, motiverend en veilig.','approved',NULL,NULL,'2026-02-27 04:14:26'),(8,10,24,10,4,'Heldere progressie in oefeningen.','approved',NULL,NULL,'2026-02-27 04:14:26'),(9,11,25,11,5,'Rustige coach, veel aandacht voor techniek.','approved',NULL,NULL,'2026-02-27 04:14:26'),(10,12,23,12,4,'Geduldig en goed afgestemd op niveau.','approved',NULL,NULL,'2026-02-27 04:14:26'),(16,21,39,27,5,'Super motiverend en duidelijk schema, top coach.','approved',NULL,NULL,'2026-02-27 14:10:11'),(17,22,40,27,4,'Goede techniek-correcties en fijne energie.','approved',NULL,NULL,'2026-02-27 14:10:11');
/*!40000 ALTER TABLE `gymies_reviews` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_reward_redemptions`
--

DROP TABLE IF EXISTS `gymies_reward_redemptions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_reward_redemptions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `reward_type` enum('discount','free_session','wallet_credit') COLLATE utf8mb4_unicode_ci NOT NULL,
  `points_spent` int unsigned NOT NULL,
  `booking_id` bigint unsigned DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_reward_redemptions_user_fk` (`user_id`),
  KEY `gymies_reward_redemptions_booking_fk` (`booking_id`),
  CONSTRAINT `gymies_reward_redemptions_booking_fk` FOREIGN KEY (`booking_id`) REFERENCES `gymies_bookings` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_reward_redemptions_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_reward_redemptions`
--

LOCK TABLES `gymies_reward_redemptions` WRITE;
/*!40000 ALTER TABLE `gymies_reward_redemptions` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_reward_redemptions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_search_recommendations`
--

DROP TABLE IF EXISTS `gymies_search_recommendations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_search_recommendations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned DEFAULT NULL COMMENT 'Voor personalisatie; NULL = algemeen',
  `trainer_user_id` bigint unsigned NOT NULL,
  `reason` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'also_viewed, popular_nearby, etc.',
  `score` decimal(8,4) NOT NULL DEFAULT '0.0000',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_search_recommendations_user` (`user_id`),
  KEY `gymies_search_recommendations_trainer` (`trainer_user_id`),
  CONSTRAINT `gymies_search_recommendations_trainer_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_search_recommendations_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_search_recommendations`
--

LOCK TABLES `gymies_search_recommendations` WRITE;
/*!40000 ALTER TABLE `gymies_search_recommendations` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_search_recommendations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_sessions`
--

DROP TABLE IF EXISTS `gymies_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_sessions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `token` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `expires_at` timestamp NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `ip_address` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_agent` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `revoked_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_sessions_token_unique` (`token`),
  KEY `gymies_sessions_user` (`user_id`),
  KEY `gymies_sessions_expires` (`expires_at`),
  CONSTRAINT `gymies_sessions_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=94 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_sessions`
--

LOCK TABLES `gymies_sessions` WRITE;
/*!40000 ALTER TABLE `gymies_sessions` DISABLE KEYS */;
INSERT INTO `gymies_sessions` VALUES (1,1,'812c02698e1cf3fa6c245dd2fd4678a7a5a7a8eeddf0f0e167871ce151619f7b','2026-03-29 02:33:20','2026-02-27 02:33:20',NULL,NULL,NULL),(2,1,'1415ba878263025a7015c429d48201dc90eee325635ce4a7db7b996775f90475','2026-03-29 03:02:08','2026-02-27 03:02:08',NULL,NULL,NULL),(3,2,'0ded7b18648ed8cd45364f723e04e0e5de48a2614c40bf7d931a1ce6ce9c92df','2026-03-29 03:05:37','2026-02-27 03:05:37',NULL,NULL,NULL),(4,2,'ce6ce48a801f5d0f4d5eb562d408f8070a6c4e14c062675e594b21f3cfdd3392','2026-03-29 03:08:24','2026-02-27 03:08:24',NULL,NULL,NULL),(5,2,'f8a739930843eefa35fdc8bae5090b871501cd8dc53c7d86ee523f38639f681a','2026-03-29 03:16:17','2026-02-27 03:16:17',NULL,NULL,NULL),(6,2,'e9398662132c8879bc5da676798ebf8eda43a900d06ecbb332ad0b7a24c34f0c','2026-03-29 03:23:46','2026-02-27 03:23:46',NULL,NULL,NULL),(7,2,'e2f1ce535797ed181f0fe08417352c74ad517165ef66dc7da048d0e40c2c2d37','2026-03-29 03:41:35','2026-02-27 03:41:35',NULL,NULL,NULL),(8,2,'b00feb75b0f89d107ba5c139e21da7154f27f7760fa044cd02c9419c64fa91d6','2026-03-29 03:53:22','2026-02-27 03:53:22',NULL,NULL,NULL),(9,2,'b339cd212d439d996d92ea9b16cd761ffa50728aca09722e51b603cc7272918a','2026-03-29 03:58:11','2026-02-27 03:58:11',NULL,NULL,NULL),(10,2,'e9b3d3ca9006060562d6d11c4fa9b7faa13ad5d86e687e90ce83e9d8982cddf9','2026-03-29 03:59:25','2026-02-27 03:59:25',NULL,NULL,NULL),(11,2,'a99fa35dfa5f5bdf4aab73d64ea51459eca282cd0125c43358acff7990aabac8','2026-03-29 04:19:43','2026-02-27 04:19:43',NULL,NULL,NULL),(12,2,'d274c2d447f3bc0b50b37b54bbbf185b6f83a2d001fd9506e126116c3b2df489','2026-03-29 04:21:18','2026-02-27 04:21:18',NULL,NULL,NULL),(13,2,'878d1effd6a559ba3be06262dc0c451e9b7dbde740d72e88adc077a17198551f','2026-03-29 04:23:16','2026-02-27 04:23:16',NULL,NULL,NULL),(14,2,'aeaf5fc6a3fbd8e8205b74d53c3a719be9b2a97fbfddd46326872f20ff2d4812','2026-03-29 04:34:49','2026-02-27 04:34:49',NULL,NULL,NULL),(15,2,'ed1a826db63481b8b2e962fab8e3bb1a5087ded1830422990264faa73abe2d21','2026-03-29 04:38:44','2026-02-27 04:38:44',NULL,NULL,NULL),(16,2,'30f2df72cceb5d5ee9ca3ad5689c83bb3fa37a8520a33699180ffc7a5959e881','2026-03-29 04:43:16','2026-02-27 04:43:16',NULL,NULL,NULL),(17,26,'142a10f2568d0624649932527b29a413b1619495a21e7dbc30fea9ce2348ab67','2026-03-29 05:04:48','2026-02-27 05:04:48',NULL,NULL,NULL),(18,2,'a59f366f15e1b035399783203b48f07fc3c168bb1acd805055e4c5d0029f42d9','2026-03-29 05:07:52','2026-02-27 05:07:52',NULL,NULL,NULL),(19,2,'1d22a1c4693e0519872558b024dd595e4fccec7b51ece99087adedc345bdf65f','2026-03-29 05:11:25','2026-02-27 05:11:25',NULL,NULL,NULL),(20,2,'7cba4e4f1fa4dc3ae3f1893782f5eb516798a7b425249345fd6c354c95c502ce','2026-03-29 05:13:24','2026-02-27 05:13:24',NULL,NULL,NULL),(21,27,'bfec17f7ae44d4c61d7753c0d794c50de9738c5458d2925284e896a3f0b2da01','2026-03-29 13:59:15','2026-02-27 13:59:15',NULL,NULL,NULL),(22,27,'3d57cd19fd91f1921aedde0a55985e514b40bc4fdfe34ea90915183644ee711a','2026-03-29 14:03:52','2026-02-27 14:03:52',NULL,NULL,NULL),(23,27,'c2874f0f923c065339b53fd7d00477d5eaf8cbc0c4a09ee3c1244297802bc482','2026-03-29 14:04:44','2026-02-27 14:04:44',NULL,NULL,NULL),(24,27,'f0921335ab051b5c182afd7a51b420d723593dbf843657e12970a3eab6255402','2026-03-29 14:06:37','2026-02-27 14:06:37',NULL,NULL,NULL),(25,27,'11b064111379802e57cb05a66ac095acd8de8a305f974608c85145bd3ec73c1f','2026-03-29 14:10:50','2026-02-27 14:10:50',NULL,NULL,NULL),(26,27,'342d28a0dab8ea48ed00e94a8c0f058e2966707ac4393728065bf68478dcf74c','2026-03-29 14:16:56','2026-02-27 14:16:56',NULL,NULL,NULL),(27,27,'db5779c007146974ee662662196da428fa4cc99990c3f58d861b86683c39d826','2026-03-29 14:24:11','2026-02-27 14:24:11',NULL,NULL,NULL),(28,27,'df92e9a2604e03d5b4deea6f0ee6c56a7cd0c0d24a47ce314016f42e92545bd3','2026-03-29 14:24:59','2026-02-27 14:24:59',NULL,NULL,NULL),(29,27,'5883db896692f143cb47aad94a3717cc8f86d2f52ee6254507a561087943a984','2026-03-29 14:44:01','2026-02-27 14:44:01',NULL,NULL,NULL),(30,27,'b47c17026763fa7c15cb4f66438c388dea729ac1850348e0abd563edcc3e7063','2026-03-29 14:45:40','2026-02-27 14:45:40',NULL,NULL,NULL),(31,27,'f3a633bf03f19a08a377f526b324bfc28e082ef6b866214e6d257cfe81393b65','2026-03-29 15:11:26','2026-02-27 15:11:26',NULL,NULL,NULL),(32,27,'93dc37b48b703c89f349e5d7a5a11f26b078a44ec2e64e123dcf7dd71f70c3e4','2026-03-29 15:11:46','2026-02-27 15:11:46',NULL,NULL,NULL),(33,27,'b147ede9d59705d81778cd9a8134518b8084c1f2d6bc590b2b0371fee75c19f1','2026-03-29 15:51:43','2026-02-27 15:51:43',NULL,NULL,NULL),(34,27,'697ccef8cd78584979ed198807df9587214e044f8c7b980999adc4162c1bea74','2026-03-29 16:15:06','2026-02-27 16:15:06',NULL,NULL,NULL),(35,27,'d61a4dfba12f646de59c8f11a41f3f3382c563c8f04d1a1cd2c98fc6beeb45b3','2026-03-29 16:19:51','2026-02-27 16:19:51',NULL,NULL,NULL),(36,27,'9e6a5719b2541e18353c02b2b6cfcfdd2c40ebfb8be3e41f350da2d68747593f','2026-03-29 16:27:12','2026-02-27 16:27:12',NULL,NULL,NULL),(37,27,'9f81b8fbec9de8ed889180669c1de9515822f5a251ac473ac606acdd090a4532','2026-03-29 16:35:57','2026-02-27 16:35:57',NULL,NULL,NULL),(38,27,'3cde4a1fb255579a65a041cd9cdf0fd81e56ee0cd6a9a40833c469888547ef9f','2026-03-29 16:47:18','2026-02-27 16:47:18',NULL,NULL,NULL),(39,27,'ec0337da3316247d4200390f8dfa95149a8c5826f5db58e203d5fbf54867dc62','2026-03-29 16:54:06','2026-02-27 16:54:06',NULL,NULL,NULL),(40,27,'fc938847d99eb0ec6595a73db7f94e0f2475a9853df793661579ab50ab3329fe','2026-03-29 17:05:06','2026-02-27 17:05:06',NULL,NULL,NULL),(41,27,'4bf5085d5d4fc4d011ca105a00f14a9777bb2cc69023d73291b2f7fe19b86854','2026-03-29 17:12:18','2026-02-27 17:12:18',NULL,NULL,NULL),(42,2,'486043c5a4a1e71c23210c1a39989d08173e0a577d32f042a2b85993f194ecdf','2026-03-29 19:05:31','2026-02-27 19:05:31',NULL,NULL,NULL),(43,27,'4d790b7075fcaedb4d3d2e3d899cc0d20cc4321ac18d2d09e264f6c0ed6d5bb0','2026-03-29 19:50:29','2026-02-27 19:50:29',NULL,NULL,NULL),(44,2,'e3ad869906e481490a64c694c7554c16b265d4a5a2235e878cbbd665e146ad6a','2026-03-29 19:56:01','2026-02-27 19:56:01',NULL,NULL,NULL),(45,2,'a8d4b4035cdb63f9f6a64ac3500b630449fff0ba4a839a4c45a3acbb42fa1a96','2026-03-29 20:09:55','2026-02-27 20:09:55',NULL,NULL,NULL),(51,2,'4acd0435c1311e9a20b18befc589a88a599702c87defff3c1b292b1683dcf4ba','2026-03-29 23:34:37','2026-02-27 23:34:10','89.205.255.117','Mozilla/5.0 (iPhone; CPU iPhone OS 18_5_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/137.0.7151.79 Mobile/15E148 Safari/604.1',NULL),(55,46,'23164b895280a9013e1c59f7fef042f808a1b37337d594405a696513c0b0627c','2026-03-30 00:38:28','2026-02-28 00:38:26','89.205.255.117','curl/8.7.1',NULL),(58,46,'8ce18aee8a79474f785aeb4d5088a226c2c9027bd42e3706a273eb40e2ae3b4e','2026-03-30 00:46:03','2026-02-28 00:46:03','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(59,46,'939003efa2bed4b33b6ac6b092637364bea7f5a68c58d527aa4eda2533d9c9a4','2026-03-30 00:50:16','2026-02-28 00:50:16','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(60,46,'f24250247590f70b4a9082bc1605e66d06c3ccb83265dfe4df2974867c36e52b','2026-03-30 00:52:09','2026-02-28 00:52:05','89.205.255.117','curl/8.7.1',NULL),(61,46,'4b5cf0c0d9d6ea227a6e648d671db11d45c0b7632366135357bf90bb1c957645','2026-03-30 00:54:50','2026-02-28 00:53:18','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(62,46,'4c1773c426994a1d41dcf7a165bc54f1214d994e8f3aed89e72d658e96b08083','2026-03-30 00:55:56','2026-02-28 00:55:55','89.205.255.117','curl/8.7.1',NULL),(63,46,'bb2b9ee387bd0e46367642b6f5e1fc1eaeb7b46deb0d6f5e888b24c5a4ef2499','2026-03-30 00:57:28','2026-02-28 00:57:28','89.205.255.117','curl/8.7.1',NULL),(65,46,'840c8237afe91e48105682d9ed6f2d5ea5d80a7b8712127944f18abff4b187b3','2026-03-30 01:18:41','2026-02-28 01:09:19','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(66,46,'2949fcb703735aede5ca8861063fcf56d2ba41adc73c72b03bba025b77aec6e2','2026-03-30 01:15:31','2026-02-28 01:15:31','89.205.255.117','curl/8.7.1',NULL),(67,46,'638244f71dff441f8b5ea7b9d86f888c4c544f0c874fb5d1cb3749c4f545aed0','2026-03-30 01:16:19','2026-02-28 01:16:19','89.205.255.117','curl/8.7.1',NULL),(68,46,'71419cbfdde4f6470f6481ce56c2e8ddc4568754aa77ce90bc5daef38e478c85','2026-03-30 01:16:28','2026-02-28 01:16:27','89.205.255.117','curl/8.7.1',NULL),(69,46,'3842cbda385ed4933fd22e5e7c6586e2231f8e05b65275cfab2009141b4ecd80','2026-03-30 01:19:03','2026-02-28 01:18:51','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(70,46,'6418b1f1eb16be4b2fc8d21d64395fbe177376c7f5795da5cb7dafd01ff72b25','2026-03-30 01:21:51','2026-02-28 01:21:12','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(72,46,'f2d3ff1faa3a2f50f1704de65efc59b4040ee77c70f543bc0fc83b52de3bd522','2026-03-30 01:26:36','2026-02-28 01:26:29','89.205.255.117','curl/8.7.1',NULL),(73,46,'1a5246fe1fe6c66accc95620d65b792e683a98ea02c23a015d9fe47f5ef0598d','2026-03-30 01:30:32','2026-02-28 01:30:32','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(74,46,'50b985d91371d401a855533ca8f610abb8b4d8f867c345d4f44bdb40c6109088','2026-03-30 01:33:48','2026-02-28 01:33:48','89.205.255.117','curl/8.7.1',NULL),(76,46,'5bbf3da4be10fe6934c1b2acac61d5a8349859d8d5b5348c8331032f532fb304','2026-03-30 01:55:15','2026-02-28 01:55:15','89.205.255.117','curl/8.7.1',NULL),(77,46,'749f65cb314188ef5a5bb355159fffda1323653ddbb0cdb34b1c92d5a3465aff','2026-03-30 01:55:19','2026-02-28 01:55:19','89.205.255.117','curl/8.7.1',NULL),(78,46,'c9efcfe7051c2be5a9fe12e74dbf121738423f7ad42a70dbe88550bb4df54662','2026-03-30 01:55:25','2026-02-28 01:55:24','89.205.255.117','curl/8.7.1',NULL),(79,46,'666b7f9c400be5e430c393cd7e0f0f6b6749c6f014163bb07d83688728227c9b','2026-03-30 01:57:29','2026-02-28 01:57:25','89.205.255.117','Python-urllib/3.9',NULL),(80,46,'4c2dad68ecf15a6d84814392157d34b4af5b175789d3577a79f9dd81fe2dd75e','2026-03-30 02:00:18','2026-02-28 01:59:57','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(81,46,'4bc32cad30a737b242b2c75ece1c9911ec39fa7bf74d398b29caa7ba88ad8556','2026-03-30 02:05:10','2026-02-28 02:03:46','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(82,46,'735bd92e90cd2f4059d9201446b8c01cd7526c8339caf383559a92c7cbbcaeb0','2026-03-30 02:13:29','2026-02-28 02:13:27','89.205.255.117','Python-urllib/3.9',NULL),(83,46,'e4b2f7332e3721513e0817499478d6958a6bc196d067ddc04124f39faa57c7cd','2026-03-30 02:18:11','2026-02-28 02:17:41','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(84,46,'8eb1fc33291aa555d5bdc5388575b3ad12a52d5a2a675d26b9e215774f513535','2026-03-30 02:26:28','2026-02-28 02:26:27','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(85,46,'9c9f35268bf4fd88feed688591726a37f3e78a431dfbd984ec0503a81ad72e37','2026-03-30 02:34:00','2026-02-28 02:28:28','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(86,2,'b44ef8335a3056d42bdbdcef63b4671a3510e96261b476b23a0b9051e9c47d36','2026-03-30 03:13:04','2026-02-28 03:13:04','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(87,2,'648d7e5808a24d860dad37d3f65356ff459317a2cbdb0246fd3aa698c1b4abbe','2026-03-14 04:08:16','2026-02-28 03:13:47','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36','2026-02-28 04:08:16'),(88,58,'61679b7a36067b135f104d53ae657164e4535db5fd6057ae6cf77afed0d60725','2026-03-14 04:07:44','2026-02-28 04:07:43','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(89,58,'19b2b3acafd7f18f6196db700a7536d5953288ffc2e5422d46f460cef3b3fc01','2026-03-14 04:12:14','2026-02-28 04:12:14','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(90,58,'8c555f14777e01fa276a5d470f6d6c6d9232b9438cf9825a598cf1b886e0ffeb','2026-03-14 04:17:09','2026-02-28 04:17:09','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(91,58,'25ae6cf9b3e513f192d7fe9f9f4efd98b0836f8f950bf404f00f607bffda9fad','2026-03-14 04:22:30','2026-02-28 04:21:39','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(92,58,'c13c218de7fc9c308acbc75f1f4d493a0b4ab65312b624aa3bd5e7e4617e7cf0','2026-03-14 04:39:28','2026-02-28 04:39:28','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL),(93,58,'8ad74ba7e00b7ed731f9791623dad001879f1176a040e145d1da4b274eed01d2','2026-03-14 04:41:00','2026-02-28 04:40:47','89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',NULL);
/*!40000 ALTER TABLE `gymies_sessions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_specialties`
--

DROP TABLE IF EXISTS `gymies_specialties`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_specialties` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Bijv. Kracht, Conditie, Revalidatie',
  `sort_order` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_specialties_name_unique` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_specialties`
--

LOCK TABLES `gymies_specialties` WRITE;
/*!40000 ALTER TABLE `gymies_specialties` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_specialties` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_subscriptions`
--

DROP TABLE IF EXISTS `gymies_subscriptions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_subscriptions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `client_user_id` bigint unsigned NOT NULL,
  `plan_id` int unsigned NOT NULL,
  `status` enum('active','cancelled','expired') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'active',
  `started_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ends_at` timestamp NULL DEFAULT NULL,
  `stripe_subscription_id` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_subscriptions_client` (`client_user_id`),
  KEY `gymies_subscriptions_plan` (`plan_id`),
  KEY `gymies_subscriptions_status` (`status`),
  CONSTRAINT `gymies_subscriptions_plan_fk` FOREIGN KEY (`plan_id`) REFERENCES `gymies_plans` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_subscriptions_user_fk` FOREIGN KEY (`client_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_subscriptions`
--

LOCK TABLES `gymies_subscriptions` WRITE;
/*!40000 ALTER TABLE `gymies_subscriptions` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_subscriptions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_support_ticket_messages`
--

DROP TABLE IF EXISTS `gymies_support_ticket_messages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_support_ticket_messages` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint unsigned NOT NULL,
  `author_user_id` bigint unsigned NOT NULL,
  `message` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `is_internal` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_support_ticket_messages_ticket_idx` (`ticket_id`),
  KEY `gymies_support_ticket_messages_author_idx` (`author_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_support_ticket_messages`
--

LOCK TABLES `gymies_support_ticket_messages` WRITE;
/*!40000 ALTER TABLE `gymies_support_ticket_messages` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_support_ticket_messages` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_support_tickets`
--

DROP TABLE IF EXISTS `gymies_support_tickets`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_support_tickets` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `subject` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `category` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'general',
  `priority` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'medium',
  `status` varchar(40) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'new',
  `assigned_to_user_id` bigint unsigned DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `resolved_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `gymies_support_tickets_user_idx` (`user_id`),
  KEY `gymies_support_tickets_status_idx` (`status`),
  KEY `gymies_support_tickets_priority_idx` (`priority`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_support_tickets`
--

LOCK TABLES `gymies_support_tickets` WRITE;
/*!40000 ALTER TABLE `gymies_support_tickets` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_support_tickets` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_system_settings`
--

DROP TABLE IF EXISTS `gymies_system_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_system_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `setting_key` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL,
  `setting_value` text COLLATE utf8mb4_unicode_ci,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_system_settings_key_unique` (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_system_settings`
--

LOCK TABLES `gymies_system_settings` WRITE;
/*!40000 ALTER TABLE `gymies_system_settings` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_system_settings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_trainer_bank_accounts`
--

DROP TABLE IF EXISTS `gymies_trainer_bank_accounts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_trainer_bank_accounts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_user_id` bigint unsigned NOT NULL,
  `iban_masked` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `bic` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `account_holder_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `sepa_mandate_id` varchar(128) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('pending','verified','rejected') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_trainer_bank_accounts_trainer_unique` (`trainer_user_id`),
  CONSTRAINT `gymies_trainer_bank_accounts_user_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_trainer_bank_accounts`
--

LOCK TABLES `gymies_trainer_bank_accounts` WRITE;
/*!40000 ALTER TABLE `gymies_trainer_bank_accounts` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_trainer_bank_accounts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_trainer_gallery`
--

DROP TABLE IF EXISTS `gymies_trainer_gallery`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_trainer_gallery` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_user_id` bigint unsigned NOT NULL,
  `media_type` enum('image','video') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'image',
  `media_url` varchar(512) COLLATE utf8mb4_unicode_ci NOT NULL,
  `caption` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `sort_order` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_trainer_gallery_trainer` (`trainer_user_id`),
  CONSTRAINT `gymies_trainer_gallery_user_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_trainer_gallery`
--

LOCK TABLES `gymies_trainer_gallery` WRITE;
/*!40000 ALTER TABLE `gymies_trainer_gallery` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_trainer_gallery` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_trainer_locations`
--

DROP TABLE IF EXISTS `gymies_trainer_locations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_trainer_locations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_user_id` bigint unsigned NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Bijv. Gym X, Thuis, Online',
  `address_line1` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `postcode` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `city` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `latitude` decimal(10,7) DEFAULT NULL,
  `longitude` decimal(10,7) DEFAULT NULL,
  `location_type` enum('gym','home','outdoor','online') COLLATE utf8mb4_unicode_ci DEFAULT 'gym',
  `is_primary` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_trainer_locations_trainer` (`trainer_user_id`),
  CONSTRAINT `gymies_trainer_locations_user_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_trainer_locations`
--

LOCK TABLES `gymies_trainer_locations` WRITE;
/*!40000 ALTER TABLE `gymies_trainer_locations` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_trainer_locations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_trainer_media`
--

DROP TABLE IF EXISTS `gymies_trainer_media`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_trainer_media` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_user_id` bigint unsigned NOT NULL,
  `media_type` enum('image','video') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'image',
  `source_type` enum('upload','external') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'external',
  `file_path` varchar(1024) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `external_url` varchar(1024) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `thumbnail_url` varchar(1024) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `caption` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_public` tinyint(1) NOT NULL DEFAULT '1',
  `sort_order` int unsigned NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_trainer_media_trainer` (`trainer_user_id`),
  CONSTRAINT `gymies_trainer_media_user_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_trainer_media`
--

LOCK TABLES `gymies_trainer_media` WRITE;
/*!40000 ALTER TABLE `gymies_trainer_media` DISABLE KEYS */;
INSERT INTO `gymies_trainer_media` VALUES (1,27,'image','external',NULL,'https://unsplash.com/photos/woman-boxer-punching-bag-UTMYoQu_QYM',NULL,'Kickbox',1,0,'2026-02-27 17:13:20','2026-02-27 17:13:20');
/*!40000 ALTER TABLE `gymies_trainer_media` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_trainer_profiles`
--

DROP TABLE IF EXISTS `gymies_trainer_profiles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_trainer_profiles` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `bio` text COLLATE utf8mb4_unicode_ci COMMENT 'Beschrijving van de trainer',
  `specialty` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Specialisatie(s), bijv. Kracht, Conditie, Revalidatie',
  `hourly_rate_cents` int unsigned DEFAULT NULL,
  `avatar_url` varchar(512) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Foto van de trainer',
  `intro_video_url` varchar(512) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Korte pitchvideo',
  `target_audiences` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Beginners, 50+, revalidatie, etc.',
  `gender` enum('female','male','non_binary','not_specified') COLLATE utf8mb4_unicode_ci DEFAULT 'not_specified',
  `session_languages` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Talen tijdens sessie, bijv. NL,EN',
  `trial_session_cents` int unsigned DEFAULT NULL COMMENT 'Proefsessie prijs',
  `region` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Regio(s) actief, bijv. Amsterdam, Noord-Holland, Online',
  `service_radius_km` int unsigned DEFAULT NULL COMMENT 'Radius voor zoeken op afstand',
  `travels_to_client` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Trainer komt naar klant toe',
  `address_visibility` enum('always','after_confirmation','never') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'after_confirmation',
  `trainer_verified_at` timestamp NULL DEFAULT NULL COMMENT 'Platform heeft trainer gecontroleerd',
  `certifications` text COLLATE utf8mb4_unicode_ci COMMENT 'Diploma’s/certificaten (NASM, Fitvak, etc.)',
  `experience_years` int unsigned DEFAULT NULL COMMENT 'Aantal jaar ervaring',
  `since_year` smallint unsigned DEFAULT NULL COMMENT 'Actief sinds jaar (alternatief voor ervaring)',
  `languages` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Talen, bijv. NL, EN',
  `min_session_minutes` int unsigned DEFAULT NULL COMMENT 'Minimale sessieduur in minuten',
  `min_buffer_minutes` int unsigned NOT NULL DEFAULT '15' COMMENT 'Pauze tussen sessies',
  `is_available` tinyint(1) NOT NULL DEFAULT '1' COMMENT '1 = zichtbaar/boekbaar, 0 = tijdelijk uit',
  `featured` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Uitgelicht op homepage',
  `sort_order` int DEFAULT NULL COMMENT 'Handmatige volgorde (lager = eerder)',
  `insurance_verified_at` timestamp NULL DEFAULT NULL COMMENT 'Verzekering gecontroleerd door platform',
  `insurance_expires_at` date DEFAULT NULL COMMENT 'Verloopdatum verzekering',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_trainer_profiles_user_id_unique` (`user_id`),
  KEY `gymies_trainer_profiles_available` (`is_available`),
  KEY `gymies_trainer_profiles_featured` (`featured`),
  KEY `gymies_trainer_profiles_sort` (`sort_order`),
  CONSTRAINT `gymies_trainer_profiles_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=22 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_trainer_profiles`
--

LOCK TABLES `gymies_trainer_profiles` WRITE;
/*!40000 ALTER TABLE `gymies_trainer_profiles` DISABLE KEYS */;
INSERT INTO `gymies_trainer_profiles` VALUES (1,3,'Ik help drukke professionals met kracht, houding en duurzame energie.','Krachttraining',6500,'https://images.unsplash.com/photo-1594381898411-846e7d193883?w=500&q=80',NULL,NULL,'not_specified',NULL,3500,'Amsterdam',NULL,0,'after_confirmation','2026-02-27 14:10:11','Fitvak A, NASM CPT',8,NULL,'NL, EN',60,15,1,1,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(2,4,'Conditie en vetverlies trajecten met meetbare progressie.','Conditie & Vetverlies',5900,'https://images.unsplash.com/photo-1546483875-ad9014c88eba?w=500&q=80',NULL,NULL,'not_specified',NULL,2900,'Rotterdam',NULL,0,'after_confirmation','2026-02-27 14:10:11','ACE CPT',6,NULL,'NL, EN',45,15,1,0,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(3,5,'Mobility en revalidatiegerichte coaching voor veilig opbouwen.','Mobility & Revalidatie',7200,'https://images.unsplash.com/photo-1518310383802-640c2de311b2?w=500&q=80',NULL,NULL,'not_specified',NULL,3900,'Utrecht',NULL,0,'after_confirmation','2026-02-27 14:10:11','Fysiotrainer certificaat',10,NULL,'NL, EN, DE',60,15,1,1,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(4,6,'Hyrox en functionele training met focus op prestaties.','Hyrox & Functioneel',6800,'https://images.unsplash.com/photo-1566753323558-f4e0952af115?w=500&q=80',NULL,NULL,'not_specified',NULL,3400,'Den Haag',NULL,0,'after_confirmation','2026-02-27 14:10:11','CrossFit L1',7,NULL,'NL, EN',60,15,1,0,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(5,7,'Postnatale en vrouwenkracht trajecten, veilig en doelgericht.','Vrouwenkracht',6400,'https://images.unsplash.com/photo-1549060279-7e168fcee0c2?w=500&q=80',NULL,NULL,'not_specified',NULL,3200,'Eindhoven',NULL,0,'after_confirmation','2026-02-27 14:10:11','Pre/Postnatal Certified',9,NULL,'NL, EN',45,15,1,1,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(6,8,'Marathon voorbereiding en blessurepreventie voor alle niveaus.','Hardlopen',5600,'https://images.unsplash.com/photo-1531891437562-4301cf35b7e4?w=500&q=80',NULL,NULL,'not_specified',NULL,2500,'Haarlem',NULL,0,'after_confirmation','2026-02-27 14:10:11','Running Coach L2',5,NULL,'NL, EN',45,15,1,0,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(7,9,'Boksen voor conditie, zelfvertrouwen en stressreductie.','Boksen',6100,'https://images.unsplash.com/photo-1599058917212-d750089bc07e?w=500&q=80',NULL,NULL,'not_specified',NULL,3000,'Tilburg',NULL,0,'after_confirmation','2026-02-27 14:10:11','Boxing Coach',6,NULL,'NL, EN, AR',60,15,1,0,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(8,10,'Calisthenics en bodyweight skills met duidelijke progressie.','Calisthenics',6000,'https://images.unsplash.com/photo-1583454110551-21f2fa2afe61?w=500&q=80',NULL,NULL,'not_specified',NULL,3000,'Nijmegen',NULL,0,'after_confirmation','2026-02-27 14:10:11','Street Workout Coach',7,NULL,'NL, EN',60,15,1,0,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(9,11,'Pilates en core-stability met focus op houding en balans.','Pilates',5800,'https://images.unsplash.com/photo-1518611012118-696072aa579a?w=500&q=80',NULL,NULL,'not_specified',NULL,2800,'Leiden',NULL,0,'after_confirmation','2026-02-27 14:10:11','Pilates Mat Instructor',8,NULL,'NL, EN, FR',45,15,1,1,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(10,12,'Senior fitness en leefstijlcoaching met rustige opbouw.','Senior Fitness',5400,'https://images.unsplash.com/photo-1552674605-db6ffd4facb5?w=500&q=80',NULL,NULL,'not_specified',NULL,2500,'Breda',NULL,0,'after_confirmation','2026-02-27 14:10:11','Senior Fit Coach',12,NULL,'NL',45,15,1,0,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(17,27,'Resultaatgerichte personal trainer voor kracht, conditie en leefstijl.','Kracht & Leefstijl',6700,'https://images.unsplash.com/photo-1549476464-37392f717541?w=500&q=80',NULL,NULL,'not_specified',NULL,3200,'Amsterdam',NULL,0,'after_confirmation','2026-02-27 14:10:11','NASM CPT, Fitvak A',9,NULL,'NL, EN',60,15,1,1,NULL,NULL,NULL,'2026-02-27 14:10:11','2026-02-27 14:10:11'),(18,47,'Kracht- en conditietrainer voor beginner en gevorderd.','Krachttraining, Conditie',6500,NULL,NULL,NULL,'not_specified',NULL,NULL,'Rotterdam',NULL,0,'after_confirmation','2026-02-28 00:55:45',NULL,NULL,NULL,NULL,NULL,15,1,0,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 01:16:28'),(19,48,'Focus op mobiliteit, core en blessurepreventie.','Mobiliteit, Core',7000,NULL,NULL,NULL,'not_specified',NULL,NULL,'Den Haag',NULL,0,'after_confirmation','2026-02-28 00:55:45',NULL,NULL,NULL,NULL,NULL,15,1,0,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(20,49,'High intensity coaching en vetverlies trajecten.','HIIT, Vetverlies',7500,NULL,NULL,NULL,'not_specified',NULL,NULL,'Utrecht',NULL,0,'after_confirmation','2026-02-28 00:55:45',NULL,NULL,NULL,NULL,NULL,15,1,0,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(21,56,'Tijdelijk niet inzetbaar (edge-case).','Hersteltraining',6200,NULL,NULL,NULL,'not_specified',NULL,NULL,'Eindhoven',NULL,0,'after_confirmation',NULL,NULL,NULL,NULL,NULL,NULL,15,0,0,NULL,NULL,NULL,'2026-02-28 00:57:19','2026-02-28 00:57:19');
/*!40000 ALTER TABLE `gymies_trainer_profiles` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_trainer_session_pricing`
--

DROP TABLE IF EXISTS `gymies_trainer_session_pricing`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_trainer_session_pricing` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_user_id` bigint unsigned NOT NULL,
  `location_id` bigint unsigned DEFAULT NULL,
  `session_type` enum('one_on_one','duo','group') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'one_on_one',
  `duration_minutes` int unsigned NOT NULL DEFAULT '60',
  `price_cents` int unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_trainer_session_pricing_trainer` (`trainer_user_id`),
  KEY `gymies_trainer_session_pricing_location_fk` (`location_id`),
  CONSTRAINT `gymies_trainer_session_pricing_location_fk` FOREIGN KEY (`location_id`) REFERENCES `gymies_trainer_locations` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_trainer_session_pricing_user_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_trainer_session_pricing`
--

LOCK TABLES `gymies_trainer_session_pricing` WRITE;
/*!40000 ALTER TABLE `gymies_trainer_session_pricing` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_trainer_session_pricing` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_trainer_specialties`
--

DROP TABLE IF EXISTS `gymies_trainer_specialties`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_trainer_specialties` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `trainer_profile_id` bigint unsigned NOT NULL,
  `specialty_id` int unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_trainer_specialties_unique` (`trainer_profile_id`,`specialty_id`),
  KEY `gymies_trainer_specialties_specialty_fk` (`specialty_id`),
  CONSTRAINT `gymies_trainer_specialties_profile_fk` FOREIGN KEY (`trainer_profile_id`) REFERENCES `gymies_trainer_profiles` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_trainer_specialties_specialty_fk` FOREIGN KEY (`specialty_id`) REFERENCES `gymies_specialties` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_trainer_specialties`
--

LOCK TABLES `gymies_trainer_specialties` WRITE;
/*!40000 ALTER TABLE `gymies_trainer_specialties` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_trainer_specialties` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_user_admin_roles`
--

DROP TABLE IF EXISTS `gymies_user_admin_roles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_user_admin_roles` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `role_id` bigint unsigned NOT NULL,
  `status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'active',
  `assigned_by_user_id` bigint unsigned DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_user_admin_roles_user_role_unique` (`user_id`,`role_id`),
  KEY `gymies_user_admin_roles_user_idx` (`user_id`),
  KEY `gymies_user_admin_roles_role_idx` (`role_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_user_admin_roles`
--

LOCK TABLES `gymies_user_admin_roles` WRITE;
/*!40000 ALTER TABLE `gymies_user_admin_roles` DISABLE KEYS */;
INSERT INTO `gymies_user_admin_roles` VALUES (1,58,1,'active',58,'2026-02-28 04:03:39','2026-02-28 04:03:39');
/*!40000 ALTER TABLE `gymies_user_admin_roles` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_user_consents`
--

DROP TABLE IF EXISTS `gymies_user_consents`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_user_consents` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `consent_type` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'terms, privacy, marketing',
  `accepted_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ip_address` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_user_consents_user` (`user_id`),
  KEY `gymies_user_consents_type` (`consent_type`),
  CONSTRAINT `gymies_user_consents_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_user_consents`
--

LOCK TABLES `gymies_user_consents` WRITE;
/*!40000 ALTER TABLE `gymies_user_consents` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_user_consents` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_user_direct_debit_mandates`
--

DROP TABLE IF EXISTS `gymies_user_direct_debit_mandates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_user_direct_debit_mandates` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `provider` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Mollie/Stripe',
  `mandate_id` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('active','revoked','failed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'active',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_user_direct_debit_mandates_unique` (`provider`,`mandate_id`),
  KEY `gymies_user_direct_debit_mandates_user_fk` (`user_id`),
  CONSTRAINT `gymies_user_direct_debit_mandates_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_user_direct_debit_mandates`
--

LOCK TABLES `gymies_user_direct_debit_mandates` WRITE;
/*!40000 ALTER TABLE `gymies_user_direct_debit_mandates` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_user_direct_debit_mandates` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_user_legal_acceptances`
--

DROP TABLE IF EXISTS `gymies_user_legal_acceptances`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_user_legal_acceptances` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `legal_document_id` bigint unsigned NOT NULL,
  `accepted_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ip_address` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_user_legal_acceptances_unique` (`user_id`,`legal_document_id`),
  KEY `gymies_user_legal_acceptances_doc_fk` (`legal_document_id`),
  CONSTRAINT `gymies_user_legal_acceptances_doc_fk` FOREIGN KEY (`legal_document_id`) REFERENCES `gymies_legal_documents` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_user_legal_acceptances_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_user_legal_acceptances`
--

LOCK TABLES `gymies_user_legal_acceptances` WRITE;
/*!40000 ALTER TABLE `gymies_user_legal_acceptances` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_user_legal_acceptances` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_user_wallets`
--

DROP TABLE IF EXISTS `gymies_user_wallets`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_user_wallets` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `balance_cents` int NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_user_wallets_user_unique` (`user_id`),
  CONSTRAINT `gymies_user_wallets_user_fk` FOREIGN KEY (`user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_user_wallets`
--

LOCK TABLES `gymies_user_wallets` WRITE;
/*!40000 ALTER TABLE `gymies_user_wallets` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_user_wallets` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_users`
--

DROP TABLE IF EXISTS `gymies_users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password_hash` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `role` enum('klant','trainer') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'klant',
  `display_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `first_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Voornaam (facturatie, formele mails)',
  `last_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Achternaam',
  `phone` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Telefoonnummer voor contact',
  `email_verified_at` timestamp NULL DEFAULT NULL,
  `phone_verified_at` timestamp NULL DEFAULT NULL,
  `date_of_birth` date DEFAULT NULL COMMENT 'Optioneel, bijv. voor 18+ of doelgroep',
  `preferred_language` varchar(10) COLLATE utf8mb4_unicode_ci DEFAULT 'nl' COMMENT 'nl, en voor e-mails en app',
  `avatar_url` varchar(512) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Profielfoto (klant en trainer)',
  `is_admin` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Platform-admin',
  `is_suspended` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Gebruiker (tijdelijk) geblokkeerd',
  `suspended_reason` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `suspended_at` timestamp NULL DEFAULT NULL,
  `trainer_approved_at` timestamp NULL DEFAULT NULL COMMENT 'Trainer pas live na goedkeuring',
  `business_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Zakelijke klant/facturatie',
  `vat_number` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'BTW-nummer',
  `coc_number` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'KvK-nummer',
  `parent_guardian_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Voor minderjarigen',
  `parent_guardian_email` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Voor minderjarigen',
  `parent_consent_at` timestamp NULL DEFAULT NULL,
  `accessibility_needs` text COLLATE utf8mb4_unicode_ci COMMENT 'Bijv. rolstoeltoegankelijkheid',
  `address_line1` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Straat en huisnummer',
  `postcode` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Postcode',
  `city` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Plaats',
  `country` varchar(2) COLLATE utf8mb4_unicode_ci DEFAULT 'NL' COMMENT 'Landcode ISO 2 (NL, BE, …)',
  `latitude` decimal(10,7) DEFAULT NULL COMMENT 'Voor afstand/radius zoekfilter',
  `longitude` decimal(10,7) DEFAULT NULL COMMENT 'Voor afstand/radius zoekfilter',
  `data_export_requested_at` timestamp NULL DEFAULT NULL COMMENT 'AVG data-export aanvraag',
  `data_export_completed_at` timestamp NULL DEFAULT NULL COMMENT 'AVG data-export afgerond',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gymies_users_email_unique` (`email`),
  KEY `gymies_users_role` (`role`),
  KEY `gymies_users_postcode` (`postcode`),
  KEY `gymies_users_city` (`city`)
) ENGINE=InnoDB AUTO_INCREMENT=59 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_users`
--

LOCK TABLES `gymies_users` WRITE;
/*!40000 ALTER TABLE `gymies_users` DISABLE KEYS */;
INSERT INTO `gymies_users` VALUES (1,'apitest_1772159597@example.com','$2y$12$urZpEERJPAHeeDvAo1hkkOlXJsUDg/ggUtJamu6mgIwHGPfJ6M/Hq','klant','apitest_1772159597',NULL,NULL,NULL,NULL,NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 02:33:20','2026-02-27 02:33:20'),(2,'zaldion75@gmail.com','$2y$12$poNUC5RxTRP6d7A2tsUUWO5Y8dgiqhSQh9T4pjbw8FsZiEoTYmSZW','klant','Moo',NULL,NULL,NULL,NULL,NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 03:05:37','2026-02-27 04:43:22'),(3,'trainer.anne@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','trainer','Anne de Vries',NULL,NULL,'+31611111111','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(4,'trainer.rayan@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','trainer','Rayan El Amrani',NULL,NULL,'+31622222222','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(5,'trainer.sophie@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','trainer','Sophie van Dam',NULL,NULL,'+31633333333','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(6,'trainer.daan@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','trainer','Daan Peters',NULL,NULL,'+31644444444','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(7,'trainer.ines@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','trainer','Ines Bakker',NULL,NULL,'+31655555555','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(8,'trainer.jasper@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','trainer','Jasper Boer',NULL,NULL,'+31666666666','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(9,'trainer.noura@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','trainer','Noura Kabbaj',NULL,NULL,'+31677777777','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(10,'trainer.milan@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','trainer','Milan Vos',NULL,NULL,'+31688888888','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(11,'trainer.fatima@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','trainer','Fatima Idrissi',NULL,NULL,'+31699999999','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(12,'trainer.thomas@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','trainer','Thomas Meijer',NULL,NULL,'+31610101010','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 03:15:27','2026-02-27 14:10:11'),(23,'klant.lisa@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','klant','Lisa Jansen',NULL,NULL,'+31620202020','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 14:10:11'),(24,'klant.noah@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','klant','Noah Smit',NULL,NULL,'+31630303030','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 14:10:11'),(25,'klant.emma@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','klant','Emma de Wit',NULL,NULL,'+31640404040','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 04:14:26','2026-02-27 14:10:11'),(26,'smoke.1772168687@example.com','$2y$12$/35lOKYvc1DhmJDxmibKzuKTavGQz9k1uhlCeKXHr.bNIz5n4A6k6','klant','Smoke Tester',NULL,NULL,NULL,NULL,NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'Rotterdam','NL',NULL,NULL,NULL,NULL,'2026-02-27 05:04:48','2026-02-27 05:04:48'),(27,'jamai1210@live.nl','$2y$12$Wq.QPcqRPJyfekAoY3.aQuBQFbV5CjUJwnqIL9O3lrCVY3J1tkOZq','trainer','Jamai El Madi',NULL,NULL,'+31612121212','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 13:59:15','2026-02-27 14:10:11'),(39,'klant.femke@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','klant','Femke Vermeer',NULL,NULL,'+31614141414','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 14:10:11','2026-02-27 14:10:11'),(40,'klant.luca@example.com','$2y$10$wHn6Q85ikA6uXODt2xQ5Re9jK2yY6wHfF4fQ3f5Gm0Qttf5o2iV0C','klant','Luca de Jong',NULL,NULL,'+31615151515','2026-02-27 14:10:11','2026-02-27 14:10:11',NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 14:10:11','2026-02-27 14:10:11'),(44,'amstelbasic@gmail.com','$2y$12$eOG5de3tRfLlCWJXJG2g0ezhGJX117W7C2RtwHeqoISqPdVuwg1HK','trainer','adam',NULL,NULL,NULL,NULL,NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-27 22:38:07','2026-02-27 22:38:07'),(45,'elotmanigym@trainmate.app','$2y$12$ij5HYJ.GReGqOJbEzIjRz.E0o6nFTr9Cxw4NdiTMkHdekQcXzo6bK','klant','elotmanigym admin',NULL,NULL,NULL,'2026-02-28 00:21:43',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:21:43','2026-02-28 00:21:43'),(46,'powerhousegym@trainmate.app','$2y$12$4q6i2IT0RZ8knZlBWZ3it.Z756pOtav/Bb0fPK4wGK3FM3iVZ.p.a','klant','powerhousegym admin',NULL,NULL,NULL,'2026-02-28 00:36:57',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:36:57','2026-02-28 00:36:57'),(47,'powerhouse.trainer1@trainmate.app','$2y$12$LgW6tXoDmDyjklkp3iWVFeHSymJIBkT9WU/jv4HLPEc1reVE31wEC','trainer','Amina Powerhouse',NULL,NULL,NULL,'2026-02-28 00:55:45',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(48,'powerhouse.trainer2@trainmate.app','$2y$12$LgW6tXoDmDyjklkp3iWVFeHSymJIBkT9WU/jv4HLPEc1reVE31wEC','trainer','Youssef Mobility',NULL,NULL,NULL,'2026-02-28 00:55:45',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(49,'powerhouse.trainer3@trainmate.app','$2y$12$LgW6tXoDmDyjklkp3iWVFeHSymJIBkT9WU/jv4HLPEc1reVE31wEC','trainer','Sofia HIIT',NULL,NULL,NULL,'2026-02-28 00:55:45',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(50,'powerhouse.manager@trainmate.app','$2y$12$LgW6tXoDmDyjklkp3iWVFeHSymJIBkT9WU/jv4HLPEc1reVE31wEC','klant','Powerhouse Manager',NULL,NULL,NULL,'2026-02-28 00:55:45',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(51,'powerhouse.viewer@trainmate.app','$2y$12$LgW6tXoDmDyjklkp3iWVFeHSymJIBkT9WU/jv4HLPEc1reVE31wEC','klant','Powerhouse Viewer',NULL,NULL,NULL,'2026-02-28 00:55:45',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(52,'powerhouse.client1@trainmate.app','$2y$12$LgW6tXoDmDyjklkp3iWVFeHSymJIBkT9WU/jv4HLPEc1reVE31wEC','klant','Nora Client',NULL,NULL,NULL,'2026-02-28 00:55:45',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(53,'powerhouse.client2@trainmate.app','$2y$12$LgW6tXoDmDyjklkp3iWVFeHSymJIBkT9WU/jv4HLPEc1reVE31wEC','klant','Milan Client',NULL,NULL,NULL,'2026-02-28 00:55:45',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(54,'powerhouse.client3@trainmate.app','$2y$12$LgW6tXoDmDyjklkp3iWVFeHSymJIBkT9WU/jv4HLPEc1reVE31wEC','klant','Daan Client',NULL,NULL,NULL,'2026-02-28 00:55:45',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(55,'powerhouse.client4@trainmate.app','$2y$12$LgW6tXoDmDyjklkp3iWVFeHSymJIBkT9WU/jv4HLPEc1reVE31wEC','klant','Lina Client',NULL,NULL,NULL,'2026-02-28 00:55:45',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:55:45','2026-02-28 00:55:45'),(56,'powerhouse.inactive.trainer@trainmate.app','$2y$12$KiiCGzTAsKf.3jFgj5lG4e6hu.gQe8OJ4ubN0269LkMrs4loHFEue','trainer','Ruben Inactive',NULL,NULL,NULL,'2026-02-28 00:57:19',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:57:19','2026-02-28 00:57:19'),(57,'powerhouse.noshow.client@trainmate.app','$2y$12$KiiCGzTAsKf.3jFgj5lG4e6hu.gQe8OJ4ubN0269LkMrs4loHFEue','klant','NoShow Client',NULL,NULL,NULL,'2026-02-28 00:57:19',NULL,NULL,'nl',NULL,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 00:57:19','2026-02-28 00:57:19'),(58,'admin@trainmate.app','$2y$12$BDZy8eCiBPgWimzCUPMroeZacrVhGmIX2Ljf2xHhVM61C02FG/le6','klant','TrainMaat Admin',NULL,NULL,NULL,NULL,NULL,NULL,'nl',NULL,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NL',NULL,NULL,NULL,NULL,'2026-02-28 04:03:39','2026-02-28 04:07:29');
/*!40000 ALTER TABLE `gymies_users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_vat_rates`
--

DROP TABLE IF EXISTS `gymies_vat_rates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_vat_rates` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `country_code` varchar(2) COLLATE utf8mb4_unicode_ci NOT NULL,
  `rate_percent` decimal(5,2) NOT NULL,
  `valid_from` date NOT NULL,
  `valid_until` date DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_vat_rates_country` (`country_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_vat_rates`
--

LOCK TABLES `gymies_vat_rates` WRITE;
/*!40000 ALTER TABLE `gymies_vat_rates` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_vat_rates` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_waitlist`
--

DROP TABLE IF EXISTS `gymies_waitlist`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_waitlist` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `client_user_id` bigint unsigned NOT NULL,
  `trainer_user_id` bigint unsigned NOT NULL,
  `requested_for_scheduled_at` datetime DEFAULT NULL COMMENT 'Wachtlijst op specifiek tijdslot',
  `availability_slot_id` bigint unsigned DEFAULT NULL,
  `preferred_date_from` date DEFAULT NULL,
  `preferred_date_to` date DEFAULT NULL,
  `notes` text COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_waitlist_client` (`client_user_id`),
  KEY `gymies_waitlist_trainer` (`trainer_user_id`),
  KEY `gymies_waitlist_slot` (`availability_slot_id`),
  CONSTRAINT `gymies_waitlist_client_fk` FOREIGN KEY (`client_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gymies_waitlist_slot_fk` FOREIGN KEY (`availability_slot_id`) REFERENCES `gymies_availability_slots` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_waitlist_trainer_fk` FOREIGN KEY (`trainer_user_id`) REFERENCES `gymies_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_waitlist`
--

LOCK TABLES `gymies_waitlist` WRITE;
/*!40000 ALTER TABLE `gymies_waitlist` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_waitlist` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gymies_wallet_transactions`
--

DROP TABLE IF EXISTS `gymies_wallet_transactions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gymies_wallet_transactions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `wallet_id` bigint unsigned NOT NULL,
  `booking_id` bigint unsigned DEFAULT NULL,
  `tx_type` enum('topup','debit','refund','adjustment') COLLATE utf8mb4_unicode_ci NOT NULL,
  `amount_cents` int NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gymies_wallet_transactions_wallet` (`wallet_id`),
  KEY `gymies_wallet_transactions_booking_fk` (`booking_id`),
  CONSTRAINT `gymies_wallet_transactions_booking_fk` FOREIGN KEY (`booking_id`) REFERENCES `gymies_bookings` (`id`) ON DELETE SET NULL,
  CONSTRAINT `gymies_wallet_transactions_wallet_fk` FOREIGN KEY (`wallet_id`) REFERENCES `gymies_user_wallets` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gymies_wallet_transactions`
--

LOCK TABLES `gymies_wallet_transactions` WRITE;
/*!40000 ALTER TABLE `gymies_wallet_transactions` DISABLE KEYS */;
/*!40000 ALTER TABLE `gymies_wallet_transactions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `cache`
--

DROP TABLE IF EXISTS `cache`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `cache` (
  `key` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `value` mediumtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `expiration` int NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `cache`
--

LOCK TABLES `cache` WRITE;
/*!40000 ALTER TABLE `cache` DISABLE KEYS */;
/*!40000 ALTER TABLE `cache` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `cache_locks`
--

DROP TABLE IF EXISTS `cache_locks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `cache_locks` (
  `key` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `owner` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `expiration` int NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `cache_locks`
--

LOCK TABLES `cache_locks` WRITE;
/*!40000 ALTER TABLE `cache_locks` DISABLE KEYS */;
/*!40000 ALTER TABLE `cache_locks` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `contacts`
--

DROP TABLE IF EXISTS `contacts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `contacts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `service` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `message` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `ip_address` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_agent` text COLLATE utf8mb4_unicode_ci,
  `is_read` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `contacts`
--

LOCK TABLES `contacts` WRITE;
/*!40000 ALTER TABLE `contacts` DISABLE KEYS */;
/*!40000 ALTER TABLE `contacts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Temporary view structure for view `customer_accounts`
--

DROP TABLE IF EXISTS `customer_accounts`;
/*!50001 DROP VIEW IF EXISTS `customer_accounts`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `customer_accounts` AS SELECT 
 1 AS `id`,
 1 AS `email`,
 1 AS `password_hash`,
 1 AS `customer_type`,
 1 AS `company_name`,
 1 AS `contact_name`,
 1 AS `phone_number`,
 1 AS `address`,
 1 AS `profile_image_data`,
 1 AS `is_active`,
 1 AS `created_at`,
 1 AS `updated_at`,
 1 AS `last_login_at`*/;
SET character_set_client = @saved_cs_client;

--
-- Temporary view structure for view `dispatcher_sessions`
--

DROP TABLE IF EXISTS `dispatcher_sessions`;
/*!50001 DROP VIEW IF EXISTS `dispatcher_sessions`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `dispatcher_sessions` AS SELECT 
 1 AS `id`,
 1 AS `email`,
 1 AS `token`,
 1 AS `pin_code`,
 1 AS `expiresAt`,
 1 AS `createdAt`*/;
SET character_set_client = @saved_cs_client;

--
-- Temporary view structure for view `driver_locations`
--

DROP TABLE IF EXISTS `driver_locations`;
/*!50001 DROP VIEW IF EXISTS `driver_locations`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `driver_locations` AS SELECT 
 1 AS `id`,
 1 AS `driverEmail`,
 1 AS `latitude`,
 1 AS `longitude`,
 1 AS `updatedAt`*/;
SET character_set_client = @saved_cs_client;

--
-- Temporary view structure for view `drivers`
--

DROP TABLE IF EXISTS `drivers`;
/*!50001 DROP VIEW IF EXISTS `drivers`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `drivers` AS SELECT 
 1 AS `id`,
 1 AS `email`,
 1 AS `passwordHash`,
 1 AS `driverName`,
 1 AS `phoneNumber`,
 1 AS `vehicleType`,
 1 AS `driverCode`,
 1 AS `isActive`,
 1 AS `averageRating`,
 1 AS `createdAt`,
 1 AS `lastLoginAt`,
 1 AS `lastOnlineUpdate`,
 1 AS `verificationStatus`*/;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `failed_jobs`
--

DROP TABLE IF EXISTS `failed_jobs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `failed_jobs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `uuid` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `connection` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `queue` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `payload` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `exception` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `failed_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `failed_jobs_uuid_unique` (`uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `failed_jobs`
--

LOCK TABLES `failed_jobs` WRITE;
/*!40000 ALTER TABLE `failed_jobs` DISABLE KEYS */;
/*!40000 ALTER TABLE `failed_jobs` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gamersunited_cart_items`
--

DROP TABLE IF EXISTS `gamersunited_cart_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gamersunited_cart_items` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `session_id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` bigint unsigned DEFAULT NULL,
  `product_id` bigint unsigned NOT NULL,
  `quantity` int NOT NULL DEFAULT '1',
  `price` decimal(10,2) NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gamersunited_cart_items_session_id_product_id_unique` (`session_id`,`product_id`),
  UNIQUE KEY `gamersunited_cart_items_user_id_product_id_unique` (`user_id`,`product_id`),
  KEY `gamersunited_cart_items_product_id_foreign` (`product_id`),
  KEY `gamersunited_cart_items_session_id_index` (`session_id`),
  CONSTRAINT `gamersunited_cart_items_product_id_foreign` FOREIGN KEY (`product_id`) REFERENCES `gamersunited_products` (`id`) ON DELETE CASCADE,
  CONSTRAINT `gamersunited_cart_items_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gamersunited_cart_items`
--

LOCK TABLES `gamersunited_cart_items` WRITE;
/*!40000 ALTER TABLE `gamersunited_cart_items` DISABLE KEYS */;
/*!40000 ALTER TABLE `gamersunited_cart_items` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gamersunited_categories`
--

DROP TABLE IF EXISTS `gamersunited_categories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gamersunited_categories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `slug` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name_nl` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name_en` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description_nl` text COLLATE utf8mb4_unicode_ci,
  `description_en` text COLLATE utf8mb4_unicode_ci,
  `image` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `sort_order` int NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `gamersunited_categories_slug_unique` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gamersunited_categories`
--

LOCK TABLES `gamersunited_categories` WRITE;
/*!40000 ALTER TABLE `gamersunited_categories` DISABLE KEYS */;
/*!40000 ALTER TABLE `gamersunited_categories` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gamersunited_products`
--

DROP TABLE IF EXISTS `gamersunited_products`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gamersunited_products` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `category_id` bigint unsigned NOT NULL,
  `brand` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `name_nl` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name_en` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description_nl` text COLLATE utf8mb4_unicode_ci,
  `description_en` text COLLATE utf8mb4_unicode_ci,
  `colors` json DEFAULT NULL,
  `short_name_nl` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `short_name_en` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `price` decimal(10,2) NOT NULL,
  `sale_price` decimal(10,2) DEFAULT NULL,
  `is_on_sale` tinyint(1) NOT NULL DEFAULT '0',
  `image` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `stock` int NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `sort_order` int NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `gamersunited_products_category_id_foreign` (`category_id`),
  CONSTRAINT `gamersunited_products_category_id_foreign` FOREIGN KEY (`category_id`) REFERENCES `gamersunited_categories` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gamersunited_products`
--

LOCK TABLES `gamersunited_products` WRITE;
/*!40000 ALTER TABLE `gamersunited_products` DISABLE KEYS */;
/*!40000 ALTER TABLE `gamersunited_products` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_audit_logs`
--

DROP TABLE IF EXISTS `islime_audit_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_audit_logs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `model_type` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Bijv. "App\\Models\\iSlime\\IslimeCompany"',
  `model_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'ID van het model (UUID voor iSlime models)',
  `company_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `action` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'created, updated, deleted, status_changed, etc.',
  `user_id` bigint unsigned DEFAULT NULL,
  `user_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Voor als user later verwijderd wordt',
  `old_values` json DEFAULT NULL COMMENT 'Oude waarden',
  `new_values` json DEFAULT NULL COMMENT 'Nieuwe waarden',
  `description` text COLLATE utf8mb4_unicode_ci COMMENT 'Beschrijving van de actie',
  `ip_address` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_agent` text COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `islime_audit_logs_model_type_model_id_index` (`model_type`,`model_id`),
  KEY `islime_audit_logs_action_index` (`action`),
  KEY `islime_audit_logs_created_at_index` (`created_at`),
  KEY `islime_audit_logs_user_id_index` (`user_id`),
  KEY `islime_audit_logs_company_id_index` (`company_id`),
  CONSTRAINT `islime_audit_logs_company_id_foreign` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE,
  CONSTRAINT `islime_audit_logs_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_audit_logs`
--

LOCK TABLES `islime_audit_logs` WRITE;
/*!40000 ALTER TABLE `islime_audit_logs` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_audit_logs` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_bank_accounts`
--

DROP TABLE IF EXISTS `islime_bank_accounts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_bank_accounts` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `account_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `iban` varchar(34) COLLATE utf8mb4_unicode_ci NOT NULL,
  `balance` decimal(15,2) DEFAULT '0.00',
  `is_active` tinyint(1) DEFAULT '1',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  CONSTRAINT `islime_bank_accounts_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_bank_accounts`
--

LOCK TABLES `islime_bank_accounts` WRITE;
/*!40000 ALTER TABLE `islime_bank_accounts` DISABLE KEYS */;
INSERT INTO `islime_bank_accounts` VALUES ('019bb511-7cad-72b5-952d-a349f3acd1c4','019bb511-7a22-7271-88f6-aa7d7c5178fe','Zakelijke Rekening','Zakelijke Rekening','NL12ABCD0123456789',0.00,1,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL);
/*!40000 ALTER TABLE `islime_bank_accounts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_bank_transactions`
--

DROP TABLE IF EXISTS `islime_bank_transactions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_bank_transactions` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `bank_account_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `transaction_id` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `transaction_date` date NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `counterparty_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `counterparty_iban` varchar(34) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `reference` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `transaction_type` enum('debit','credit','transfer') COLLATE utf8mb4_unicode_ci DEFAULT 'debit',
  `status` enum('pending','processed','matched','ignored') COLLATE utf8mb4_unicode_ci DEFAULT 'pending',
  `is_reconciled` tinyint(1) DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `bank_account_id` (`bank_account_id`),
  CONSTRAINT `islime_bank_transactions_ibfk_1` FOREIGN KEY (`bank_account_id`) REFERENCES `islime_bank_accounts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_bank_transactions`
--

LOCK TABLES `islime_bank_transactions` WRITE;
/*!40000 ALTER TABLE `islime_bank_transactions` DISABLE KEYS */;
INSERT INTO `islime_bank_transactions` VALUES ('019bb511-7d06-73c0-ac7e-fc04d95b9ef6','019bb511-7cad-72b5-952d-a349f3acd1c4','TX-1768269380-0','2026-01-08',-29.99,'Microsoft Office',NULL,'Microsoft 365 subscription','TEST-9345','debit','pending',0,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7d08-7065-a255-e4179331a9c5','019bb511-7cad-72b5-952d-a349f3acd1c4','TX-1768269380-1','2026-01-03',-150.00,'Google Ads',NULL,'Google Advertising','TEST-6841','debit','pending',0,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7d0a-70a7-8253-ae92822ec1db','019bb511-7cad-72b5-952d-a349f3acd1c4','TX-1768269380-2','2026-01-01',-45.50,'Shell',NULL,'Tankstation betaling','TEST-3654','debit','pending',0,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7d0c-7082-9736-8d0b14db0618','019bb511-7cad-72b5-952d-a349f3acd1c4','TX-1768269380-3','2025-12-29',-89.00,'Staples',NULL,'Kantoorartikelen','TEST-5480','debit','pending',0,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7d0e-7264-b7c6-6d5a21a047ba','019bb511-7cad-72b5-952d-a349f3acd1c4','TX-1768269380-4','2026-01-10',1210.00,'Acme Corporation',NULL,'Betaling factuur TEST-2026-0001','TEST-2861','debit','pending',1,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL);
/*!40000 ALTER TABLE `islime_bank_transactions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_categories`
--

DROP TABLE IF EXISTS `islime_categories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_categories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `color` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '#4682B4',
  `type` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'expense',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `sort_order` int NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_categories`
--

LOCK TABLES `islime_categories` WRITE;
/*!40000 ALTER TABLE `islime_categories` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_categories` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_companies`
--

DROP TABLE IF EXISTS `islime_companies`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_companies` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` bigint unsigned DEFAULT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `kvk_number` varchar(8) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `legal_form` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `vat_number` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `country` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT 'Nederland',
  `currency` varchar(3) COLLATE utf8mb4_unicode_ci DEFAULT 'EUR',
  `vat_obligated` tinyint(1) DEFAULT '1',
  `vat_frequency` enum('month','quarter','year') COLLATE utf8mb4_unicode_ci DEFAULT 'quarter',
  `kor_applicable` tinyint(1) DEFAULT '0',
  `icp_applicable` tinyint(1) DEFAULT '0',
  `vat_settings_confirmed_at` timestamp NULL DEFAULT NULL,
  `active_fiscal_year_id` bigint unsigned DEFAULT NULL,
  `wizard_completed` tinyint(1) DEFAULT '0',
  `wizard_completed_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `islime_companies_user_id_foreign` (`user_id`),
  KEY `islime_companies_active_fiscal_year_id_index` (`active_fiscal_year_id`),
  CONSTRAINT `islime_companies_active_fiscal_year_id_foreign` FOREIGN KEY (`active_fiscal_year_id`) REFERENCES `islime_fiscal_years` (`id`) ON DELETE SET NULL,
  CONSTRAINT `islime_companies_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_companies`
--

LOCK TABLES `islime_companies` WRITE;
/*!40000 ALTER TABLE `islime_companies` DISABLE KEYS */;
INSERT INTO `islime_companies` VALUES ('019bb511-7a22-7271-88f6-aa7d7c5178fe',NULL,'Test BV','12345678',NULL,'NL123456789B01','Nederland','EUR',1,'quarter',0,0,NULL,3,1,'2026-01-13 01:56:20',NULL,NULL);
/*!40000 ALTER TABLE `islime_companies` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_company_users`
--

DROP TABLE IF EXISTS `islime_company_users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_company_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `role` enum('owner','accountant','viewer') COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `user_id` (`user_id`),
  KEY `company_id` (`company_id`),
  CONSTRAINT `islime_company_users_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `islime_company_users_ibfk_2` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_company_users`
--

LOCK TABLES `islime_company_users` WRITE;
/*!40000 ALTER TABLE `islime_company_users` DISABLE KEYS */;
INSERT INTO `islime_company_users` VALUES (1,1,'019bb511-7a22-7271-88f6-aa7d7c5178fe','owner','2026-01-13 01:56:20','2026-01-13 01:56:20'),(2,2,'019bb511-7a22-7271-88f6-aa7d7c5178fe','accountant','2026-01-13 01:56:20','2026-01-13 01:56:20'),(3,3,'019bb511-7a22-7271-88f6-aa7d7c5178fe','viewer','2026-01-13 01:56:20','2026-01-13 01:56:20');
/*!40000 ALTER TABLE `islime_company_users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_customers`
--

DROP TABLE IF EXISTS `islime_customers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_customers` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `address` text COLLATE utf8mb4_unicode_ci,
  `vat_number` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  CONSTRAINT `islime_customers_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_customers`
--

LOCK TABLES `islime_customers` WRITE;
/*!40000 ALTER TABLE `islime_customers` DISABLE KEYS */;
INSERT INTO `islime_customers` VALUES ('019bb511-7cb0-7179-81d2-24a6f9ad3132','019bb511-7a22-7271-88f6-aa7d7c5178fe','Acme Corporation','info@acme.com',NULL,NULL,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cb2-70dd-be39-ee0cc7af5724','019bb511-7a22-7271-88f6-aa7d7c5178fe','TechStart BV','contact@techstart.nl',NULL,NULL,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cb4-7181-8891-6fdb6ed77dff','019bb511-7a22-7271-88f6-aa7d7c5178fe','Design Studio','hello@designstudio.nl',NULL,NULL,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL);
/*!40000 ALTER TABLE `islime_customers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_documents`
--

DROP TABLE IF EXISTS `islime_documents`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_documents` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `uploaded_by` bigint unsigned DEFAULT NULL,
  `filename` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `stored_filename` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `file_path` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `mime_type` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `file_size` bigint unsigned DEFAULT NULL,
  `document_type` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT 'receipt',
  `title` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `tags` text COLLATE utf8mb4_unicode_ci,
  `ocr_amount` decimal(10,2) DEFAULT NULL,
  `ocr_date` date DEFAULT NULL,
  `ocr_text` text COLLATE utf8mb4_unicode_ci,
  `ocr_processed` tinyint(1) DEFAULT '0',
  `ocr_processed_at` timestamp NULL DEFAULT NULL,
  `customer_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `supplier_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `purchase_invoice_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `invoice_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `project_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT 'uploaded',
  `is_archived` tinyint(1) DEFAULT '0',
  `document_date` date DEFAULT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `type` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `path` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL,
  `size` bigint DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  KEY `islime_documents_uploaded_by_index` (`uploaded_by`),
  KEY `islime_documents_document_type_index` (`document_type`),
  KEY `islime_documents_is_archived_index` (`is_archived`),
  CONSTRAINT `islime_documents_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE,
  CONSTRAINT `islime_documents_uploaded_by_foreign` FOREIGN KEY (`uploaded_by`) REFERENCES `users` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_documents`
--

LOCK TABLES `islime_documents` WRITE;
/*!40000 ALTER TABLE `islime_documents` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_documents` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_expenses`
--

DROP TABLE IF EXISTS `islime_expenses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_expenses` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `category_id` bigint unsigned DEFAULT NULL,
  `customer_id` bigint unsigned DEFAULT NULL,
  `description` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `expense_date` date NOT NULL,
  `payment_method` enum('cash','bank_transfer','credit_card','other') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'bank_transfer',
  `receipt_file` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `vendor` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `is_tax_deductible` tinyint(1) NOT NULL DEFAULT '1',
  `tax_amount` decimal(10,2) NOT NULL DEFAULT '0.00',
  `notes` text COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `islime_expenses_category_id_foreign` (`category_id`),
  CONSTRAINT `islime_expenses_category_id_foreign` FOREIGN KEY (`category_id`) REFERENCES `islime_categories` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_expenses`
--

LOCK TABLES `islime_expenses` WRITE;
/*!40000 ALTER TABLE `islime_expenses` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_expenses` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_fiscal_years`
--

DROP TABLE IF EXISTS `islime_fiscal_years`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_fiscal_years` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `year` int NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `is_active` tinyint(1) DEFAULT '1',
  `is_locked` tinyint(1) DEFAULT '0',
  `locked_at` timestamp NULL DEFAULT NULL,
  `locked_by` bigint unsigned DEFAULT NULL,
  `lock_reason` text COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `islime_fiscal_years_year_company_unique` (`year`,`company_id`),
  KEY `islime_fiscal_years_is_active_index` (`is_active`),
  KEY `islime_fiscal_years_is_locked_index` (`is_locked`),
  KEY `islime_fiscal_years_company_id_index` (`company_id`),
  KEY `islime_fiscal_years_locked_by_foreign` (`locked_by`),
  CONSTRAINT `islime_fiscal_years_company_id_foreign` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE,
  CONSTRAINT `islime_fiscal_years_locked_by_foreign` FOREIGN KEY (`locked_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_fiscal_years`
--

LOCK TABLES `islime_fiscal_years` WRITE;
/*!40000 ALTER TABLE `islime_fiscal_years` DISABLE KEYS */;
INSERT INTO `islime_fiscal_years` VALUES (3,NULL,'2026',2026,'2026-01-01','2026-12-31',1,0,NULL,NULL,NULL,'2026-01-13 02:32:48','2026-01-13 02:32:48');
/*!40000 ALTER TABLE `islime_fiscal_years` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_invoice_lines`
--

DROP TABLE IF EXISTS `islime_invoice_lines`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_invoice_lines` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `invoice_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `quantity` decimal(10,2) DEFAULT '1.00',
  `unit_price` decimal(15,2) NOT NULL,
  `vat_rate` decimal(5,2) DEFAULT '21.00',
  `subtotal` decimal(15,2) DEFAULT '0.00',
  `vat_amount` decimal(15,2) DEFAULT '0.00',
  `total` decimal(15,2) NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `invoice_id` (`invoice_id`),
  CONSTRAINT `islime_invoice_lines_ibfk_1` FOREIGN KEY (`invoice_id`) REFERENCES `islime_invoices` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_invoice_lines`
--

LOCK TABLES `islime_invoice_lines` WRITE;
/*!40000 ALTER TABLE `islime_invoice_lines` DISABLE KEYS */;
INSERT INTO `islime_invoice_lines` VALUES ('019bb511-7cbc-7233-aa89-fb88eac2b3bf','019bb511-7cb6-7103-9dd2-05812ec9e84a','Webdesign diensten',8.00,75.00,21.00,0.00,0.00,726.00,NULL,NULL,NULL),('019bb511-7cbf-73dd-aa78-85996e9e8096','019bb511-7cb6-7103-9dd2-05812ec9e84a','Hosting & onderhoud',1.00,50.00,21.00,0.00,0.00,60.50,NULL,NULL,NULL),('019bb511-7cc4-715b-9496-b71baccdd4ca','019bb511-7cc2-719c-a41c-44e31e51e981','Webdesign diensten',8.00,75.00,21.00,0.00,0.00,726.00,NULL,NULL,NULL),('019bb511-7cc5-717b-9be9-87beee670cc5','019bb511-7cc2-719c-a41c-44e31e51e981','Hosting & onderhoud',1.00,50.00,21.00,0.00,0.00,60.50,NULL,NULL,NULL),('019bb511-7cca-70ae-a21c-c09a8a0033af','019bb511-7cc9-735d-bdd4-852aab9dfa18','Webdesign diensten',8.00,75.00,21.00,0.00,0.00,726.00,NULL,NULL,NULL),('019bb511-7ccc-7311-90c5-f0c95ee4a5ca','019bb511-7cc9-735d-bdd4-852aab9dfa18','Hosting & onderhoud',1.00,50.00,21.00,0.00,0.00,60.50,NULL,NULL,NULL),('019bb511-7cd0-717f-b0bd-45405249ad70','019bb511-7cce-70b7-93be-d11c4eabafb7','Webdesign diensten',8.00,75.00,21.00,0.00,0.00,726.00,NULL,NULL,NULL),('019bb511-7cd1-70f3-b4e5-17224d96e6a2','019bb511-7cce-70b7-93be-d11c4eabafb7','Hosting & onderhoud',1.00,50.00,21.00,0.00,0.00,60.50,NULL,NULL,NULL),('019bb511-7cd6-7013-a9ad-a0f50dc2445b','019bb511-7cd4-7283-afa2-05dca473390e','Webdesign diensten',8.00,75.00,21.00,0.00,0.00,726.00,NULL,NULL,NULL),('019bb511-7cd7-7155-9fe5-0d1a108c3a15','019bb511-7cd4-7283-afa2-05dca473390e','Hosting & onderhoud',1.00,50.00,21.00,0.00,0.00,60.50,NULL,NULL,NULL),('019bb511-7cdc-71ab-bf73-1523fb495530','019bb511-7cda-7333-9554-b7ffcff6bd34','Webdesign diensten',8.00,75.00,21.00,0.00,0.00,726.00,NULL,NULL,NULL),('019bb511-7cdd-70d6-8dc1-9e9f346e3d48','019bb511-7cda-7333-9554-b7ffcff6bd34','Hosting & onderhoud',1.00,50.00,21.00,0.00,0.00,60.50,NULL,NULL,NULL);
/*!40000 ALTER TABLE `islime_invoice_lines` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_invoices`
--

DROP TABLE IF EXISTS `islime_invoices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_invoices` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `customer_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `invoice_number` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `invoice_date` date NOT NULL,
  `due_date` date NOT NULL,
  `status` enum('draft','sent','paid','overdue','cancelled') COLLATE utf8mb4_unicode_ci DEFAULT 'draft',
  `subtotal` decimal(15,2) DEFAULT '0.00',
  `vat_amount` decimal(15,2) DEFAULT '0.00',
  `total` decimal(15,2) DEFAULT '0.00',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  KEY `customer_id` (`customer_id`),
  CONSTRAINT `islime_invoices_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE,
  CONSTRAINT `islime_invoices_ibfk_2` FOREIGN KEY (`customer_id`) REFERENCES `islime_customers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_invoices`
--

LOCK TABLES `islime_invoices` WRITE;
/*!40000 ALTER TABLE `islime_invoices` DISABLE KEYS */;
INSERT INTO `islime_invoices` VALUES ('019bb511-7cb6-7103-9dd2-05812ec9e84a','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cb0-7179-81d2-24a6f9ad3132','TEST-1768269380-0001','2026-01-13','2026-01-27','paid',0.00,0.00,786.50,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cc2-719c-a41c-44e31e51e981','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cb0-7179-81d2-24a6f9ad3132','TEST-1768269380-0002','2026-01-03','2026-01-17','paid',0.00,0.00,786.50,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cc9-735d-bdd4-852aab9dfa18','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cb2-70dd-be39-ee0cc7af5724','TEST-1768269380-0003','2025-12-24','2026-01-07','sent',0.00,0.00,786.50,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cce-70b7-93be-d11c4eabafb7','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cb2-70dd-be39-ee0cc7af5724','TEST-1768269380-0004','2025-12-14','2025-12-28','sent',0.00,0.00,786.50,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cd4-7283-afa2-05dca473390e','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cb4-7181-8891-6fdb6ed77dff','TEST-1768269380-0005','2025-12-04','2025-12-18','draft',0.00,0.00,786.50,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cda-7333-9554-b7ffcff6bd34','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cb4-7181-8891-6fdb6ed77dff','TEST-1768269380-0006','2025-11-24','2025-12-08','draft',0.00,0.00,786.50,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL);
/*!40000 ALTER TABLE `islime_invoices` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_ledger_accounts`
--

DROP TABLE IF EXISTS `islime_ledger_accounts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_ledger_accounts` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `code` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `type` enum('asset','liability','equity','revenue','expense') COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  CONSTRAINT `islime_ledger_accounts_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_ledger_accounts`
--

LOCK TABLES `islime_ledger_accounts` WRITE;
/*!40000 ALTER TABLE `islime_ledger_accounts` DISABLE KEYS */;
INSERT INTO `islime_ledger_accounts` VALUES ('019bb511-7c9d-7343-98fd-be24da839a7a','019bb511-7a22-7271-88f6-aa7d7c5178fe','1100','Bank','asset',NULL,NULL,NULL),('019bb511-7c9f-7157-b389-fce89853a9e2','019bb511-7a22-7271-88f6-aa7d7c5178fe','1300','Debiteuren','asset',NULL,NULL,NULL),('019bb511-7ca1-7050-9930-b0eb48e413e0','019bb511-7a22-7271-88f6-aa7d7c5178fe','1600','Crediteuren','liability',NULL,NULL,NULL),('019bb511-7ca3-72e7-b64e-1b70d5a112e6','019bb511-7a22-7271-88f6-aa7d7c5178fe','2600','BTW te betalen','liability',NULL,NULL,NULL),('019bb511-7ca5-7318-bdbd-e0415e841571','019bb511-7a22-7271-88f6-aa7d7c5178fe','8000','Omzet','revenue',NULL,NULL,NULL),('019bb511-7ca7-71f5-b3b4-e722f3ef982d','019bb511-7a22-7271-88f6-aa7d7c5178fe','4600','Software & Abonnementen','expense',NULL,NULL,NULL),('019bb511-7ca9-7176-9e72-bf803c390423','019bb511-7a22-7271-88f6-aa7d7c5178fe','4700','Marketing & Reclame','expense',NULL,NULL,NULL);
/*!40000 ALTER TABLE `islime_ledger_accounts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_projects`
--

DROP TABLE IF EXISTS `islime_projects`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_projects` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `customer_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `status` enum('active','on_hold','completed','cancelled') COLLATE utf8mb4_unicode_ci DEFAULT 'active',
  `start_date` date NOT NULL,
  `end_date` date DEFAULT NULL,
  `estimated_hours` decimal(10,2) DEFAULT NULL,
  `budget_amount` decimal(15,2) DEFAULT NULL,
  `hourly_rate` decimal(10,2) DEFAULT '75.00',
  `billing_type` enum('hourly','fixed','retainer') COLLATE utf8mb4_unicode_ci DEFAULT 'hourly',
  `is_billable` tinyint(1) DEFAULT '1',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  KEY `customer_id` (`customer_id`),
  CONSTRAINT `islime_projects_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE,
  CONSTRAINT `islime_projects_ibfk_2` FOREIGN KEY (`customer_id`) REFERENCES `islime_customers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_projects`
--

LOCK TABLES `islime_projects` WRITE;
/*!40000 ALTER TABLE `islime_projects` DISABLE KEYS */;
INSERT INTO `islime_projects` VALUES ('019bb511-7ce2-71c1-a6ec-c8645d43e0eb','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cb0-7179-81d2-24a6f9ad3132','Website Acme Corporation','Complete website redesign met modern design','active','2025-12-14','2026-02-12',40.00,4000.00,100.00,'hourly',1,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cf0-7067-866f-7f3589b20ccb','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cb2-70dd-be39-ee0cc7af5724','Website TechStart BV','Complete website redesign met modern design','active','2025-12-14','2026-02-12',40.00,4000.00,100.00,'hourly',1,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cfa-7097-ac42-19e2de764068','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cb4-7181-8891-6fdb6ed77dff','Website Design Studio','Complete website redesign met modern design','active','2025-12-14','2026-02-12',40.00,4000.00,100.00,'hourly',1,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL);
/*!40000 ALTER TABLE `islime_projects` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_purchase_invoices`
--

DROP TABLE IF EXISTS `islime_purchase_invoices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_purchase_invoices` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `supplier_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `invoice_number` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `invoice_date` date NOT NULL,
  `due_date` date DEFAULT NULL,
  `total` decimal(15,2) DEFAULT '0.00',
  `vat_amount` decimal(15,2) DEFAULT '0.00',
  `status` enum('draft','approved','paid','cancelled') COLLATE utf8mb4_unicode_ci DEFAULT 'draft',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  CONSTRAINT `islime_purchase_invoices_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_purchase_invoices`
--

LOCK TABLES `islime_purchase_invoices` WRITE;
/*!40000 ALTER TABLE `islime_purchase_invoices` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_purchase_invoices` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_quotes`
--

DROP TABLE IF EXISTS `islime_quotes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_quotes` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `customer_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `quote_number` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `quote_date` date NOT NULL,
  `valid_until` date DEFAULT NULL,
  `status` enum('draft','sent','accepted','rejected','expired') COLLATE utf8mb4_unicode_ci DEFAULT 'draft',
  `total` decimal(15,2) DEFAULT '0.00',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  KEY `customer_id` (`customer_id`),
  CONSTRAINT `islime_quotes_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE,
  CONSTRAINT `islime_quotes_ibfk_2` FOREIGN KEY (`customer_id`) REFERENCES `islime_customers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_quotes`
--

LOCK TABLES `islime_quotes` WRITE;
/*!40000 ALTER TABLE `islime_quotes` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_quotes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_recurring_invoices`
--

DROP TABLE IF EXISTS `islime_recurring_invoices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_recurring_invoices` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `customer_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `frequency` enum('weekly','monthly','quarterly','yearly') COLLATE utf8mb4_unicode_ci DEFAULT 'monthly',
  `status` enum('active','paused','cancelled') COLLATE utf8mb4_unicode_ci DEFAULT 'active',
  `next_invoice_date` date DEFAULT NULL,
  `amount` decimal(15,2) DEFAULT '0.00',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  KEY `customer_id` (`customer_id`),
  CONSTRAINT `islime_recurring_invoices_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE,
  CONSTRAINT `islime_recurring_invoices_ibfk_2` FOREIGN KEY (`customer_id`) REFERENCES `islime_customers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_recurring_invoices`
--

LOCK TABLES `islime_recurring_invoices` WRITE;
/*!40000 ALTER TABLE `islime_recurring_invoices` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_recurring_invoices` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_subscription_plans`
--

DROP TABLE IF EXISTS `islime_subscription_plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_subscription_plans` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_subscription_plans`
--

LOCK TABLES `islime_subscription_plans` WRITE;
/*!40000 ALTER TABLE `islime_subscription_plans` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_subscription_plans` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_subscriptions`
--

DROP TABLE IF EXISTS `islime_subscriptions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_subscriptions` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `plan_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('active','cancelled','expired') COLLATE utf8mb4_unicode_ci DEFAULT 'active',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  CONSTRAINT `islime_subscriptions_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_subscriptions`
--

LOCK TABLES `islime_subscriptions` WRITE;
/*!40000 ALTER TABLE `islime_subscriptions` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_subscriptions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_suppliers`
--

DROP TABLE IF EXISTS `islime_suppliers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_suppliers` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `address` text COLLATE utf8mb4_unicode_ci,
  `vat_number` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `default_vat_type` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT 'nl_21',
  `default_expense_account_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `notes` text COLLATE utf8mb4_unicode_ci,
  PRIMARY KEY (`id`),
  KEY `islime_suppliers_company_id_index` (`company_id`),
  CONSTRAINT `islime_suppliers_company_id_foreign` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_suppliers`
--

LOCK TABLES `islime_suppliers` WRITE;
/*!40000 ALTER TABLE `islime_suppliers` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_suppliers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_tasks`
--

DROP TABLE IF EXISTS `islime_tasks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_tasks` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `assigned_to` bigint unsigned DEFAULT NULL,
  `title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `type` enum('general','vat','banking','invoicing','reporting','year_end','accounting','onboarding') COLLATE utf8mb4_unicode_ci DEFAULT 'general',
  `priority` enum('low','normal','high','urgent') COLLATE utf8mb4_unicode_ci DEFAULT 'normal',
  `status` enum('open','in_progress','completed','cancelled') COLLATE utf8mb4_unicode_ci DEFAULT 'open',
  `due_date` date DEFAULT NULL,
  `context` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `context_id` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `completed_at` timestamp NULL DEFAULT NULL,
  `completed_by` bigint unsigned DEFAULT NULL,
  `completion_notes` text COLLATE utf8mb4_unicode_ci,
  `assigned_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  KEY `islime_tasks_created_by_foreign` (`created_by`),
  KEY `islime_tasks_completed_by_foreign` (`completed_by`),
  KEY `islime_tasks_assigned_to_status_index` (`assigned_to`,`status`),
  CONSTRAINT `islime_tasks_assigned_to_foreign` FOREIGN KEY (`assigned_to`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `islime_tasks_completed_by_foreign` FOREIGN KEY (`completed_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `islime_tasks_created_by_foreign` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `islime_tasks_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_tasks`
--

LOCK TABLES `islime_tasks` WRITE;
/*!40000 ALTER TABLE `islime_tasks` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_tasks` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_time_entries`
--

DROP TABLE IF EXISTS `islime_time_entries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_time_entries` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `project_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `customer_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_id` bigint unsigned NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `hours` decimal(5,2) NOT NULL,
  `is_running` tinyint(1) DEFAULT '0',
  `hourly_rate` decimal(10,2) NOT NULL,
  `total_amount` decimal(15,2) DEFAULT '0.00',
  `date` date NOT NULL,
  `started_at` timestamp NULL DEFAULT NULL,
  `stopped_at` timestamp NULL DEFAULT NULL,
  `is_billable` tinyint(1) DEFAULT '1',
  `is_billed` tinyint(1) DEFAULT '0',
  `invoice_id` char(36) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  KEY `project_id` (`project_id`),
  KEY `customer_id` (`customer_id`),
  KEY `user_id` (`user_id`),
  CONSTRAINT `islime_time_entries_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE,
  CONSTRAINT `islime_time_entries_ibfk_2` FOREIGN KEY (`project_id`) REFERENCES `islime_projects` (`id`) ON DELETE CASCADE,
  CONSTRAINT `islime_time_entries_ibfk_3` FOREIGN KEY (`customer_id`) REFERENCES `islime_customers` (`id`) ON DELETE SET NULL,
  CONSTRAINT `islime_time_entries_ibfk_4` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_time_entries`
--

LOCK TABLES `islime_time_entries` WRITE;
/*!40000 ALTER TABLE `islime_time_entries` DISABLE KEYS */;
INSERT INTO `islime_time_entries` VALUES ('019bb511-7ce5-7113-abab-8435b162a138','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7ce2-71c1-a6ec-c8645d43e0eb','019bb511-7cb0-7179-81d2-24a6f9ad3132',1,'Review: Gewerkt aan over ons',3.00,0,100.00,300.00,'2025-12-24',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7ce8-70fb-99ed-736e6bce3a8d','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7ce2-71c1-a6ec-c8645d43e0eb','019bb511-7cb0-7179-81d2-24a6f9ad3132',1,'Review: Gewerkt aan homepage',2.00,0,100.00,200.00,'2025-12-27',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cea-72d7-9686-03e51382eaa2','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7ce2-71c1-a6ec-c8645d43e0eb','019bb511-7cb0-7179-81d2-24a6f9ad3132',1,'Development: Gewerkt aan footer',2.00,0,100.00,200.00,'2025-12-30',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cec-733b-9ca6-23224d774162','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7ce2-71c1-a6ec-c8645d43e0eb','019bb511-7cb0-7179-81d2-24a6f9ad3132',1,'Testing: Gewerkt aan portfolio',2.00,0,100.00,200.00,'2026-01-02',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cee-7347-b843-829454758595','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7ce2-71c1-a6ec-c8645d43e0eb','019bb511-7cb0-7179-81d2-24a6f9ad3132',1,'Review: Gewerkt aan portfolio',3.00,0,100.00,300.00,'2026-01-05',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cf1-729b-9c2e-1e302f285a08','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cf0-7067-866f-7f3589b20ccb','019bb511-7cb2-70dd-be39-ee0cc7af5724',1,'Design: Gewerkt aan portfolio',4.00,0,100.00,400.00,'2025-12-24',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cf3-71c1-8886-4c241bf96968','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cf0-7067-866f-7f3589b20ccb','019bb511-7cb2-70dd-be39-ee0cc7af5724',1,'Review: Gewerkt aan contactpagina',3.00,0,100.00,300.00,'2025-12-27',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cf5-7317-ac72-3672a7efba5d','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cf0-7067-866f-7f3589b20ccb','019bb511-7cb2-70dd-be39-ee0cc7af5724',1,'Testing: Gewerkt aan portfolio',3.50,0,100.00,350.00,'2025-12-30',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cf7-71bc-9446-b647ac3ffbd0','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cf0-7067-866f-7f3589b20ccb','019bb511-7cb2-70dd-be39-ee0cc7af5724',1,'Review: Gewerkt aan contactpagina',2.00,0,100.00,200.00,'2026-01-02',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cf8-7019-8a89-44494e6068dd','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cf0-7067-866f-7f3589b20ccb','019bb511-7cb2-70dd-be39-ee0cc7af5724',1,'Review: Gewerkt aan contactpagina',1.50,0,100.00,150.00,'2026-01-05',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cfc-7241-991e-a2295b1d3bc1','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cfa-7097-ac42-19e2de764068','019bb511-7cb4-7181-8891-6fdb6ed77dff',1,'Design: Gewerkt aan footer',3.50,0,100.00,350.00,'2025-12-24',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7cfe-72a0-9f67-aa9353ccf219','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cfa-7097-ac42-19e2de764068','019bb511-7cb4-7181-8891-6fdb6ed77dff',1,'Review: Gewerkt aan homepage',3.50,0,100.00,350.00,'2025-12-27',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7d00-70bd-bb8f-a0b324bd3475','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cfa-7097-ac42-19e2de764068','019bb511-7cb4-7181-8891-6fdb6ed77dff',1,'Development: Gewerkt aan homepage',1.00,0,100.00,100.00,'2025-12-30',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7d02-728c-a202-25c6be623ae5','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cfa-7097-ac42-19e2de764068','019bb511-7cb4-7181-8891-6fdb6ed77dff',1,'Design: Gewerkt aan portfolio',2.50,0,100.00,250.00,'2026-01-02',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb511-7d03-7127-ba5a-9dff12b22317','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cfa-7097-ac42-19e2de764068','019bb511-7cb4-7181-8891-6fdb6ed77dff',1,'Testing: Gewerkt aan homepage',3.00,0,100.00,300.00,'2026-01-05',NULL,NULL,1,0,NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20',NULL),('019bb525-bd30-7111-b07b-dd46787c3b79','019bb511-7a22-7271-88f6-aa7d7c5178fe','019bb511-7cfa-7097-ac42-19e2de764068','019bb511-7cb4-7181-8891-6fdb6ed77dff',2,'Aan de boekhouding',0.00,0,100.00,0.00,'2026-01-13','2026-01-13 02:18:28','2026-01-13 02:18:29',1,0,NULL,'2026-01-13 02:18:28','2026-01-13 02:18:29',NULL);
/*!40000 ALTER TABLE `islime_time_entries` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_vat_returns`
--

DROP TABLE IF EXISTS `islime_vat_returns`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_vat_returns` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `year` int NOT NULL,
  `quarter` int NOT NULL,
  `vat_to_pay` decimal(15,2) DEFAULT '0.00',
  `status` enum('draft','submitted','paid') COLLATE utf8mb4_unicode_ci DEFAULT 'draft',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `company_id` (`company_id`),
  CONSTRAINT `islime_vat_returns_ibfk_1` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_vat_returns`
--

LOCK TABLES `islime_vat_returns` WRITE;
/*!40000 ALTER TABLE `islime_vat_returns` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_vat_returns` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `islime_webshop_integrations`
--

DROP TABLE IF EXISTS `islime_webshop_integrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `islime_webshop_integrations` (
  `id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `company_id` char(36) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `platform` enum('shopify','woocommerce','custom') COLLATE utf8mb4_unicode_ci NOT NULL,
  `shop_identifier` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `api_token` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `webhook_secret` text COLLATE utf8mb4_unicode_ci,
  `status` enum('active','inactive','connection_failed','token_expired') COLLATE utf8mb4_unicode_ci DEFAULT 'inactive',
  `sync_settings` json DEFAULT NULL,
  `mapping_settings` json DEFAULT NULL,
  `last_sync_at` timestamp NULL DEFAULT NULL,
  `last_sync_order_count` int DEFAULT NULL,
  `last_sync_error` text COLLATE utf8mb4_unicode_ci,
  `total_orders_synced` int DEFAULT '0',
  `currency` varchar(3) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `vat_country` varchar(2) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `metadata` json DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `islime_webshop_integrations_company_id_index` (`company_id`),
  KEY `islime_webshop_integrations_status_index` (`status`),
  KEY `islime_webshop_integrations_platform_index` (`platform`),
  CONSTRAINT `islime_webshop_integrations_company_id_foreign` FOREIGN KEY (`company_id`) REFERENCES `islime_companies` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `islime_webshop_integrations`
--

LOCK TABLES `islime_webshop_integrations` WRITE;
/*!40000 ALTER TABLE `islime_webshop_integrations` DISABLE KEYS */;
/*!40000 ALTER TABLE `islime_webshop_integrations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `job_batches`
--

DROP TABLE IF EXISTS `job_batches`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `job_batches` (
  `id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `total_jobs` int NOT NULL,
  `pending_jobs` int NOT NULL,
  `failed_jobs` int NOT NULL,
  `failed_job_ids` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `options` mediumtext COLLATE utf8mb4_unicode_ci,
  `cancelled_at` int DEFAULT NULL,
  `created_at` int NOT NULL,
  `finished_at` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `job_batches`
--

LOCK TABLES `job_batches` WRITE;
/*!40000 ALTER TABLE `job_batches` DISABLE KEYS */;
/*!40000 ALTER TABLE `job_batches` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `jobs`
--

DROP TABLE IF EXISTS `jobs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `jobs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `queue` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `payload` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `attempts` tinyint unsigned NOT NULL,
  `reserved_at` int unsigned DEFAULT NULL,
  `available_at` int unsigned NOT NULL,
  `created_at` int unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `jobs_queue_index` (`queue`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `jobs`
--

LOCK TABLES `jobs` WRITE;
/*!40000 ALTER TABLE `jobs` DISABLE KEYS */;
/*!40000 ALTER TABLE `jobs` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `login_rate_limit`
--

DROP TABLE IF EXISTS `login_rate_limit`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `login_rate_limit` (
  `id` int NOT NULL AUTO_INCREMENT,
  `identifier` varchar(255) NOT NULL,
  `type` enum('email','ip') NOT NULL,
  `attempt_count` int DEFAULT '1',
  `window_start` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `last_attempt` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `locked_until` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_identifier_type` (`identifier`,`type`),
  KEY `idx_window_start` (`window_start`),
  KEY `idx_locked_until` (`locked_until`)
) ENGINE=InnoDB AUTO_INCREMENT=32 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `login_rate_limit`
--

LOCK TABLES `login_rate_limit` WRITE;
/*!40000 ALTER TABLE `login_rate_limit` DISABLE KEYS */;
/*!40000 ALTER TABLE `login_rate_limit` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `mamawok_catering_requests`
--

DROP TABLE IF EXISTS `mamawok_catering_requests`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mamawok_catering_requests` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `phone` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `location` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `guests` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `budget` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `message` text COLLATE utf8mb4_unicode_ci,
  `is_read` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `mamawok_catering_requests`
--

LOCK TABLES `mamawok_catering_requests` WRITE;
/*!40000 ALTER TABLE `mamawok_catering_requests` DISABLE KEYS */;
/*!40000 ALTER TABLE `mamawok_catering_requests` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `mamawok_customers`
--

DROP TABLE IF EXISTS `mamawok_customers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mamawok_customers` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `remember_token` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `street` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `postcode` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `city` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `delivery_instructions` text COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `mamawok_customers_email_unique` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `mamawok_customers`
--

LOCK TABLES `mamawok_customers` WRITE;
/*!40000 ALTER TABLE `mamawok_customers` DISABLE KEYS */;
/*!40000 ALTER TABLE `mamawok_customers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `mamawok_discount_codes`
--

DROP TABLE IF EXISTS `mamawok_discount_codes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mamawok_discount_codes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `type` enum('percentage','fixed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'percentage',
  `value` decimal(10,2) NOT NULL,
  `minimum_order_amount` decimal(10,2) DEFAULT NULL,
  `max_uses` int DEFAULT NULL,
  `uses_count` int NOT NULL DEFAULT '0',
  `valid_from` date DEFAULT NULL,
  `valid_until` date DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `mamawok_discount_codes_code_unique` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `mamawok_discount_codes`
--

LOCK TABLES `mamawok_discount_codes` WRITE;
/*!40000 ALTER TABLE `mamawok_discount_codes` DISABLE KEYS */;
/*!40000 ALTER TABLE `mamawok_discount_codes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `mamawok_job_applications`
--

DROP TABLE IF EXISTS `mamawok_job_applications`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mamawok_job_applications` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `birthdate` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `function` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `license` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `is_read` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `mamawok_job_applications`
--

LOCK TABLES `mamawok_job_applications` WRITE;
/*!40000 ALTER TABLE `mamawok_job_applications` DISABLE KEYS */;
/*!40000 ALTER TABLE `mamawok_job_applications` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `mamawok_orders`
--

DROP TABLE IF EXISTS `mamawok_orders`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mamawok_orders` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `customer_id` bigint unsigned NOT NULL,
  `order_type` enum('delivery','pickup') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'delivery',
  `pickup_time` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `items` json NOT NULL,
  `subtotal` decimal(10,2) NOT NULL,
  `delivery_fee` decimal(10,2) NOT NULL DEFAULT '0.00',
  `discount_code` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `discount_amount` decimal(10,2) NOT NULL DEFAULT '0.00',
  `total` decimal(10,2) NOT NULL,
  `payment_method` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` enum('pending','confirmed','preparing','ready','delivered','completed','cancelled') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `notes` text COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `mamawok_orders_customer_id_foreign` (`customer_id`),
  CONSTRAINT `mamawok_orders_customer_id_foreign` FOREIGN KEY (`customer_id`) REFERENCES `mamawok_customers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `mamawok_orders`
--

LOCK TABLES `mamawok_orders` WRITE;
/*!40000 ALTER TABLE `mamawok_orders` DISABLE KEYS */;
/*!40000 ALTER TABLE `mamawok_orders` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `mamawok_settings`
--

DROP TABLE IF EXISTS `mamawok_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mamawok_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `value` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `mamawok_settings_key_unique` (`key`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `mamawok_settings`
--

LOCK TABLES `mamawok_settings` WRITE;
/*!40000 ALTER TABLE `mamawok_settings` DISABLE KEYS */;
INSERT INTO `mamawok_settings` VALUES (1,'delivery_fee','2.00','2026-01-13 02:00:21','2026-01-13 02:00:21');
/*!40000 ALTER TABLE `mamawok_settings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `mhelektra_contacts`
--

DROP TABLE IF EXISTS `mhelektra_contacts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mhelektra_contacts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `address` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `phone` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `subject` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `message` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `is_read` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `mhelektra_contacts`
--

LOCK TABLES `mhelektra_contacts` WRITE;
/*!40000 ALTER TABLE `mhelektra_contacts` DISABLE KEYS */;
/*!40000 ALTER TABLE `mhelektra_contacts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `mhelektra_projects`
--

DROP TABLE IF EXISTS `mhelektra_projects`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mhelektra_projects` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `image` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `order` int NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `mhelektra_projects`
--

LOCK TABLES `mhelektra_projects` WRITE;
/*!40000 ALTER TABLE `mhelektra_projects` DISABLE KEYS */;
INSERT INTO `mhelektra_projects` VALUES (10,'TIEL 2','kdklfsd','mhelektra/projects/f8KkWR32EseNrrHO91xa66dDptqCpuxGBW2UpHEv.jpg',0,1,'2026-01-16 01:19:17','2026-01-16 01:19:17'),(11,'sfafs','asffsfa','mhelektra/projects/ZNMIXaSywIFiLhLItJZMTZqTd52Uo68L0kt8Lwr4.jpg',0,1,'2026-01-16 01:20:02','2026-01-16 01:20:02');
/*!40000 ALTER TABLE `mhelektra_projects` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `migrations`
--

DROP TABLE IF EXISTS `migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `migrations` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `migration` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `batch` int NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=22 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `migrations`
--

LOCK TABLES `migrations` WRITE;
/*!40000 ALTER TABLE `migrations` DISABLE KEYS */;
INSERT INTO `migrations` VALUES (1,'0001_01_01_000000_create_users_table',1),(2,'0001_01_01_000001_create_cache_table',2),(3,'0001_01_01_000002_create_jobs_table',3),(4,'2026_01_06_195023_create_contacts_table',4),(5,'2026_01_07_173044_create_mamawok_customers_table',4),(6,'2026_01_07_173044_create_mamawok_orders_table',4),(7,'2026_01_07_175635_create_mamawok_settings_table',4),(8,'2026_01_07_182012_add_pickup_time_to_mamawok_orders_table',4),(9,'2026_01_07_193007_create_mamawok_catering_requests_table',4),(10,'2026_01_07_193008_create_mamawok_job_applications_table',4),(11,'2026_01_07_194943_add_auth_fields_to_mamawok_customers_table',4),(12,'2026_01_07_203613_create_gamersunited_categories_table',4),(13,'2026_01_07_203614_create_gamersunited_products_table',4),(14,'2026_01_07_203615_create_gamersunited_cart_items_table',4),(15,'2026_01_07_224906_create_mamawok_discount_codes_table',4),(16,'2026_01_07_231010_add_image_to_gamersunited_categories_table',4),(17,'2026_01_07_232736_add_brand_colors_sale_to_gamersunited_products_table',4),(18,'2026_01_08_002911_create_islime_categories_table',4),(19,'2026_01_25_150000_create_mhelektra_projects_table',5),(20,'2026_01_25_160000_create_mhelektra_contacts_table',6),(21,'2026_01_15_000000_update_mhelektra_projects_table',7);
/*!40000 ALTER TABLE `migrations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `niyah_friend_nicknames`
--

DROP TABLE IF EXISTS `niyah_friend_nicknames`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `niyah_friend_nicknames` (
  `niyah_user_id` int unsigned NOT NULL,
  `niyah_friend_id` int unsigned NOT NULL,
  `niyah_nickname` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `niyah_updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`niyah_user_id`,`niyah_friend_id`),
  KEY `niyah_nick_friend` (`niyah_friend_id`),
  CONSTRAINT `niyah_nick_friend` FOREIGN KEY (`niyah_friend_id`) REFERENCES `niyah_users` (`niyah_id`) ON DELETE CASCADE,
  CONSTRAINT `niyah_nick_user` FOREIGN KEY (`niyah_user_id`) REFERENCES `niyah_users` (`niyah_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `niyah_friend_nicknames`
--

LOCK TABLES `niyah_friend_nicknames` WRITE;
/*!40000 ALTER TABLE `niyah_friend_nicknames` DISABLE KEYS */;
/*!40000 ALTER TABLE `niyah_friend_nicknames` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `niyah_friend_requests`
--

DROP TABLE IF EXISTS `niyah_friend_requests`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `niyah_friend_requests` (
  `niyah_id` int unsigned NOT NULL AUTO_INCREMENT,
  `niyah_from_user_id` int unsigned NOT NULL,
  `niyah_to_user_id` int unsigned NOT NULL,
  `niyah_status` enum('pending','accepted','rejected') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `niyah_created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `niyah_updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`niyah_id`),
  UNIQUE KEY `niyah_from_to` (`niyah_from_user_id`,`niyah_to_user_id`),
  KEY `niyah_to_user_id` (`niyah_to_user_id`),
  KEY `niyah_status` (`niyah_status`),
  CONSTRAINT `niyah_friend_from_user` FOREIGN KEY (`niyah_from_user_id`) REFERENCES `niyah_users` (`niyah_id`) ON DELETE CASCADE,
  CONSTRAINT `niyah_friend_to_user` FOREIGN KEY (`niyah_to_user_id`) REFERENCES `niyah_users` (`niyah_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `niyah_friend_requests`
--

LOCK TABLES `niyah_friend_requests` WRITE;
/*!40000 ALTER TABLE `niyah_friend_requests` DISABLE KEYS */;
/*!40000 ALTER TABLE `niyah_friend_requests` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `niyah_user_progress`
--

DROP TABLE IF EXISTS `niyah_user_progress`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `niyah_user_progress` (
  `niyah_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `niyah_user_id` int unsigned NOT NULL,
  `niyah_progress_type` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'lesson',
  `niyah_reference_id` varchar(128) COLLATE utf8mb4_unicode_ci NOT NULL,
  `niyah_xp` int unsigned NOT NULL DEFAULT '0',
  `niyah_completed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`niyah_id`),
  UNIQUE KEY `niyah_user_type_ref` (`niyah_user_id`,`niyah_progress_type`,`niyah_reference_id`),
  KEY `niyah_user_id` (`niyah_user_id`),
  KEY `niyah_completed_at` (`niyah_completed_at`),
  CONSTRAINT `niyah_progress_user` FOREIGN KEY (`niyah_user_id`) REFERENCES `niyah_users` (`niyah_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `niyah_user_progress`
--

LOCK TABLES `niyah_user_progress` WRITE;
/*!40000 ALTER TABLE `niyah_user_progress` DISABLE KEYS */;
/*!40000 ALTER TABLE `niyah_user_progress` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `niyah_user_stats`
--

DROP TABLE IF EXISTS `niyah_user_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `niyah_user_stats` (
  `niyah_user_id` int unsigned NOT NULL,
  `niyah_lessons_completed` int unsigned NOT NULL DEFAULT '0',
  `niyah_streak_days` int unsigned NOT NULL DEFAULT '0',
  `niyah_total_xp` int unsigned NOT NULL DEFAULT '0',
  `niyah_last_activity_at` datetime DEFAULT NULL,
  `niyah_updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`niyah_user_id`),
  KEY `niyah_total_xp` (`niyah_total_xp`),
  KEY `niyah_streak_days` (`niyah_streak_days`),
  CONSTRAINT `niyah_stats_user` FOREIGN KEY (`niyah_user_id`) REFERENCES `niyah_users` (`niyah_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `niyah_user_stats`
--

LOCK TABLES `niyah_user_stats` WRITE;
/*!40000 ALTER TABLE `niyah_user_stats` DISABLE KEYS */;
INSERT INTO `niyah_user_stats` VALUES (1,0,0,0,NULL,'2026-02-19 19:56:05');
/*!40000 ALTER TABLE `niyah_user_stats` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `niyah_users`
--

DROP TABLE IF EXISTS `niyah_users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `niyah_users` (
  `niyah_id` int unsigned NOT NULL AUTO_INCREMENT,
  `niyah_email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `niyah_first_name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `niyah_last_name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `niyah_age` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `niyah_password_hash` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `niyah_auth_token` varchar(64) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `niyah_token_expires_at` datetime DEFAULT NULL,
  `niyah_created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `niyah_updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`niyah_id`),
  UNIQUE KEY `niyah_email` (`niyah_email`),
  KEY `niyah_auth_token` (`niyah_auth_token`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `niyah_users`
--

LOCK TABLES `niyah_users` WRITE;
/*!40000 ALTER TABLE `niyah_users` DISABLE KEYS */;
INSERT INTO `niyah_users` VALUES (1,'test@test.nl','Test','User','25','$2y$12$S.LDj5XSD312QV7R8z/5RO314ofN9ME6iLTZdKLrtRJuOmQ9DOKS2',NULL,NULL,'2026-02-19 19:56:05','2026-02-19 19:56:05');
/*!40000 ALTER TABLE `niyah_users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `notification_reads`
--

DROP TABLE IF EXISTS `notification_reads`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `notification_reads` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `notification_type` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `notification_key` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `read_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_notif_read` (`user_id`,`notification_type`,`notification_key`),
  CONSTRAINT `notification_reads_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `notification_reads`
--

LOCK TABLES `notification_reads` WRITE;
/*!40000 ALTER TABLE `notification_reads` DISABLE KEYS */;
/*!40000 ALTER TABLE `notification_reads` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Temporary view structure for view `order_chat_messages`
--

DROP TABLE IF EXISTS `order_chat_messages`;
/*!50001 DROP VIEW IF EXISTS `order_chat_messages`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `order_chat_messages` AS SELECT 
 1 AS `id`,
 1 AS `orderId`,
 1 AS `senderEmail`,
 1 AS `receiverEmail`,
 1 AS `body`,
 1 AS `createdAt`,
 1 AS `isRead`*/;
SET character_set_client = @saved_cs_client;

--
-- Temporary view structure for view `orders`
--

DROP TABLE IF EXISTS `orders`;
/*!50001 DROP VIEW IF EXISTS `orders`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `orders` AS SELECT 
 1 AS `orderId`,
 1 AS `senderName`,
 1 AS `senderAddress`,
 1 AS `destinationName`,
 1 AS `destinationAddress`,
 1 AS `deliveryMode`,
 1 AS `isUrgent`,
 1 AS `notes`,
 1 AS `attachmentImageData`,
 1 AS `customerEmail`,
 1 AS `status`,
 1 AS `pickedUp`,
 1 AS `paymentStatus`,
 1 AS `paymentAmount`,
 1 AS `paymentMethod`,
 1 AS `paymentTransactionId`,
 1 AS `paymentDate`,
 1 AS `assignedDriverEmail`,
 1 AS `completedByDriverEmail`,
 1 AS `serviceType`,
 1 AS `discountAmount`,
 1 AS `discountReason`,
 1 AS `createdAt`,
 1 AS `updatedAt`,
 1 AS `assignedAt`,
 1 AS `pickedUpAt`,
 1 AS `completedAt`,
 1 AS `cancelledAt`,
 1 AS `deliveryTimeMinutes`,
 1 AS `totalTimeMinutes`,
 1 AS `routeDistanceKilometers`*/;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `password_reset_tokens`
--

DROP TABLE IF EXISTS `password_reset_tokens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `password_reset_tokens` (
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `token` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `password_reset_tokens`
--

LOCK TABLES `password_reset_tokens` WRITE;
/*!40000 ALTER TABLE `password_reset_tokens` DISABLE KEYS */;
/*!40000 ALTER TABLE `password_reset_tokens` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `raptor_dispatcher_sessions`
--

DROP TABLE IF EXISTS `raptor_dispatcher_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `raptor_dispatcher_sessions` (
  `id` int NOT NULL AUTO_INCREMENT,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `token` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `pin_code` varchar(10) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `expiresAt` datetime DEFAULT NULL,
  `createdAt` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_token` (`token`),
  KEY `idx_pin` (`pin_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `raptor_dispatcher_sessions`
--

LOCK TABLES `raptor_dispatcher_sessions` WRITE;
/*!40000 ALTER TABLE `raptor_dispatcher_sessions` DISABLE KEYS */;
/*!40000 ALTER TABLE `raptor_dispatcher_sessions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `raptor_driver_locations`
--

DROP TABLE IF EXISTS `raptor_driver_locations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `raptor_driver_locations` (
  `id` int NOT NULL AUTO_INCREMENT,
  `driverEmail` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `latitude` decimal(10,8) NOT NULL,
  `longitude` decimal(11,8) NOT NULL,
  `updatedAt` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_driver` (`driverEmail`),
  CONSTRAINT `raptor_driver_locations_ibfk_1` FOREIGN KEY (`driverEmail`) REFERENCES `raptor_drivers` (`email`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `raptor_driver_locations`
--

LOCK TABLES `raptor_driver_locations` WRITE;
/*!40000 ALTER TABLE `raptor_driver_locations` DISABLE KEYS */;
/*!40000 ALTER TABLE `raptor_driver_locations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `raptor_drivers`
--

DROP TABLE IF EXISTS `raptor_drivers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `raptor_drivers` (
  `id` int NOT NULL AUTO_INCREMENT,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `passwordHash` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `driverName` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `phoneNumber` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `vehicleType` enum('bike','scooter') COLLATE utf8mb4_unicode_ci DEFAULT 'bike',
  `driverCode` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `isActive` tinyint(1) DEFAULT '1',
  `averageRating` decimal(3,2) DEFAULT NULL,
  `createdAt` datetime DEFAULT CURRENT_TIMESTAMP,
  `lastLoginAt` datetime DEFAULT NULL,
  `lastOnlineUpdate` datetime DEFAULT NULL,
  `verificationStatus` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT 'pending',
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  KEY `idx_email` (`email`),
  KEY `idx_isActive` (`isActive`),
  KEY `idx_driverCode` (`driverCode`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `raptor_drivers`
--

LOCK TABLES `raptor_drivers` WRITE;
/*!40000 ALTER TABLE `raptor_drivers` DISABLE KEYS */;
INSERT INTO `raptor_drivers` VALUES (1,'raptor_bezorger@raptor.test','Raptor2025!','Test Bezorger','+31687654321','bike','TEST001',1,4.50,'2026-02-13 20:22:37',NULL,NULL,'pending');
/*!40000 ALTER TABLE `raptor_drivers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `raptor_order_chat_messages`
--

DROP TABLE IF EXISTS `raptor_order_chat_messages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `raptor_order_chat_messages` (
  `id` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `orderId` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `senderEmail` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `receiverEmail` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `body` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `createdAt` datetime NOT NULL,
  `isRead` tinyint(1) DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `idx_order_id` (`orderId`),
  CONSTRAINT `raptor_order_chat_messages_ibfk_1` FOREIGN KEY (`orderId`) REFERENCES `raptor_orders` (`orderId`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `raptor_order_chat_messages`
--

LOCK TABLES `raptor_order_chat_messages` WRITE;
/*!40000 ALTER TABLE `raptor_order_chat_messages` DISABLE KEYS */;
/*!40000 ALTER TABLE `raptor_order_chat_messages` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `raptor_orders`
--

DROP TABLE IF EXISTS `raptor_orders`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `raptor_orders` (
  `orderId` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `senderName` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `senderAddress` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `destinationName` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `destinationAddress` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `deliveryMode` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT 'standard',
  `isUrgent` tinyint(1) DEFAULT '0',
  `notes` text COLLATE utf8mb4_unicode_ci,
  `attachmentImageData` longtext COLLATE utf8mb4_unicode_ci,
  `customerEmail` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `status` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT 'pending',
  `pickedUp` tinyint(1) DEFAULT '0',
  `paymentStatus` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT 'pending',
  `paymentAmount` decimal(10,2) DEFAULT NULL,
  `paymentMethod` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `paymentTransactionId` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `paymentDate` datetime DEFAULT NULL,
  `assignedDriverEmail` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `completedByDriverEmail` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `serviceType` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `discountAmount` decimal(10,2) DEFAULT NULL,
  `discountReason` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `createdAt` datetime DEFAULT CURRENT_TIMESTAMP,
  `updatedAt` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `assignedAt` datetime DEFAULT NULL,
  `pickedUpAt` datetime DEFAULT NULL,
  `completedAt` datetime DEFAULT NULL,
  `cancelledAt` datetime DEFAULT NULL,
  `deliveryTimeMinutes` int DEFAULT NULL,
  `totalTimeMinutes` int DEFAULT NULL,
  `routeDistanceKilometers` decimal(10,2) DEFAULT NULL,
  PRIMARY KEY (`orderId`),
  KEY `idx_status` (`status`),
  KEY `idx_assignedDriverEmail` (`assignedDriverEmail`),
  KEY `idx_customerEmail` (`customerEmail`),
  KEY `idx_createdAt` (`createdAt`),
  KEY `completedByDriverEmail` (`completedByDriverEmail`),
  CONSTRAINT `raptor_orders_ibfk_1` FOREIGN KEY (`assignedDriverEmail`) REFERENCES `raptor_drivers` (`email`) ON DELETE SET NULL,
  CONSTRAINT `raptor_orders_ibfk_2` FOREIGN KEY (`completedByDriverEmail`) REFERENCES `raptor_drivers` (`email`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `raptor_orders`
--

LOCK TABLES `raptor_orders` WRITE;
/*!40000 ALTER TABLE `raptor_orders` DISABLE KEYS */;
/*!40000 ALTER TABLE `raptor_orders` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `raptor_users`
--

DROP TABLE IF EXISTS `raptor_users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `raptor_users` (
  `id` int NOT NULL AUTO_INCREMENT,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password_hash` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `customer_type` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT 'business',
  `company_name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `contact_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `phone_number` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `address` text COLLATE utf8mb4_unicode_ci,
  `profile_image_data` longblob,
  `is_active` tinyint(1) DEFAULT '1',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `last_login_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  KEY `idx_email` (`email`),
  KEY `idx_is_active` (`is_active`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `raptor_users`
--

LOCK TABLES `raptor_users` WRITE;
/*!40000 ALTER TABLE `raptor_users` DISABLE KEYS */;
INSERT INTO `raptor_users` VALUES (1,'zaldion75@gmail.com','Ikbenmo123','individual',NULL,'Mohamed',NULL,NULL,NULL,1,'2026-02-13 19:38:48','2026-02-13 19:38:48',NULL),(2,'raptor_klant@raptor.test','Raptor2025!','individual',NULL,'Test Klant','+31612345678','Teststraat 1, 1234 AB Amsterdam',NULL,1,'2026-02-13 20:22:37','2026-02-13 20:22:37',NULL);
/*!40000 ALTER TABLE `raptor_users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `registration_rate_limit`
--

DROP TABLE IF EXISTS `registration_rate_limit`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `registration_rate_limit` (
  `id` int NOT NULL AUTO_INCREMENT,
  `identifier` varchar(255) NOT NULL,
  `type` enum('email','ip') NOT NULL,
  `attempt_count` int DEFAULT '1',
  `window_start` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `last_attempt` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_identifier_type` (`identifier`,`type`),
  KEY `idx_window_start` (`window_start`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `registration_rate_limit`
--

LOCK TABLES `registration_rate_limit` WRITE;
/*!40000 ALTER TABLE `registration_rate_limit` DISABLE KEYS */;
INSERT INTO `registration_rate_limit` VALUES (3,'zaldion75@gmail.com','email',1,'2026-02-13 20:14:23','2026-02-13 20:14:23'),(4,'62.163.72.25','ip',1,'2026-02-13 20:14:23','2026-02-13 20:14:23');
/*!40000 ALTER TABLE `registration_rate_limit` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `sessions`
--

DROP TABLE IF EXISTS `sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `sessions` (
  `id` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` bigint unsigned DEFAULT NULL,
  `ip_address` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_agent` text COLLATE utf8mb4_unicode_ci,
  `payload` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `last_activity` int NOT NULL,
  PRIMARY KEY (`id`),
  KEY `sessions_user_id_index` (`user_id`),
  KEY `sessions_last_activity_index` (`last_activity`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `sessions`
--

LOCK TABLES `sessions` WRITE;
/*!40000 ALTER TABLE `sessions` DISABLE KEYS */;
INSERT INTO `sessions` VALUES ('0OZ22lbRFf33KPssM4oIg550mEpZ7pPJ3lZVRxeV',NULL,'185.191.171.8','Mozilla/5.0 (compatible; SemrushBot/7~bl; +http://www.semrush.com/bot.html)','YTozOntzOjY6Il90b2tlbiI7czo0MDoiek85NFJoME9keGI3Y0NORWppVkxkQ1ZNZmhTb0w3VDdUcm4yd3JvWSI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjY6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sL2VuIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772247075),('2JYKROGaw7sznXMGZxObZQ2TEnJe04govmdtntQL',NULL,'89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36','YTozOntzOjY6Il90b2tlbiI7czo0MDoiakhsdGhMUmxjajhiYnByYThoaDFnWTlhSTk4VHpjTmRwbjRvOU9WOSI7czo2OiJfZmxhc2giO2E6Mjp7czozOiJvbGQiO2E6MDp7fXM6MzoibmV3IjthOjA6e319czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6NDY6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sL2FwaS90cmFpbm1hYXQvYm9va2luZ3MiO3M6NToicm91dGUiO3M6Mjg6ImFwaS50cmFpbm1hYXQuYm9va2luZ3MuaW5kZXgiO319',1772251664),('4BRXhv1Nbfmi0poXx1llF4Lmsl9vwM00ZxfqttBx',NULL,'89.205.255.117','curl/8.7.1','YTozOntzOjY6Il90b2tlbiI7czo0MDoiUUhPZFRJSEEzakhJOWRORWZORWd0cUlPcGdKUVNRQ0hOdlQ0Unp5YyI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6NDk6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sL2FwaS90cmFpbm1hYXQvb3BzL21ldHJpY3MiO3M6NToicm91dGUiO3M6MjU6ImFwaS50cmFpbm1hYXQub3BzLm1ldHJpY3MiO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772247102),('4JJZU8aly7GdCIYNZ68ELk9vXPchMEa0GOFARvdt',NULL,'111.7.100.22','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36','YTozOntzOjY6Il90b2tlbiI7czo0MDoidTIxemE5MFVCQWJqRWdWMTYzdkN1ODhGb2FQUnpYZFlxTGlSQ2VlRiI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772247383),('Cbaq0h8wsEbq8YvGJqND5X4I6kD7hcllXR3kMIcL',NULL,'89.205.255.117','curl/8.7.1','YTozOntzOjY6Il90b2tlbiI7czo0MDoid3dSUFB2YU1VcW1BcHNmb2xNVVUwZ1FMMVJITlFaQVNyWTQ2QWdORiI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6NDg6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sL2FwaS90cmFpbm1hYXQvb3BzL2hlYWx0aCI7czo1OiJyb3V0ZSI7czoyNDoiYXBpLnRyYWlubWFhdC5vcHMuaGVhbHRoIjt9czo2OiJfZmxhc2giO2E6Mjp7czozOiJvbGQiO2E6MDp7fXM6MzoibmV3IjthOjA6e319fQ==',1772250785),('dbHOa8UkKTPuXPWzooo6pSXgg4ZJeUGomEkoEaya',NULL,'51.68.107.159','Mozilla/5.0 (compatible; MJ12bot/v2.0.5; http://mj12bot.com/)','YTozOntzOjY6Il90b2tlbiI7czo0MDoiOEVoMUZ1R2t5OEpMYW5SUHg2T1hrd2NmcFptSzBpamFQdzF5eVhOVCI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772253185),('en11QbAJCg5urOTHyYGeugfbAwCMb4QQHaOvYgQY',NULL,'89.205.255.117','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36','YTozOntzOjY6Il90b2tlbiI7czo0MDoiYWZwTVM3TjBIN212M2dhbGpwbkw1c0dXQnNIeHVPVTRyQjAzelhmZSI7czo2OiJfZmxhc2giO2E6Mjp7czozOiJvbGQiO2E6MDp7fXM6MzoibmV3IjthOjA6e319czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6NzM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sL2FwaS90cmFpbm1hYXQvdmF1bHQtY29uc29sZS9zZWN1cml0eS9pcC1hbGxvd2xpc3QiO3M6NToicm91dGUiO3M6Mzc6ImFwaS50cmFpbm1hYXQuYWRtaW4uc2VjdXJpdHkuaXAuaW5kZXgiO319',1772253660),('GbalOq2VXnKiELJgzJW3x1N232hpTn5TIXHaJoFF',NULL,'89.205.255.117','curl/8.7.1','YTozOntzOjY6Il90b2tlbiI7czo0MDoiNGtIVFdLVTRWdHR1aWNJdXB6d21XbDJFeFR2QjZoSUpibFdjWndvMyI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6NDg6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sL2FwaS90cmFpbm1hYXQvb3BzL2hlYWx0aCI7czo1OiJyb3V0ZSI7czoyNDoiYXBpLnRyYWlubWFhdC5vcHMuaGVhbHRoIjt9czo2OiJfZmxhc2giO2E6Mjp7czozOiJvbGQiO2E6MDp7fXM6MzoibmV3IjthOjA6e319fQ==',1772247262),('iuJNz7tZlbwtvZKQryfw73LI53EqyfzRYV49WNrO',NULL,'89.205.255.117','curl/8.7.1','YTozOntzOjY6Il90b2tlbiI7czo0MDoic3pWa0Q0eldVMThSZmhreEhOWGo0cmFESm5kMzNEUEZHcHdoME1YMiI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6NDg6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sL2FwaS90cmFpbm1hYXQvb3BzL2hlYWx0aCI7czo1OiJyb3V0ZSI7czoyNDoiYXBpLnRyYWlubWFhdC5vcHMuaGVhbHRoIjt9czo2OiJfZmxhc2giO2E6Mjp7czozOiJvbGQiO2E6MDp7fXM6MzoibmV3IjthOjA6e319fQ==',1772247252),('KcpE3lOjWHN4QJ3TjRqWE5ZDGSBUZdp1GTCbqsfp',NULL,'89.205.255.117','curl/8.7.1','YTozOntzOjY6Il90b2tlbiI7czo0MDoiYlozb2ludU1NS1dGamNzYkZJeHU2bGpGZjl2N3BCd09RV052RHRxMSI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6NDg6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sL2FwaS90cmFpbm1hYXQvb3BzL2hlYWx0aCI7czo1OiJyb3V0ZSI7czoyNDoiYXBpLnRyYWlubWFhdC5vcHMuaGVhbHRoIjt9czo2OiJfZmxhc2giO2E6Mjp7czozOiJvbGQiO2E6MDp7fXM6MzoibmV3IjthOjA6e319fQ==',1772247947),('KmDtK6n34Nn8KjS1cXfZjmvipLU50FYueKw2TdGn',NULL,'64.89.163.113','','YTozOntzOjY6Il90b2tlbiI7czo0MDoiMHZENUtXTFpMQmVQY0NIQ1lDaGtibmR2cVZscnIwWEFZZklnZlh2RCI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772247978),('l2WaaPGQwFtzjDKKVPrWDjdChsqssNlKVJ3Tol1E',NULL,'43.159.149.216','Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1','YTozOntzOjY6Il90b2tlbiI7czo0MDoiMkxoQTBtZWxBczkyaHlhb096dUR1WHJZeDlFSk5hQnhMWlRSQmZLSCI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772250094),('Qmm6o0M6kOvPjdTOS0etZ9SEiG6T9pOxNFf1kCEb',NULL,'111.7.100.25','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36','YTozOntzOjY6Il90b2tlbiI7czo0MDoiNUQ1TlpQYUJxZnBRS0dlVlVYT3ZXUDgzNUVCQWV6aVUzWHNXZnpBdyI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772248329),('Rur81Tpn4FAoQQJvtQLvJ3qeYj9AbarRRZChLRax',NULL,'180.95.238.217','Mozilla/5.082584686 Mozilla/5.0 (iPhone; CPU iPhone OS 11_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.0 Mobile/15E148 Safari/604.1','YTozOntzOjY6Il90b2tlbiI7czo0MDoicmg4OTdHd0pYTUNCVUZwVVZBbktPUXRDVzJqekM2ek5XTTF1bzQyQSI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772248384),('SyTc2w4lXItAzTy2lxeQ2NVjReT3BVSZfdwXihz1',NULL,'111.7.100.21','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36','YTozOntzOjY6Il90b2tlbiI7czo0MDoiQUI1WWpGSWpQRWhSNGhlZnRkUmg4eHR6eGYzUXFxeHpTUDhSQldhayI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772247381),('tV0KSFMRsYNSiTtIXav58JiQF2XzsaPIilg5xDLu',NULL,'172.235.40.131','Mozilla/5.0 (Macintosh; Intel Mac OS X 13_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36','YTozOntzOjY6Il90b2tlbiI7czo0MDoiNjU0RjV1ekNxOTdmRUN1dDJHNHV3Q3Jyd3dHa09zTU5ldk1MT0NFbiI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772252526),('UI6YHpHLTRPPGzlTb4xIqU93li5y6a2JIFBXtyiU',NULL,'35.203.211.61','Hello from Palo Alto Networks, find out more about our scans in https://docs-cortex.paloaltonetworks.com/r/1/Cortex-Xpanse/Scanning-activity','YTozOntzOjY6Il90b2tlbiI7czo0MDoiZnY1M1pwQUZndUxrakdQcENDSmRxcFdyZjc3SmZPRkI1aFhqc2psRCI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772251997),('uID4XY73WLliqNIcMaUu1Ydg7v8GlPyVeldJbOVs',NULL,'111.7.100.27','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36','YTozOntzOjY6Il90b2tlbiI7czo0MDoiZWdKRmpLUnN5cVc1ZTBIMmhNZzR4MTdkRk10NDBCMG9GdXR3NUY3eCI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772248330),('VtYbJtdbwLvtfAwFkyZFjBvHOen5VIqQNyGvgR9m',NULL,'89.205.255.117','curl/8.7.1','YTozOntzOjY6Il90b2tlbiI7czo0MDoiUTQwUWFzcEh5SEN5dXVVWVFBRUQ2Wk9IOXVXOW9EWktsaVdpSFl1YiI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6NDg6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sL2FwaS90cmFpbm1hYXQvb3BzL2hlYWx0aCI7czo1OiJyb3V0ZSI7czoyNDoiYXBpLnRyYWlubWFhdC5vcHMuaGVhbHRoIjt9czo2OiJfZmxhc2giO2E6Mjp7czozOiJvbGQiO2E6MDp7fXM6MzoibmV3IjthOjA6e319fQ==',1772247102),('wYvomqwyYNuMaJOJv4Q8OjFO6lay3jO2QzcV0Yjv',NULL,'79.124.40.174','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/78.0.3904.108 Safari/537.36','YTozOntzOjY6Il90b2tlbiI7czo0MDoib084VTg2MGNLTTFBcWpHZmkwOERnVlpQa3B1MTRuZ1pkbk4xVDRSMSI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6NTQ6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sLz9YREVCVUdfU0VTU0lPTl9TVEFSVD1waHBzdG9ybSI7czo1OiJyb3V0ZSI7Tjt9czo2OiJfZmxhc2giO2E6Mjp7czozOiJvbGQiO2E6MDp7fXM6MzoibmV3IjthOjA6e319fQ==',1772247953),('Z135SeKetznOmb7NH8qeWf7GXkTFxlxaderFDseM',NULL,'3.221.83.235','Mozilla/5.0 (Windows NT 6.1; WOW64; Trident/7.0; rv:11.0) like Gecko','YTozOntzOjY6Il90b2tlbiI7czo0MDoibXJaYXUyZXFiaU5QR3Z5MmQ2Yzg5aVIwNzVRRE45UDlCOUtGcTg0MSI7czo5OiJfcHJldmlvdXMiO2E6Mjp7czozOiJ1cmwiO3M6MjM6Imh0dHBzOi8vbWRqaXNlcnZpY2VzLm5sIjtzOjU6InJvdXRlIjtOO31zOjY6Il9mbGFzaCI7YToyOntzOjM6Im9sZCI7YTowOnt9czozOiJuZXciO2E6MDp7fX19',1772253197);
/*!40000 ALTER TABLE `sessions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_preferences`
--

DROP TABLE IF EXISTS `user_preferences`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_preferences` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `terminology` enum('standard','accounting') COLLATE utf8mb4_unicode_ci DEFAULT 'standard',
  `has_seen_terminology_modal` tinyint(1) DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_id` (`user_id`),
  CONSTRAINT `user_preferences_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_preferences`
--

LOCK TABLES `user_preferences` WRITE;
/*!40000 ALTER TABLE `user_preferences` DISABLE KEYS */;
INSERT INTO `user_preferences` VALUES (7,2,'accounting',1,'2026-01-13 02:04:14','2026-01-13 02:06:58'),(8,4,'standard',0,'2026-01-15 02:04:01','2026-01-15 02:04:01');
/*!40000 ALTER TABLE `user_preferences` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email_verified_at` timestamp NULL DEFAULT NULL,
  `password` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `remember_token` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `users_email_unique` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
INSERT INTO `users` VALUES (1,'Test Owner','owner@test.nl',NULL,'$2y$12$7dYCnQp/mePGQtGI2..Ieeaxyg485nswei.zJZXYJ3/BCV3Hlqay.',NULL,'2026-01-13 01:56:20','2026-01-15 01:46:48'),(2,'Test Accountant','accountant@test.nl',NULL,'$2y$12$sv4giUaXBvcJx7qusCNEAeZWrlv/GL8Xm13V9vcfm1Ql2DZ7o6Z.a',NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20'),(3,'Test Viewer','viewer@test.nl',NULL,'$2y$12$plMaIBwy.LKhuRvvu1GYUOoVuRlzgEMPooDraZDR.U3qF9cMx.E0e',NULL,'2026-01-13 01:56:20','2026-01-13 01:56:20'),(4,'MHElektra Admin','admin@mhelektra.nl',NULL,'$2y$12$VzLMjI.YW611uSmbvBXf0u1EiucvfHJUW5S5xyFK5VRZobgGJDyWq','5lU01YPLAgScYYjiRYjtz2NBbuGqbGhqe6eceHuzI53fGXCx5MDwClGXWCDN','2026-01-15 01:48:41','2026-01-15 01:48:41');
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Final view structure for view `customer_accounts`
--

/*!50001 DROP VIEW IF EXISTS `customer_accounts`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`mdjiservices_user`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `customer_accounts` AS select `raptor_users`.`id` AS `id`,`raptor_users`.`email` AS `email`,`raptor_users`.`password_hash` AS `password_hash`,`raptor_users`.`customer_type` AS `customer_type`,`raptor_users`.`company_name` AS `company_name`,`raptor_users`.`contact_name` AS `contact_name`,`raptor_users`.`phone_number` AS `phone_number`,`raptor_users`.`address` AS `address`,`raptor_users`.`profile_image_data` AS `profile_image_data`,`raptor_users`.`is_active` AS `is_active`,`raptor_users`.`created_at` AS `created_at`,`raptor_users`.`updated_at` AS `updated_at`,`raptor_users`.`last_login_at` AS `last_login_at` from `raptor_users` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `dispatcher_sessions`
--

/*!50001 DROP VIEW IF EXISTS `dispatcher_sessions`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`mdjiservices_user`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `dispatcher_sessions` AS select `raptor_dispatcher_sessions`.`id` AS `id`,`raptor_dispatcher_sessions`.`email` AS `email`,`raptor_dispatcher_sessions`.`token` AS `token`,`raptor_dispatcher_sessions`.`pin_code` AS `pin_code`,`raptor_dispatcher_sessions`.`expiresAt` AS `expiresAt`,`raptor_dispatcher_sessions`.`createdAt` AS `createdAt` from `raptor_dispatcher_sessions` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `driver_locations`
--

/*!50001 DROP VIEW IF EXISTS `driver_locations`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`mdjiservices_user`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `driver_locations` AS select `raptor_driver_locations`.`id` AS `id`,`raptor_driver_locations`.`driverEmail` AS `driverEmail`,`raptor_driver_locations`.`latitude` AS `latitude`,`raptor_driver_locations`.`longitude` AS `longitude`,`raptor_driver_locations`.`updatedAt` AS `updatedAt` from `raptor_driver_locations` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `drivers`
--

/*!50001 DROP VIEW IF EXISTS `drivers`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`mdjiservices_user`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `drivers` AS select `raptor_drivers`.`id` AS `id`,`raptor_drivers`.`email` AS `email`,`raptor_drivers`.`passwordHash` AS `passwordHash`,`raptor_drivers`.`driverName` AS `driverName`,`raptor_drivers`.`phoneNumber` AS `phoneNumber`,`raptor_drivers`.`vehicleType` AS `vehicleType`,`raptor_drivers`.`driverCode` AS `driverCode`,`raptor_drivers`.`isActive` AS `isActive`,`raptor_drivers`.`averageRating` AS `averageRating`,`raptor_drivers`.`createdAt` AS `createdAt`,`raptor_drivers`.`lastLoginAt` AS `lastLoginAt`,`raptor_drivers`.`lastOnlineUpdate` AS `lastOnlineUpdate`,`raptor_drivers`.`verificationStatus` AS `verificationStatus` from `raptor_drivers` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `order_chat_messages`
--

/*!50001 DROP VIEW IF EXISTS `order_chat_messages`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`mdjiservices_user`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `order_chat_messages` AS select `raptor_order_chat_messages`.`id` AS `id`,`raptor_order_chat_messages`.`orderId` AS `orderId`,`raptor_order_chat_messages`.`senderEmail` AS `senderEmail`,`raptor_order_chat_messages`.`receiverEmail` AS `receiverEmail`,`raptor_order_chat_messages`.`body` AS `body`,`raptor_order_chat_messages`.`createdAt` AS `createdAt`,`raptor_order_chat_messages`.`isRead` AS `isRead` from `raptor_order_chat_messages` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `orders`
--

/*!50001 DROP VIEW IF EXISTS `orders`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`mdjiservices_user`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `orders` AS select `raptor_orders`.`orderId` AS `orderId`,`raptor_orders`.`senderName` AS `senderName`,`raptor_orders`.`senderAddress` AS `senderAddress`,`raptor_orders`.`destinationName` AS `destinationName`,`raptor_orders`.`destinationAddress` AS `destinationAddress`,`raptor_orders`.`deliveryMode` AS `deliveryMode`,`raptor_orders`.`isUrgent` AS `isUrgent`,`raptor_orders`.`notes` AS `notes`,`raptor_orders`.`attachmentImageData` AS `attachmentImageData`,`raptor_orders`.`customerEmail` AS `customerEmail`,`raptor_orders`.`status` AS `status`,`raptor_orders`.`pickedUp` AS `pickedUp`,`raptor_orders`.`paymentStatus` AS `paymentStatus`,`raptor_orders`.`paymentAmount` AS `paymentAmount`,`raptor_orders`.`paymentMethod` AS `paymentMethod`,`raptor_orders`.`paymentTransactionId` AS `paymentTransactionId`,`raptor_orders`.`paymentDate` AS `paymentDate`,`raptor_orders`.`assignedDriverEmail` AS `assignedDriverEmail`,`raptor_orders`.`completedByDriverEmail` AS `completedByDriverEmail`,`raptor_orders`.`serviceType` AS `serviceType`,`raptor_orders`.`discountAmount` AS `discountAmount`,`raptor_orders`.`discountReason` AS `discountReason`,`raptor_orders`.`createdAt` AS `createdAt`,`raptor_orders`.`updatedAt` AS `updatedAt`,`raptor_orders`.`assignedAt` AS `assignedAt`,`raptor_orders`.`pickedUpAt` AS `pickedUpAt`,`raptor_orders`.`completedAt` AS `completedAt`,`raptor_orders`.`cancelledAt` AS `cancelledAt`,`raptor_orders`.`deliveryTimeMinutes` AS `deliveryTimeMinutes`,`raptor_orders`.`totalTimeMinutes` AS `totalTimeMinutes`,`raptor_orders`.`routeDistanceKilometers` AS `routeDistanceKilometers` from `raptor_orders` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-02-28  4:43:21

-- ========== TrainMaat admin werkbak (saved views, note templates) – toegevoegd aan complete schema ==========

-- Admin Control Tower: werkbak, saved views, note templates
-- Uitvoeren: mysql -u user -p database < alter_gymies_admin_werkbak.sql

SET NAMES utf8mb4;

-- Saved filters/views per admin (optioneel user_id = NULL = globale view)
CREATE TABLE IF NOT EXISTS gymies_admin_saved_views (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NULL DEFAULT NULL COMMENT 'NULL = globale view voor iedereen',
  name VARCHAR(120) NOT NULL,
  entity_type VARCHAR(32) NOT NULL COMMENT 'users, tickets, bookings, payouts',
  filters JSON NOT NULL COMMENT 'bijv. {"status":"new","priority":"high"}',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_admin_saved_views_user_entity (user_id, entity_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Standaard notitietemplates voor snelle reacties
CREATE TABLE IF NOT EXISTS gymies_admin_note_templates (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(120) NOT NULL,
  body TEXT NOT NULL,
  category VARCHAR(32) NOT NULL DEFAULT 'general' COMMENT 'ticket, booking, general',
  sort_order SMALLINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_admin_note_templates_category (category),
  UNIQUE KEY gymies_admin_note_templates_name_category (name, category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Default templates (INSERT IGNORE = veilig opnieuw draaien)
INSERT IGNORE INTO gymies_admin_note_templates (name, body, category, sort_order) VALUES
('KYC check pending', 'KYC-check loopt. Klant is geïnformeerd.', 'ticket', 10),
('Client contacted', 'Klant is gecontacteerd; wacht op reactie.', 'ticket', 20),
('Refund approved', 'Terugbetaling goedgekeurd. Verwerkt binnen 5 werkdagen.', 'ticket', 30),
('Escalated to specialist', 'Doorgestuurd naar specialist voor verdere afhandeling.', 'ticket', 40),
('Booking incident – no-show', 'No-show geregistreerd. Trainer heeft klant proberen te bereiken.', 'booking', 10),
('Booking incident – dispute', 'Geschil gemeld. Beide partijen gehoord; follow-up volgt.', 'booking', 20),
('Payout blocked – verification', 'Uitbetaling gepauzeerd tot verificatie is afgerond.', 'general', 10),
('Fraude review in progress', 'Fraudecheck loopt. Geen actie tot conclusie.', 'general', 20);
