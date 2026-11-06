-- Rollback of 0022_security_modes (python -m hub.storage.migrate --rollback 0022_security_modes).
-- auth_audit is append-only, so its rows of security_mode_changed stay and the event list keeps
-- it; the connection-loss alerts go before the alert kinds go back to the three sensors.

DELETE FROM security_alerts WHERE kind = 'offline';
ALTER TABLE security_alerts DROP CONSTRAINT security_alerts_kind_check;
ALTER TABLE security_alerts ADD CONSTRAINT security_alerts_kind_check
    CHECK (kind IN ('motion', 'magnet', 'smoke'));
DROP INDEX home_contacts_member_idx;
ALTER TABLE home_contacts DROP COLUMN member_id;
DROP TABLE home_security;
