-- Розподілені очки статів (П-147): раніше `stat_points` рахувався й
-- зберігався, а сама витрата — сила, спритність, витривалість,
-- інтелект, чуття — ніде не жила. Один jsonb-стовпець, ключі українською,
-- як і скрізь у даних.

ALTER TABLE game.characters
    ADD COLUMN IF NOT EXISTS stats jsonb NOT NULL DEFAULT '{}'::jsonb;

GRANT SELECT, INSERT, UPDATE ON game.characters TO game_anon;

NOTIFY pgrst, 'reload schema';
