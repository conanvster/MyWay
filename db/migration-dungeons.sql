-- Строк підземель і штраф світу переживають перезапуск сервера
-- (П-153, Ф7).
--
-- Було: відкриті підземелля й активовані святині жили лише в пам'яті
-- сервера. Перезапуск — і святиня знову «під охороною», підземелля
-- немає, а ключ, витрачений на активацію, пропав.
--
-- Стало: запис з'являється на активації святині (шаблону ще немає —
-- підземелля будує перший вхід), шаблон і зерно дописуються першим
-- входом. Строк — від активації. Минув — запис видаляється, і на світ
-- падає штраф, що теж зберігається, доки не мине.
--
-- Час — секунди Unix цілим числом (`bigint`): рядки часу з поясами
-- PostgREST і Godot розбирають по-різному, а число — ні. Стовпець
-- `made` — лише для людини, що дивиться в таблицю.
--
-- Ставити так (з каталогу проєкту; саме `<`, а не `-f` — домашній
-- каталог користувачеві `postgres` закритий, див. db/HOW-TO-RUN.md):
--     sudo -u postgres psql -d myway < db/migration-dungeons.sql

CREATE TABLE IF NOT EXISTS game.dungeons (
    world     text    NOT NULL,
    shrine    integer NOT NULL,
    grade     text    NOT NULL,
    template  text    NOT NULL DEFAULT '',
    seed      bigint  NOT NULL DEFAULT 0,
    opened_at bigint  NOT NULL,
    closes_at bigint  NOT NULL,
    made      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (world, shrine)
);

CREATE TABLE IF NOT EXISTS game.world_penalties (
    world  text    NOT NULL,
    shrine integer NOT NULL,
    until  bigint  NOT NULL,
    made   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (world, shrine, until)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON game.dungeons TO game_anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON game.world_penalties TO game_anon;

NOTIFY pgrst, 'reload schema';
