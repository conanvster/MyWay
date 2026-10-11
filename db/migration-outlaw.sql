\set ON_ERROR_STOP on
-- Позначка вбивці (П-87/П-261, Р-7, 11.10.2026).
--
-- {"вбивств": скільки, "згасає за": секунд гри до згасання одного} —
-- порожньо, коли не позначений. Без стовпця `Store` повторить запис без
-- нього (і скаже про це в журнал), але позначка зникатиме з перезаходом.
--
-- Ставити так (з домашнього каталогу файл не читається — див. HOW-TO-RUN):
--     sudo -u postgres psql -d myway < db/migration-outlaw.sql

ALTER TABLE game.characters
    ADD COLUMN IF NOT EXISTS outlaw jsonb NOT NULL DEFAULT '{}'::jsonb;

GRANT SELECT, INSERT, UPDATE ON game.characters TO game_anon;

-- PostgREST тримає схему в пам'яті — перечитати.
NOTIFY pgrst, 'reload schema';

\echo 'Done!'
