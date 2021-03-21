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

