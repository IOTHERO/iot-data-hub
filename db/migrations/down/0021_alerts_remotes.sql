-- Rollback of 0021_alerts_remotes (python -m hub.storage.migrate --rollback 0021_alerts_remotes).
-- auth_audit is append-only, so its rows of the new events stay and the event list keeps them;
-- only the tables go.

DROP TABLE rf_keys;
DROP TABLE rf_remotes;
DROP TABLE security_alerts;
