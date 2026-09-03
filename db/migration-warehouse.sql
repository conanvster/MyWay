-- Склад: окремий на кожного персонажа, ті самі два типи речей, що й у
-- торбі (складані за кількістю, поодинокі з афіксами) — просто друга
-- пара стовпців поруч із items/things.

ALTER TABLE game.characters
    ADD COLUMN IF NOT EXISTS warehouse_items  jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS warehouse_things jsonb NOT NULL DEFAULT '[]'::jsonb;

GRANT SELECT, INSERT, UPDATE ON game.characters TO game_anon;

NOTIFY pgrst, 'reload schema';
