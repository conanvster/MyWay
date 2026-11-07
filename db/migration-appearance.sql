\set ON_ERROR_STOP on
-- Зовнішність персонажа (07.11.2026): варіант моделі, зачіска, кольори
-- волосся, очей, шкіри, губ, підводка, риси — назвами (`Appearance` у грі).
--
-- {"варіант": 1, "зачіска": "коса", "волосся": "рудий", "очі": "зелені"}.
-- Без стовпця `Store` запише рядок без нього (і скаже про це в журнал) —
-- зовнішність тоді тримається лише до перезапуску сервера.
--
--     sudo -u postgres psql -d myway < db/migration-appearance.sql

ALTER TABLE game.characters
    ADD COLUMN IF NOT EXISTS appearance jsonb NOT NULL DEFAULT '{}'::jsonb;

GRANT SELECT, INSERT, UPDATE ON game.characters TO game_anon;

-- PostgREST тримає схему в пам'яті — перечитати.
NOTIFY pgrst, 'reload schema';

\echo 'Done!'
