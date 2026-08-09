# Trippy

A simple, self-hosted trip tracker. Post updates from the road with photos and
locations; anyone you share the trip with can follow along on a map, no
account required.

- **Adventurers** (invite-only accounts, promoted by an admin) create trips
  and log entries with photos. Location and date are read automatically from
  each photo's EXIF data, or set manually.
- **Trips** are public (listed on the homepage) or private (unlocked with a
  32-character code, shareable as a link — no login needed to view).
- **Viewers** can create a free account to comment and react with emoji on
  entries.
- Two adventurers can collaborate on the same trip; entries and photos are
  tagged with who created/uploaded them.

## Running with Docker Compose

1. Copy `.env.example` to `.env` and set `SECRET_KEY_BASE`:

   ```sh
   cp .env.example .env
   echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" >> .env
   ```

2. Start it:

   ```sh
   docker compose up -d --build
   ```

3. Visit `http://localhost:3003` and sign up — **the first account created
   becomes the admin** and an adventurer automatically. Use the admin panel
   (top right, once signed in) to grant adventurer access to other users by
   username; everyone else who signs up is a viewer who can comment/react.

The SQLite databases and uploaded photos are stored in the `trippy_storage`
Docker volume, so they persist across restarts and rebuilds.

## Reverse proxy network
use `reverse-proxy` network to connect trippy to your caddy reverse proxy

## Local development (without Docker)

Requires Ruby 3.4 and Node is not needed (Tailwind builds via a standalone
binary).

```sh
bin/setup
bin/dev
```

`bin/dev` runs the Rails server and the Tailwind watcher together.
