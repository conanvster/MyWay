-- Крок 5: акаунти й кілька персонажів на акаунт (П-12, П-13).
--
-- Пароль НЕ доходить до гри в чистому вигляді далі за одну функцію:
-- перевірка робиться в самому Postgres, і назовні через PostgREST видно
-- лише «увійшов / не увійшов» і перелік персонажів.
--
-- Про argon2, який названий у П-13: у Postgres його немає без окремого
-- розширення (pgsodium чи argon2), а вони не в кожному сховищі. Тут
-- узято **bcrypt** із pgcrypto — він у сховищах є, і це теж повільна
-- функція, задумана саме для паролів. Якщо потрібен саме argon2 —
-- скажи, і я перепишу під pgsodium.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS game.accounts (
    login      text PRIMARY KEY,
    secret     text NOT NULL,          -- bcrypt-хеш, не пароль
    created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE game.characters
    ADD COLUMN IF NOT EXISTS account text REFERENCES game.accounts(login);

-- ── завести акаунт ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION game.register(login text, password text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF length(password) < 6 THEN
        RETURN jsonb_build_object('ok', false, 'why', 'пароль закороткий');
    END IF;
    IF EXISTS (SELECT 1 FROM game.accounts a WHERE a.login = register.login) THEN
        RETURN jsonb_build_object('ok', false, 'why', 'такий акаунт уже є');
    END IF;
    INSERT INTO game.accounts (login, secret)
        VALUES (register.login, crypt(register.password, gen_salt('bf', 10)));
    RETURN jsonb_build_object('ok', true, 'characters', '[]'::jsonb);
END
$$;

-- ── увійти ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION game.login(login text, password text)
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
        FROM game.characters c WHERE c.account = login.login;
    RETURN jsonb_build_object('ok', true, 'characters', list);
END
$$;

-- ── створити персонажа на акаунті ─────────────────────────────────────
CREATE OR REPLACE FUNCTION game.new_character(
    login text, password text, name text, race text, sex text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    kept text;
BEGIN
    SELECT a.secret INTO kept FROM game.accounts a WHERE a.login = new_character.login;
    IF kept IS NULL OR kept <> crypt(new_character.password, kept) THEN
        RETURN jsonb_build_object('ok', false, 'why', 'невірний акаунт або пароль');
    END IF;
    IF EXISTS (SELECT 1 FROM game.characters c WHERE c.name = new_character.name) THEN
        RETURN jsonb_build_object('ok', false, 'why', 'таке ім’я вже зайняте');
    END IF;
    INSERT INTO game.characters (name, account, race, sex)
        VALUES (new_character.name, new_character.login,
                new_character.race, new_character.sex);
    RETURN jsonb_build_object('ok', true);
END
$$;

REVOKE ALL ON FUNCTION game.register(text, text) FROM public;
REVOKE ALL ON FUNCTION game.login(text, text) FROM public;
REVOKE ALL ON FUNCTION game.new_character(text, text, text, text, text) FROM public;
GRANT EXECUTE ON FUNCTION game.register(text, text) TO game_anon;
GRANT EXECUTE ON FUNCTION game.login(text, text) TO game_anon;
GRANT EXECUTE ON FUNCTION game.new_character(text, text, text, text, text) TO game_anon;

NOTIFY pgrst, 'reload schema';
