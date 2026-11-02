-- Rollback of 0019_claim_pairing (python -m hub.storage.migrate --rollback 0019_claim_pairing).

ALTER TABLE products DROP COLUMN require_pairing;
