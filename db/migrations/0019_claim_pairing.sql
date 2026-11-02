-- 0019_claim_pairing: a product may require pairing mode before a device is claimed.
-- Rollback: db/migrations/down/0019_claim_pairing.sql.
--
-- With require_pairing, a buyer adds the device only while it is in pairing mode: the owner
-- holds the device's button, the device reports {"state": "pairing"} with its own credential,
-- and the claim code is accepted for a short window after that (backend/claims.py). A photo
-- of the label alone is then not enough to take a device. Off by default: firmware that does
-- not report pairing keeps working.

ALTER TABLE products ADD COLUMN require_pairing boolean NOT NULL DEFAULT false;
