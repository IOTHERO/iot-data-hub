-- Rollback of 0020_local_control (python -m hub.storage.migrate --rollback 0020_local_control).
-- auth_audit is append-only, so its rows of the three local events stay and the event list
-- keeps them; only the key table goes.

DROP TABLE device_local_keys;
