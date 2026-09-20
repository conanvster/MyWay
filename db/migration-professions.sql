-- Професія, відкриті приховані гілки й рахунок убитих (П-224).
--
-- Без цих трьох стовпців PostgREST відповідає на запис персонажа
-- кодом 400 («column ... does not exist»), і персонаж НЕ зберігається
-- взагалі — не лише професія, а весь рядок.
--
-- Ставити так (з домашнього каталогу файл не читається — див. HOW-TO-RUN):
--     sudo -u postgres psql -d myway < db/migration-professions.sql

ALTER TABLE game.characters
    ADD COLUMN IF NOT EXISTS profession text   NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS opened     jsonb  NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS kills      jsonb  NOT NULL DEFAULT '{}'::jsonb;

GRANT SELECT, INSERT, UPDATE ON game.characters TO game_anon;

-- PostgREST тримає схему в пам'яті — після зміни таблиці її треба
-- перечитати. Або цим рядком, або просто перезапустити PostgREST.
NOTIFY pgrst, 'reload schema';
