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
