-- Крок 4 додав речі: поодинокі (з афіксами) і те, що вдягнене.
--
-- Без цих двох стовпців PostgREST відповідає 400, і сервер каже про це
-- вголос: «[база] ‼ запис Вовкодав не вдався, код 400». Саме так ваду й
-- знайшли — на живому прогоні, а не в коді.

ALTER TABLE game.characters
    ADD COLUMN IF NOT EXISTS things jsonb NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS gear   jsonb NOT NULL DEFAULT '{}'::jsonb;

GRANT SELECT, INSERT, UPDATE ON game.characters TO game_anon;

-- PostgREST тримає схему в пам'яті — після зміни таблиці її треба
-- перечитати. Або цим рядком, або просто перезапустити PostgREST.
NOTIFY pgrst, 'reload schema';
