-- Incident workflow: koppeling ticket, resolutie (betaal trainer / geef klant credit / splits)

ALTER TABLE gymies_admin_alerts
  ADD COLUMN linked_ticket_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'Ticket aangemaakt bij incident' AFTER entity_id,
  ADD COLUMN resolution_type VARCHAR(64) DEFAULT NULL COMMENT 'pay_trainer, give_client_credit, split' AFTER status,
  ADD COLUMN resolution_reason VARCHAR(500) DEFAULT NULL AFTER resolution_type,
  ADD COLUMN resolved_at TIMESTAMP NULL DEFAULT NULL AFTER resolution_reason,
  ADD COLUMN resolved_by_user_id BIGINT UNSIGNED DEFAULT NULL AFTER resolved_at,
  ADD KEY gymies_admin_alerts_linked_ticket (linked_ticket_id);

-- FK optioneel (tabel kan op andere volgorde bestaan)
-- ALTER TABLE gymies_admin_alerts ADD CONSTRAINT gymies_admin_alerts_ticket_fk FOREIGN KEY (linked_ticket_id) REFERENCES gymies_support_tickets (id) ON DELETE SET NULL;
