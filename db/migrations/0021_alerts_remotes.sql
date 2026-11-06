-- 0021_alerts_remotes: security alerts a home must acknowledge, and learnt RF remotes.
-- Rollback: db/migrations/down/0021_alerts_remotes.sql.
--
-- A motion sensor (a hallway PIR), a door / window magnet or a smoke detector of a home is a
-- burglar / fire alarm wherever it is: when it trips, the hub opens an alert for the home
-- (backend/alerts.py). Another trip while it is open counts on the same alert. People of the
-- home see it live, mark it seen and clear it; who did so is kept.
--
-- An RF module (433 or 315 MHz) learns the code of a remote's key into a numbered slot of its
-- own memory and sends a slot's code again on request (the template's rf_* tags; both are
-- writes through the control-safety layer). The hub keeps what the home calls the remote and
-- its keys and which slot holds which key.

CREATE TABLE security_alerts (
    alert_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    org_id      text NOT NULL REFERENCES organizations (org_id),
    device_id   text NOT NULL REFERENCES platform_devices (device_id),
    tag_key     text NOT NULL CHECK (tag_key ~ '^[a-z][a-z0-9_]{0,63}$'),
    kind        text NOT NULL CHECK (kind IN ('motion', 'magnet', 'smoke')),
    started_at  timestamptz NOT NULL,
    last_at     timestamptz NOT NULL,
    trips       integer NOT NULL DEFAULT 1 CHECK (trips >= 1),
    seen_at     timestamptz,
    seen_by     integer REFERENCES users (user_id),
    cleared_at  timestamptz,
    cleared_by  integer REFERENCES users (user_id)
);
-- at most one open alert per sensor
CREATE UNIQUE INDEX security_alerts_open_idx ON security_alerts (device_id, tag_key)
    WHERE cleared_at IS NULL;
CREATE INDEX security_alerts_org_idx ON security_alerts (org_id, started_at DESC);

CREATE TABLE rf_remotes (
    remote_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    device_id   text NOT NULL REFERENCES platform_devices (device_id),
    name        text NOT NULL CHECK (length(name) BETWEEN 1 AND 40),
    band        smallint NOT NULL CHECK (band IN (315, 433)),
    icon        text CHECK (icon IS NULL OR icon ~ '^[a-z][a-z0-9_-]{0,39}$'),
    created_by  integer REFERENCES users (user_id),
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX rf_remotes_device_idx ON rf_remotes (device_id);

CREATE TABLE rf_keys (
    key_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    remote_id   bigint NOT NULL REFERENCES rf_remotes (remote_id) ON DELETE CASCADE,
    device_id   text NOT NULL REFERENCES platform_devices (device_id),
    slot        integer NOT NULL CHECK (slot BETWEEN 1 AND 9999),
    name        text NOT NULL CHECK (length(name) BETWEEN 1 AND 40),
    icon        text CHECK (icon IS NULL OR icon ~ '^[a-z][a-z0-9_-]{0,39}$'),
    position    integer NOT NULL DEFAULT 0 CHECK (position BETWEEN 0 AND 1000),
    learnt_at   timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (device_id, slot)
);

ALTER TABLE auth_audit DROP CONSTRAINT auth_audit_event_check;
ALTER TABLE auth_audit ADD CONSTRAINT auth_audit_event_check CHECK (event IN (
    'login_ok', 'login_failed', 'login_throttled', 'logout', 'locked', 'unlocked',
    'password_changed', 'password_expired', 'user_created', 'user_updated', 'user_disabled',
    'role_granted', 'role_revoked', 'session_revoked', 'session_expired', 'alarm_acked',
    'alarm_shelved', 'alarm_unshelved', 'write_confirmed', 'write_rejected', 'config_changed',
    'schedule_created', 'schedule_updated', 'schedule_deleted', 'opcua_login', 'mfa_enabled',
    'mfa_disabled', 'mfa_failed', 'mfa_reset', 'network_denied', 'roles_synced',
    'directory_unavailable', 'config_restored', 'maintenance_recorded',
    'organization_created', 'organization_updated', 'product_saved', 'product_version_saved',
    'product_version_published', 'devices_registered', 'platform_device_updated',
    'account_signup', 'email_verified', 'password_reset_requested', 'password_reset',
    'invitation_created', 'invitation_accepted', 'invitation_revoked', 'member_removed',
    'device_shared', 'device_share_revoked', 'account_throttled',
    'claim_codes_issued', 'device_claimed', 'claim_failed', 'device_released',
    'device_transfer_started', 'device_reset', 'child_device_added', 'child_device_removed',
    'device_auth_failed', 'automation_saved', 'automation_deleted', 'scene_saved',
    'scene_deleted', 'scene_run', 'holiday_saved', 'devices_upgraded', 'firmware_released',
    'firmware_withdrawn', 'firmware_rollout',
    'account_deleted', 'home_created', 'home_updated', 'ticket_opened', 'ticket_updated',
    'plan_changed', 'branding_saved', 'sms_settings_saved', 'group_saved',
    'contact_saved', 'contact_deleted', 'sms_pin_set', 'sms_command', 'sms_command_refused',
    'level_saved', 'level_deleted', 'member_role_changed',
    'local_keys_fetched', 'local_key_rotated', 'local_commands_reported',
    'security_alert_seen', 'security_alerts_cleared', 'rf_remote_saved', 'rf_remote_deleted',
    'rf_key_learnt'));
