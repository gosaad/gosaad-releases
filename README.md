# GoSAAD local deployment

Run GoSAAD and PostgreSQL locally at `http://localhost:8080`.

```sh
git clone https://github.com/gosaad/gosaad-releases.git
cd gosaad-releases
cp .env.example .env
```

Edit `.env` and set the database passwords and both JWT secrets. Generate secrets with:

```sh
openssl rand -hex 32
```

Start:

```sh
docker compose up -d
docker compose ps
```

Update:

```sh
git pull --ff-only
docker compose up -d
```

Useful commands:

```sh
docker compose logs --follow gosaad-core
docker compose down
```

`docker compose up -d` pulls the current GoSAAD image. Do not use `docker compose down -v` unless you want to delete the local database.
