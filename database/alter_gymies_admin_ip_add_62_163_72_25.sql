-- Voeg IP 62.163.72.25 toe aan admin allowlist (vault-console toegang)
INSERT INTO gymies_admin_ip_allowlist (ip_pattern, status, created_at, updated_at)
VALUES ('62.163.72.25', 'active', NOW(), NOW());
