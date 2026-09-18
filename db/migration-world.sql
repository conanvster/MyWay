-- Персонажі розділені по світах (П-204, слово замовника 19.09.2026).
--
-- Було: `characters.name` — первинний ключ на всю гру, стовпця «світ»
-- немає, і `game.login()` віддавав усі персонажі акаунта без огляду на
-- те, у якому світі стоїть сервер. Через це персонаж, збережений у
-- світі 2 (координата -1748 м), потрапляв у перелік світу 600 м і
-- з'являвся поза картою.
--
-- Стало: логін і пароль одні на обидва світи, персонажі — свої в
-- кожному. Ім'я унікальне В МЕЖАХ СВІТУ (слово замовника): той самий
-- «Ork» може бути і тут, і там, як на окремих серверах L2.
--
-- Світ називається іменем свого файлу даних — `map.json` чи
-- `map2.json`. Це не нова назва, а та сама, якою світ уже зветься в
-- коді (`GameData.map_path()`), у мітці готовності сервера й у звірці
-- `client_which_world`: другої схеми найменування, яку довелось би
-- тримати узгодженою руками, тут свідомо не заводиться.
--
-- Ставити так (з каталогу проєкту; саме `<`, а не `-f` — домашній
-- каталог користувачеві `postgres` закритий, див. db/HOW-TO-RUN.md):
--     sudo -u postgres psql -d myway < db/migration-world.sql

ALTER TABLE game.characters
    ADD COLUMN IF NOT EXISTS world text NOT NULL DEFAULT 'map.json';

-- Слово замовника: усіх, хто вже є, — у світ 2. Саме там вони й грали.
UPDATE game.characters SET world = 'map2.json';

-- Ім'я унікальне в межах світу, а не на всю гру.
ALTER TABLE game.characters DROP CONSTRAINT IF EXISTS characters_pkey;
ALTER TABLE game.characters ADD PRIMARY KEY (name, world);

-- ── увійти: перелік лише того світу, у якому стоїть сервер ────────────
-- Стара функція саме ВИДАЛЯЄТЬСЯ, а не заміщається: CREATE OR REPLACE з
-- іншим набором аргументів зробив би другу, і PostgREST обирав би між
-- ними за ключами тіла запиту — тобто мовчки й непередбачувано.
DROP FUNCTION IF EXISTS game.login(text, text);

CREATE OR REPLACE FUNCTION game.login(login text, password text, world text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    kept text;
    list jsonb;
BEGIN
    SELECT a.secret INTO kept FROM game.accounts a WHERE a.login = login.login;
    IF kept IS NULL OR kept <> crypt(login.password, kept) THEN
        -- Одна відповідь на обидва випадки: інакше можна перебирати логіни.
        RETURN jsonb_build_object('ok', false, 'why', 'невірний акаунт або пароль');
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object(
               'name', c.name, 'level', c.level, 'race', c.race,
               'sex', c.sex)), '[]'::jsonb)
        INTO list
        FROM game.characters c
        WHERE c.account = login.login AND c.world = login.world;
    RETURN jsonb_build_object('ok', true, 'characters', list);
END
$$;

-- ── створити персонажа: у тому світі, де стоїть сервер ────────────────
DROP FUNCTION IF EXISTS game.new_character(text, text, text, text, text);

CREATE OR REPLACE FUNCTION game.new_character(
    login text, password text, name text, race text, sex text, world text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    kept text;
BEGIN
    SELECT a.secret INTO kept FROM game.accounts a WHERE a.login = new_character.login;
    IF kept IS NULL OR kept <> crypt(new_character.password, kept) THEN
        RETURN jsonb_build_object('ok', false, 'why', 'невірний акаунт або пароль');
    END IF;
    IF EXISTS (SELECT 1 FROM game.characters c
               WHERE c.name = new_character.name
                 AND c.world = new_character.world) THEN
        RETURN jsonb_build_object('ok', false, 'why', 'таке ім’я вже зайняте');
    END IF;
    INSERT INTO game.characters (name, account, race, sex, world)
        VALUES (new_character.name, new_character.login,
                new_character.race, new_character.sex, new_character.world);
    RETURN jsonb_build_object('ok', true);
END
$$;

REVOKE ALL ON FUNCTION game.login(text, text, text) FROM public;
REVOKE ALL ON FUNCTION game.new_character(text, text, text, text, text, text) FROM public;
GRANT EXECUTE ON FUNCTION game.login(text, text, text) TO game_anon;
GRANT EXECUTE ON FUNCTION game.new_character(text, text, text, text, text, text) TO game_anon;

NOTIFY pgrst, 'reload schema';
