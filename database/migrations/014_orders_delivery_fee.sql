-- Migration 014: delivery fee informed by the store (NULL = pending). Additive; also applied by the backend
-- bootstrap (app/db/orders_schema.py). Existing orders keep NULL and their current status.
ALTER TABLE orders ADD COLUMN delivery_fee_cents INT UNSIGNED NULL AFTER subtotal_cents;
