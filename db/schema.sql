-- Схема бази для гри. Ставиться один раз.
--
-- Назви латиною навмисно: кирилиця в SQL вимагає лапок у кожному запиті,
-- а в адресі PostgREST — ще й кодування відсотками. Українська лишається
-- там, де її читають люди.

CREATE SCHEMA IF NOT EXISTS game;

CREATE TABLE IF NOT EXISTS game.characters (
    name        text NOT NULL,
    -- Світи розділені (П-204): логін і пароль одні, персонажі свої в
    -- кожному. Світ зветься іменем свого файлу даних — тією самою
    -- назвою, якою він уже зветься в коді (`GameData.map_path()`).
    world       text NOT NULL DEFAULT 'map.json',
    level       integer NOT NULL DEFAULT 1,
    respect     integer NOT NULL DEFAULT 0,   -- дає рівні
    experience  integer NOT NULL DEFAULT 0,   -- валюта на скіли
    stat_points integer NOT NULL DEFAULT 0,
    race        text    NOT NULL DEFAULT 'людина',
    sex         text    NOT NULL DEFAULT 'чоловік',
    hp          integer NOT NULL DEFAULT 100,
    mp          integer NOT NULL DEFAULT 70,
    x           real    NOT NULL DEFAULT 0,
    y           real    NOT NULL DEFAULT 1.5,
    z           real    NOT NULL DEFAULT 0,
    skills      jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- вивчене: ключ -> рівень
    items       jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- складані: ім'я -> скільки
    things      jsonb   NOT NULL DEFAULT '[]'::jsonb,   -- поодинокі, з афіксами
    gear        jsonb   NOT NULL DEFAULT '{}'::jsonb,   -- слот -> номер у things
    saved_at    timestamptz NOT NULL DEFAULT now(),
    -- Ім'я унікальне В МЕЖАХ СВІТУ, а не на всю гру: той самий «Ork»
    -- може бути і тут, і там, як на окремих серверах L2.
    PRIMARY KEY (name, world)
);

-- Роль, під якою ходить PostgREST. Пароль замінити на свій.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'game_api') THEN
        CREATE ROLE game_api LOGIN PASSWORD 'змінити-мене';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'game_anon') THEN
        CREATE ROLE game_anon NOLOGIN;
    END IF;
END
$$;

GRANT game_anon TO game_api;
GRANT USAGE ON SCHEMA game TO game_anon;
GRANT SELECT, INSERT, UPDATE ON game.characters TO game_anon;
