# hse_db_2

## Dependencies

* `psql`
* `jq`
* `jg`

## Run

```sh
docker-compose up -d
```
> [#1] and [#3] can be done with:
> ```sh
> psql --host=localhost --port=5432 -f create_tables.sql hse_db hse_user
> ./fill_tables.sh
> ```

## 1

> Создать базу данных, спроектированную в ходе выполнения предыдущей практической
> работы, в любой SQL среде

```sh
psql --host=localhost hse_user hse_user
```

```sql
CREATE DATABASE hse_db;
```

```sh
psql --host=localhost hse_db hse_user
```

```sql
CREATE TABLE IF NOT EXISTS cities (
  id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(40)
);

CREATE TABLE IF NOT EXISTS authors (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  last_name VARCHAR(40)
);

CREATE TABLE IF NOT EXISTS theaters (
  id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name    VARCHAR(40),
  city_id UUID NOT NULL REFERENCES cities(id)
);

CREATE TABLE IF NOT EXISTS actors (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  first_name VARCHAR(40),
  last_name  VARCHAR(40),
  city_id    UUID NOT NULL REFERENCES cities(id)
);

CREATE TABLE IF NOT EXISTS plays (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       VARCHAR(40) NOT NULL,
  author_id  UUID NOT NULL REFERENCES authors(id),
  theater_id UUID NOT NULL REFERENCES theaters(id)
);

CREATE TABLE IF NOT EXISTS plays_actors (
  play_id  UUID NOT NULL REFERENCES plays(id),
  actor_id UUID NOT NULL REFERENCES actors(id),
  lead     BOOLEAN DEFAULT false,

  PRIMARY KEY (play_id, actor_id)
);
```

## 3

> Импортировать и экспортировать данные в созданную базу с использованием средств языка SQL

```sh
# cat ./fill_tables.sh
#!/bin/sh -e

set -o pipefail

PG_HOST=localhost
PG_PORT=5432
PG_DB=hse_db
PG_USER=hse_user

pg_cmd() {
  local cmd=$1
  docker-compose exec -T pg psql --host=${PG_HOST} --port=${PG_PORT} --command="${cmd}" ${PG_DB} ${PG_USER}
}

jg --stream 100 city.yaml --files cities=data/cities.txt \
  | jq . --raw-output \
  | pg_cmd 'COPY cities(name) FROM STDIN'
CITY_IDS=$(mktemp)
pg_cmd 'COPY cities(id) TO STDOUT' > ${CITY_IDS}

jg --stream 100 author.yaml --files last_names=data/last_names.txt \
  | jq . --raw-output \
  | pg_cmd 'COPY authors(last_name) FROM STDIN'
AUTHOR_IDS=$(mktemp)
pg_cmd 'COPY authors(id) TO STDOUT' > ${AUTHOR_IDS}

cp ${CITY_IDS} city_ids.txt

jg --stream 1000 theater.yaml --files names=data/theater_names.txt,city_ids=${CITY_IDS} \
  | tee theaters_prepares.json \
  | jq '[.name, .city_id] | join("\t")' --raw-output \
  | tee theaters_prepared.txt \
  | pg_cmd 'COPY theaters(name, city_id) FROM STDIN'
THEATER_IDS=$(mktemp)
pg_cmd 'COPY theaters(id) TO STDOUT' > ${THEATER_IDS}

jg --stream 10000 actor.yaml --files first_names=data/first_names.txt,last_names=data/last_names.txt,city_ids=${CITY_IDS} \
  | jq '[.first_name, .last_name, .city_id] | join("\t")' --raw-output \
  | pg_cmd 'COPY actors(first_name, last_name, city_id) FROM STDIN'
ACTOR_IDS=$(mktemp)
pg_cmd 'COPY actors(id) TO STDOUT' > ${ACTOR_IDS}

jg --stream 5000 play.yaml --files names=data/play_names.txt,author_ids=${AUTHOR_IDS},theater_ids=${THEATER_IDS} \
  | jq '[.name, .author_id, .theater_id] | join("\t")' --raw-output \
  | pg_cmd 'COPY plays(name, author_id, theater_id) FROM STDIN'
PLAY_IDS=$(mktemp)
pg_cmd 'COPY plays(id) TO STDOUT' > ${PLAY_IDS}

# not effective, but i have no time to do it well
IFS=$'\n'
cat ${PLAY_IDS} | while read -r play_id; do
  jg --array 1,20 play_actor.yaml --files actor_ids=${ACTOR_IDS} \
    | jq "unique | (.[:length/5 | ceil][] | [\"${play_id}\", ., true]), (.[length/5 | ceil:][] | [\"${play_id}\", ., false]) | join(\"\t\")" --raw-output
done | pg_cmd 'COPY plays_actors(play_id, actor_id, lead) FROM STDIN'
```

## 4

> Сформировать запросы к построенной базе данных информационной системы в
> соответствии с выбранной моделью и заданием №2 предыдущей практической работы

### 1
Получить список ведущих артистов всех театров
```sql
SELECT DISTINCT
  A.id AS id,
  A.first_name AS first_name,
  A.last_name AS last_name
FROM actors AS A
INNER JOIN plays_actors AS PA
  ON PA.actor_id = A.id
WHERE PA.lead;
```

### 2
Получить список спектаклей, в которых занят заданный артист
```sql
SELECT
  P.id AS play_id,
  P.name AS play_name,
  T.id AS theater_id,
  T.name AS theater_name
FROM plays AS P
INNER JOIN theaters AS T
  ON T.id = P.theater_id
INNER JOIN plays_actors AS PA
  ON PA.play_id = P.id
WHERE PA.actor_id = ?;
```

### 3
Получить список театров, в которых играют однофамильцы
```sql
SELECT
  T.id AS id,
  T.name AS name
FROM theaters AS T
INNER JOIN plays AS P
  ON P.theater_id = T.id
INNER JOIN plays_actors AS PA
  ON PA.play_id = P.id
INNER JOIN actors AS A
  ON A.id = PA.actor_id
GROUP BY (T.id, T.name, A.last_name)
HAVING count(*) >= 2;
```

### 4
Получить пары (название театра, город), в котором идут те же спектакли,
что и спектакль, в котором занят заданный артист
```sql
SELECT
  T.name AS theater_name,
  C.name AS city_name
FROM theaters AS T
INNER JOIN cities AS C
  ON C.id = T.city_id
INNER JOIN plays AS P
  ON P.theater_id = T.id
WHERE P.name IN (
  SELECT P.name
  FROM plays AS P
  INNER JOIN plays_actors AS PA
    ON PA.play_id = P.id
  WHERE PA.actor_id = ?
);
```

### 5
Получить список спектаклей, в которых участвуют артисты, живущие в том же городе, что и театр
```sql
SELECT DISTINCT
  P.id,
  P.name
FROM plays AS P
INNER JOIN theaters AS T
  ON T.id = P.theater_id
INNER JOIN plays_actors AS PA
  ON PA.play_id = P.id
INNER JOIN actors AS A
  ON A.id = PA.actor_id
WHERE A.city_id = T.city_id;
```

### 6
Получить пары (название театра, спектакль), в которых играют артисты с той же фамилией, что и автор пьесы

```sql
SELECT DISTINCT
  T.name AS theater_name,
  P.name AS play_name
FROM plays AS P
INNER JOIN theaters AS T
  ON T.id = P.theater_id
INNER JOIN plays_actors AS PA
  ON PA.play_id = P.id
INNER JOIN actors AS A
  ON A.id = PA.actor_id
INNER JOIN authors AS AU
  ON AU.id = P.author_id
WHERE A.last_name = AU.last_name;
```

## 5

> Создать хранимую процедуру по внесению новой записи в любое отношение

```sql
CREATE OR REPLACE PROCEDURE create_actor(
  first_name actors.first_name%TYPE,
  last_name  actors.last_name%TYPE,
  city_name  cities.name%TYPE
) LANGUAGE SQL AS $$
INSERT INTO actors (
  first_name,
  last_name,
  city_id
) VALUES (first_name, last_name, (
  SELECT id
  FROM cities
  WHERE name = city_name
  LIMIT 1;
))
$$;
```

## 6

> Создать набор пользователей БД и разграничение прав доступа к объектам БД для разных
> пользователей (минимально 3 пользователя с разными правами)

```sql
CREATE ROLE root WITH
  LOGIN
  SUPERUSER
  PASSWORD 'root';

CREATE ROLE admin WITH
  LOGIN
  PASSWORD 'admin';
GRANT ALL PRIVILEGES
ON
  cities,
  authors,
  theaters,
  actors,
  plays,
  plays_actors
TO admin;

CREATE ROLE viewer WITH
  LOGIN
  PASSWORD 'viewer';
GRANT SELECT
ON
  cities,
  authors,
  theaters,
  actors,
  plays,
  plays_actors
TO viewer;
```

## 7

> Настроить шифрование любого атрибута. Создать представление, возвращающее данные в
> расшифрованном виде. Предусмотреть ограниченный доступ к этому представлению

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE actors
ALTER COLUMN first_name TYPE bytea USING pgp_sym_encrypt(first_name, 'mysecretkey');

CREATE OR REPLACE VIEW actors_view (
  id,
  first_name,
  last_name,
  city_id
) AS SELECT
  id,
  pgp_sym_decrypt(first_name, 'mysecretkey'),
  last_name,
  city_id
FROM actors;

CREATE OR REPLACE PROCEDURE create_actor(
  first_name actors.first_name%TYPE,
  last_name  actors.last_name%TYPE,
  city_name  cities.name%TYPE
) LANGUAGE SQL AS $$
INSERT INTO actors (
  first_name,
  last_name,
  city_id
) VALUES (
  pgp_sym_encrypt(first_name, 'mysecretkey'),
  last_name,
  (SELECT id
    FROM cities
    WHERE name = city_name
    LIMIT 1
))

GRANT SELECT
ON actors_view
TO admin;

-- ROLE viewer still has access to definition of actors_view.
-- It production, decryption key should not be kept in database
```

## 8

> Создать резервную копию БД, удалить ее и восстановить БД по резервной копии

```sh
pg_dump --host=localhost -U root hse_db > backup.db
```

```sql
DROP DATABASE hse_db;
```

```sh
psql --host=localhost -U root hse_db < backup.db
```
