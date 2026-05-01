-- Spoed Inval: status unassigned/failed voor backoffice-monitoring.
-- unassigned = verlopen (expires_at), niemand heeft geaccepteerd.
-- failed = alle aanbiedingen geweigerd, niemand heeft geaccepteerd.
--
-- Voer uit na alter_gymies_spoed_inval.sql

ALTER TABLE gymies_spoed_inval_requests
  MODIFY COLUMN status ENUM(
    'pending', 'accepted', 'declined', 'cancelled', 'expired',
    'unassigned', 'failed'
  ) NOT NULL DEFAULT 'pending';
