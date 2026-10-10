\set ON_ERROR_STOP on
-- Завдання переходу, взяте в майстра гільдії (П-227, 10.10.2026).
--
-- {"професія": ключ, "від": скільки вбито на мить, коли взяв} — лічильник
-- «убито|10» рахується від цього числа. Без стовпця PostgREST відкидає
-- ВЕСЬ рядок персонажа кодом 400; `Store` це переживе, але завдання
-- після перезаходу почнеться наново.
--
-- Ставити так (з домашнього каталогу файл не читається — див. HOW-TO-RUN):
--     sudo -u postgres psql -d myway < db/migration-quest.sql

ALTER TABLE game.characters
    ADD COLUMN IF NOT EXISTS quest jsonb NOT NULL DEFAULT '{}'::jsonb;

GRANT SELECT, INSERT, UPDATE ON game.characters TO game_anon;

-- PostgREST тримає схему в пам'яті — перечитати.
NOTIFY pgrst, 'reload schema';

\echo 'Done!'
