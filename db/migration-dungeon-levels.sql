-- Рівні підземель і боси (П-153, Ф5′/Ф6, 19.09.2026): що переживає
-- перезапуск сервера, крім самого запису підземелля (migration-dungeons).
--
--   depth   — скільки рівнів у підземеллі (від сили того, хто відкрив);
--   power   — та сила: з нею вибираються шаблони глибших рівнів, тож
--             після перезапуску розклад складності той самий;
--   levels  — збудовані рівні: [{"template": …, "seed": …}, …];
--   cleared — скільки босів уже повалено (рівні вище не мають боса, а
--             прохід далі горить).
--
-- Ставити так (з каталогу проєкту):
--     sudo -u postgres psql -d myway < db/migration-dungeon-levels.sql

ALTER TABLE game.dungeons
    ADD COLUMN IF NOT EXISTS depth   integer NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS power   integer NOT NULL DEFAULT 50,
    ADD COLUMN IF NOT EXISTS levels  jsonb   NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS cleared integer NOT NULL DEFAULT 0;

NOTIFY pgrst, 'reload schema';
