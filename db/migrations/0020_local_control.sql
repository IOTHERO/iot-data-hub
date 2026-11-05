-- 0020_local_control: control of a device over the home network while the internet is down.
-- Rollback: db/migrations/down/0020_local_control.sql.
--
-- Each device gets a local key (32 random bytes, base64url) the hub gives the device over its
-- own connection and the phones of the members who may fully control it (owner, operators,
-- members without room / output / hour limits). On the home Wi-Fi the app asks the device for
-- a one-time nonce and signs every command with HMAC-SHA256 of that key (backend/local.py),
-- so a guest on the same Wi-Fi can neither send nor replay a command. The device reports its
-- address on the home network (local_addr) so the phone finds it without the cloud. The key
-- changes when the device changes hands or a member of its home is removed.

CREATE TABLE device_local_keys (
    device_id   text PRIMARY KEY REFERENCES platform_devices (device_id),
    key         text NOT NULL CHECK (key ~ '^[A-Za-z0-9_-]{43}$'),
    version     integer NOT NULL DEFAULT 1 CHECK (version >= 1),
    local_addr  text CHECK (local_addr IS NULL OR local_addr ~ '^[0-9A-Za-z.:\[\]-]{3,64}$'),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
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
    'local_keys_fetched', 'local_key_rotated', 'local_commands_reported'));
