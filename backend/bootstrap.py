"""First install: one administrator with access to every panel, from deploy/.env.

On the first start of an empty database, when ``HUB_BOOTSTRAP_ADMIN_PASSWORD`` is set, the hub
creates one account (default user name ``admin``) that works in all three places - the engineering
dashboard (administrator), the maker panel (administrator of the default manufacturer, so the
whole product / production / labels work can start at once) and the customer web app and phone app
(its own home) - and requires a new password at the first sign-in. Nobody has to open a terminal
for the first account. Once any user exists this does nothing, so changing the setting later, or
deleting the password from deploy/.env after the first sign-in, is safe.
"""

from __future__ import annotations

import logging
from typing import Any

from backend.security import hash_password, password_problems
from hub.storage.platform import PlatformError

log = logging.getLogger("hub.bootstrap")


async def bootstrap_first_install(store: Any, settings: Any) -> bool:
    """Create the default administrator on an empty database; True when it did."""
    password = settings.bootstrap_admin_password
    if not password or await store.count_users():
        return False
    username = settings.bootstrap_admin_username.strip().lower()
    problems = password_problems(password, username, settings.password_min_length)
    if problems:
        log.error("HUB_BOOTSTRAP_ADMIN_PASSWORD refused (%s): no default administrator was "
                  "created", "; ".join(problems))
        return False
    user = await store.create_user(username, "Administrator", hash_password(password),
                                   must_change_password=True)
    await store.grant_role(user.user_id, "admin", None, None, None)
    org_id = settings.bootstrap_maker_org
    try:
        await store.platform.create_organization(org_id, settings.bootstrap_maker_name,
                                                 "manufacturer")
    except PlatformError:
        pass                                          # it exists already
    await store.grant_role(user.user_id, "manufacturer_admin", None, None, None, org_id=org_id)
    home = await store.accounts.ensure_personal_org(user, "Administrator")
    await store.add_auth_audit("user_created", username, user_id=user.user_id,
                               detail={"via": "bootstrap", "roles": ["admin"],
                                       "maker_org": org_id, "home": home})
    log.warning("default administrator %r created: sign in at /, /maker/ and /app/ and set a new "
                "password (it is required)", username)
    return True
