\set ON_ERROR_STOP on
-- Торба (14.11.2026): місця понад основу з data/items.json → торба —
-- за зачищені підземелля, по «за зачищене підземелля» за кожне.

ALTER TABLE game.characters
    ADD COLUMN IF NOT EXISTS bag_extra integer NOT NULL DEFAULT 0;

GRANT SELECT, INSERT, UPDATE ON game.characters TO game_anon;

NOTIFY pgrst, 'reload schema';

\echo 'Done!'
