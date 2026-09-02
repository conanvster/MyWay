-- Розкладка панелі — своя в кожного персонажа.
--
-- Досі панель бралась із data/bar.json і була однакова в усіх. Відколи
-- скіли можна тягнути на комірки мишею, розкладка стала власністю
-- персонажа, і мусить переживати вихід із гри.
--
-- Ставити так (з домашнього каталогу файл не читається — див. CONTEXT.md):
--     sudo -u postgres psql -d myway < db/migration-bar.sql

ALTER TABLE game.characters
    ADD COLUMN IF NOT EXISTS bar jsonb NOT NULL DEFAULT '[]'::jsonb;

GRANT SELECT, INSERT, UPDATE ON game.characters TO game_anon;

-- PostgREST тримає схему в пам'яті — після зміни таблиці її треба
-- перечитати. Або цим рядком, або просто перезапустити PostgREST.
NOTIFY pgrst, 'reload schema';
