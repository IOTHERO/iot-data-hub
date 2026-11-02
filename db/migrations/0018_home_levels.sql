-- 0018_home_levels: access levels a home defines for its members (platform, phase 10).
-- Rollback: db/migrations/down/0018_home_levels.sql.
--
-- A level is a role of one home: a name, a set of permissions (ticks in the app), and limits:
-- which devices / outputs (rooms, groups or single outputs; none = every device), when the
-- member may operate (Jalali weekdays, hours; none = always) and whether the member may change
-- only the scenes and automations he made. The built-in roles (owner, member, viewer) stay.
-- The limits are enforced on the server: the device lists, the views and the control-safety
-- layer (every write, including the scenes and automations a limited member made).

INSERT INTO permissions (permission_id, description) VALUES
    ('scene.run',     'Run the scenes of an organization'),
    ('timer.manage',  'Countdown and repeating timers on the devices of an organization'),
    ('energy.view',   'See the energy use and its cost'),
    ('home.settings', 'Change the home''s settings: place, tariff, SMS contacts and PIN'),
    ('ticket.manage', 'Support requests and warranty claims to the maker');
INSERT INTO role_permissions (role_id, permission_id) VALUES
    ('customer_owner', 'scene.run'), ('customer_owner', 'timer.manage'),
    ('customer_owner', 'energy.view'), ('customer_owner', 'home.settings'),
    ('customer_owner', 'ticket.manage'),
    ('customer_member', 'scene.run'), ('customer_member', 'timer.manage'),
    ('customer_member', 'energy.view'), ('customer_member', 'ticket.manage'),
    ('customer_viewer', 'energy.view'),
    ('admin', 'scene.run'), ('admin', 'timer.manage'), ('admin', 'energy.view'),
    ('admin', 'home.settings'), ('admin', 'ticket.manage');

-- role_id is a row of roles (so grants, invitations and every permission check work as for
-- the built-in roles): 'lvl_' + random; the permissions are rows of role_permissions
CREATE TABLE home_levels (
    role_id     text PRIMARY KEY REFERENCES roles (role_id) ON DELETE CASCADE
                CHECK (role_id ~ '^lvl_[a-z0-9]{8,32}$'),
    org_id      text NOT NULL REFERENCES organizations (org_id) ON DELETE CASCADE,
    name        text NOT NULL CHECK (length(name) BETWEEN 1 AND 40),
    -- {"rooms": [...], "groups": [group_id...], "outputs": [{"device_id", "key"}]}; {} = all
    scope       jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(scope) = 'object'),
    -- {"weekdays": [0..6], "from": "08:00", "to": "18:00"} (Tehran time); NULL = always
    schedule    jsonb CHECK (schedule IS NULL OR jsonb_typeof(schedule) = 'object'),
    own_only    boolean NOT NULL DEFAULT false,      -- edits only his own scenes/automations
    created_by  integer REFERENCES users (user_id),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (org_id, name)
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
    'level_saved', 'level_deleted', 'member_role_changed'));
