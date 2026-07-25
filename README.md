# GoSAAD deployment

This repository runs a published GoSAAD container image with PostgreSQL and Caddy. Caddy terminates HTTPS and forwards requests to the application. PostgreSQL and application runtime data use named Docker volumes and are not exposed publicly.

## Prerequisites

- A server with Docker Engine and Docker Compose v2.
- A DNS `A`/`AAAA` record for the chosen hostname pointing to the server.
- Ports 80 and 443 reachable from the Internet.
- Access to the GoSAAD image package. While the package is private, authenticate Docker with a GitHub token that has `read:packages`:

  ```sh
  printf '%s' "$GHCR_TOKEN" | docker login ghcr.io --username "$GHCR_USERNAME" --password-stdin
  ```

## First deployment

```sh
git clone https://github.com/gosaad/gosaad-releases.git
cd gosaad-releases
cp .env.example .env
```

Edit `.env`: set the public hostname, email address, database passwords, and the two JWT secrets. Generate secrets with `openssl rand -hex 32`. Keep `.env` private and never commit it.

Start the deployment:

```sh
docker compose up -d
docker compose ps
```

The application will be available at `https://CADDY_DOMAIN` after Caddy receives its TLS certificate.

## Local deployment

For local use, the dedicated Compose file skips Caddy and publishes the application only on the loopback interface at `http://localhost:8080`:

```sh
docker compose -f docker-compose.local.yml up -d
docker compose -f docker-compose.local.yml ps
```

Use the same `.env` setup as production. The Caddy values in `.env` are ignored in local mode. Do not use this mode for a user-facing deployment.

## Updating

After a new image has been published as `ghcr.io/gosaad/gosaad:latest`:

```sh
git pull --ff-only
docker compose up -d
```

`pull_policy: always` makes `docker compose up -d` retrieve the current image tag before recreating services. For an explicit preflight pull, run `docker compose pull` first.

## Operations

```sh
docker compose logs --follow gosaad-core
docker compose logs --follow caddy
docker compose ps
```

Do not run `docker compose down -v` on a live deployment: it deletes the database and application runtime volumes.
