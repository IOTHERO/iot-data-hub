-- Rollback of 0018_home_levels (python -m hub.storage.migrate --rollback 0018_home_levels).
-- Members on a custom level become plain members first. The auth_audit event names stay.

UPDATE user_roles SET role_id = 'customer_member' WHERE role_id LIKE 'lvl\_%';
UPDATE invitations SET role_id = 'customer_member' WHERE role_id LIKE 'lvl\_%';
DELETE FROM roles WHERE role_id LIKE 'lvl\_%';
DROP TABLE home_levels;
DELETE FROM role_permissions WHERE permission_id IN
    ('scene.run', 'timer.manage', 'energy.view', 'home.settings', 'ticket.manage');
DELETE FROM permissions WHERE permission_id IN
    ('scene.run', 'timer.manage', 'energy.view', 'home.settings', 'ticket.manage');
