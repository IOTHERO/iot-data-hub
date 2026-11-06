-- 0022_security_modes: a home's security scenarios, switched on and off by its people.
-- Rollback: db/migrations/down/0022_security_modes.sql.
--
-- A tripped sensor is an alarm only while its scenario is on (backend/home_alerts.py):
--   burglar  away from home: motion sensors (PIR) and door / window magnets
--   night    at home / at night: door / window magnets only, people move about inside
--   fire     smoke detectors (on unless the home turns it off)
--   offline  a device of the home that guards it (one with alarm sensors, or an edge hub) is
--            cut off from the server for a few minutes: the home cannot tell anyone itself
-- Zones are not fixed pins: any on/off input of any module of the home becomes one by its type
-- (motion, magnet, smoke: output_labels.icon or the template's). The siren likewise is whichever
-- outputs the home picks (sirens). The scenarios and the siren outputs also go to the home's
-- devices with their local rules, so a device that loses the internet still knows whether it is
-- armed and which of its outputs is a siren.

CREATE TABLE home_security (
    org_id      text PRIMARY KEY REFERENCES organizations (org_id),
    burglar     boolean NOT NULL DEFAULT false,
    night       boolean NOT NULL DEFAULT false,
    fire        boolean NOT NULL DEFAULT true,
    offline     boolean NOT NULL DEFAULT true,
    -- the siren: any outputs of any of the home's modules ([{"device_id", "key"}]; e.g. relay 3
    -- of an 8-output module while the zones are wired to an 8-input module), sounding for
    -- siren_s seconds or until someone marks the alarm seen
    sirens      jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(sirens) = 'array'),
    siren_s     integer NOT NULL DEFAULT 180 CHECK (siren_s BETWEEN 10 AND 1800),
    updated_by  integer REFERENCES users (user_id),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE security_alerts DROP CONSTRAINT security_alerts_kind_check;
ALTER TABLE security_alerts ADD CONSTRAINT security_alerts_kind_check
    CHECK (kind IN ('motion', 'magnet', 'smoke', 'offline'));

-- A member's mobile number is kept with the member (the home's access page): a contact linked to
-- the member's account, so the home knows whose each account is. Contacts without one are people
-- without an account (a neighbour). Alarm recipients are picked by name from both.
ALTER TABLE home_contacts ADD COLUMN member_id integer REFERENCES users (user_id);
CREATE UNIQUE INDEX home_contacts_member_idx ON home_contacts (org_id, member_id)
    WHERE member_id IS NOT NULL;

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
    'rf_key_learnt',
    'security_mode_changed', 'member_phone_set'));
