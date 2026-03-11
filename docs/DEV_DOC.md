# Developer Documentation — Inception

## Prerequisites

Install the following tools before setting up the project:

| Tool | Minimum version | Check |
|------|----------------|-------|
| Docker Engine | 24.x | `docker --version` |
| Docker Compose v2 | 2.x | `docker compose version` |
| GNU Make | 4.x | `make --version` |
| OpenSSL | 3.x | `openssl version` |
| Git | 2.x | `git --version` |

> On 42 school machines all tools are pre-installed.

---

## First-Time Setup

### 1. Clone the repository

```bash
git clone <repo-url> 42_Inception
cd 42_Inception
```

### 2. Create `srcs/.env`

Copy the template and fill in every credential before running `make`:

```bash
cp srcs/.env.example srcs/.env
$EDITOR srcs/.env
```

The file is **never committed** (covered by `.gitignore`).

### 3. Review `srcs/.env`

`srcs/.env` holds all configuration — both non-sensitive settings and credentials:

| Variable | Example value | Purpose |
|----------|--------------|---------|
| `DOMAIN_NAME` | `login.42.fr` | WordPress site URL and nginx server name |
| `DATA_PATH` | `/home/<login>/data` | Host path for persistent volume data |
| `WP_DATABASE` | `wordpress` | WordPress database name |
| `WP_USER` | `wp_user` | WordPress database username |
| `WP_HOST` | `mariadb` | Database hostname (must match container name) |
| `FTP_USER` | `ftpuser` | FTP username *(bonus)* |
| `WP_REDIS_HOST` | `redis` | Redis hostname for WordPress object cache *(bonus)* |
| `DB_PASSWORD` | *(your choice)* | MariaDB password for the WordPress user |
| `DB_ROOT_PASSWORD` | *(your choice)* | MariaDB root password |
| `WP_ADMIN_USER` | *(your choice)* | WordPress admin login (must NOT be `admin`/`administrator`) |
| `WP_ADMIN_PASS` | *(your choice)* | WordPress admin password |
| `WP_EDITOR` | *(your choice)* | WordPress editor username |
| `WP_EDITOR_PASS` | *(your choice)* | WordPress editor password |
| `FTP_PASSWORD` | *(your choice)* | FTP user password *(bonus)* |

Adjust `DATA_PATH` and `DOMAIN_NAME` to match your machine and login.

### 4. Add the domain to `/etc/hosts`

```bash
echo "127.0.0.1   umeneses.42.fr" | sudo tee -a /etc/hosts
```

Verify:

```bash
getent hosts umeneses.42.fr
# Expected: 127.0.0.1   umeneses.42.fr
```

---

## Build and Launch

All commands run from the **repository root**.

### Start the full stack

```bash
make
```

What happens:
1. `dirs` target creates `${DATA_PATH}/wordpress` and `${DATA_PATH}/mariadb` on the host
2. `docker compose up -d --build --wait` builds all images and starts containers, waiting until healthy
3. WordPress installs itself on first boot: downloads core, creates DB tables, creates admin and editor users
4. The nginx entrypoint auto-generates a self-signed TLS certificate on first start (no manual step needed)

Typical first-boot time: **30–60 seconds** for mandatory (`make`); **2–4 minutes** for bonus (`make bonus`) since plugins and themes are downloaded at runtime.

### Check that everything started

```bash
make ps
# or
docker compose -f srcs/docker-compose.yml ps
```

All containers should show `Up`.

### View logs

```bash
make logs              # tail all services
docker compose -f srcs/docker-compose.yml logs wordpress   # single service
docker compose -f srcs/docker-compose.yml logs -f nginx    # follow nginx
```

---

## Container Management

### Open a shell inside a container

```bash
docker exec -it wordpress sh
docker exec -it mariadb sh
docker exec -it nginx sh
```

### Run a WP-CLI command

```bash
docker exec wordpress wp <command> --path=/var/www/html --allow-root
```

Examples:

```bash
# List active plugins
docker exec wordpress wp plugin list --path=/var/www/html --allow-root --status=active

# Check Redis cache status (bonus)
docker exec wordpress wp redis status --path=/var/www/html --allow-root

# List WordPress users
docker exec wordpress wp user list --path=/var/www/html --allow-root
```

### Query MariaDB directly

```bash
source srcs/.env
docker exec mariadb mysql -uroot -p"${DB_ROOT_PASSWORD}" \
    --socket=/run/mysqld/mysqld.sock wordpress -e "SHOW TABLES;"
```

### Restart a single service

```bash
docker compose -f srcs/docker-compose.yml restart wordpress
```

### Inspect a container

```bash
docker inspect wordpress
docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' nginx
```

---

## Volume Management

### Where data is stored

All persistent data lives on the host at the path set by `DATA_PATH` in `srcs/.env`:

| Host path | Container path | Contents |
|-----------|---------------|----------|
| `${DATA_PATH}/wordpress` | `/var/www/html` (wordpress, nginx, ftp) | WordPress core files, themes, plugins, uploads |
| `${DATA_PATH}/mariadb` | `/var/lib/mysql` (mariadb) | MariaDB database files |

Default `DATA_PATH=/home/biralavor/data`, so data lives at:
- `/home/biralavor/data/wordpress`
- `/home/biralavor/data/mariadb`

### How persistence works

Volumes are **named Docker volumes** backed by bind mounts (`driver: local`, `type: none`). This makes them visible to `docker volume ls` and `docker volume inspect` while still storing data at a controlled host path:

```yaml
volumes:
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/wordpress

  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/mariadb
```

The host directories must exist before `docker compose up` — the `dirs` Makefile target handles this with `mkdir -p`.

Stopping containers (`make down`) does **not** delete data — only `make fclean` wipes the host directories.

### Reset data without removing images

```bash
make clean                                     # stop containers
sudo rm -rf ${DATA_PATH}/wordpress ${DATA_PATH}/mariadb   # wipe data only
make                                           # restart — WordPress reinstalls
```

### Inspect volumes

```bash
docker volume ls
docker volume inspect inception_wordpress_data
docker inspect wordpress --format '{{json .Mounts}}' | python3 -m json.tool
```

---

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │            inception_network             │
                        │                (bridge)                  │
  Host port 443 ──────► │  nginx ──► wordpress (9000) ──► mariadb  │
                        │               │                  (3306)  │
  Host port 8080 ──────►│  adminer ─────┘                          │
  Host port 8888 ──────►│  static                                  │
  Host port 21   ──────►│  ftp (shares wordpress volume)           │
                        │  redis (6379, internal only)             │
                        └─────────────────────────────────────────┘
```

- **nginx** is the sole TLS termination point. All public traffic enters on port 443.
- **wordpress** is never directly exposed — nginx proxies requests to it on port 9000.
- **mariadb** and **redis** are internal-only: no host ports.
- **ftp**, **adminer**, and **static** are bonus services with their own exposed ports.
- All containers share `inception_network` (custom bridge). Docker DNS resolves container names (e.g. `mariadb`, `redis`) automatically.

---

## Adding a Bonus Service

Bonus services live under `srcs/bonus/<service>/` and are gated behind the `bonus` Docker Compose profile. They only start when `make bonus` is run — plain `make` never starts them.

**Step-by-step pattern:**

1. Create `srcs/bonus/<service>/Dockerfile` — `FROM` a pinned Alpine/Debian version, never `:latest`
2. Add the service to `srcs/docker-compose.yml` under `services:` with **all four of these**:
   ```yaml
     <service>:
       build:
         context: ./bonus/<service>
         dockerfile: Dockerfile
       image: <service>_bonus        # avoid colliding with official DockerHub image names
       container_name: <service>
       profiles: [bonus]             # REQUIRED — prevents starting with plain `make`
       networks:
         - inception_network
       restart: unless-stopped
   ```
3. Add only the ports the service actually needs — or none if it is internal-only
4. If it needs a volume, declare it under `volumes:` and mount it; if the data is ephemeral, omit the volume
5. If it needs credentials, add a variable to `srcs/.env` — never hardcode passwords in Dockerfiles or `docker-compose.yml`
6. If it installs WordPress plugins/themes, add the install commands inside the `BONUS_SETUP` block in `srcs/requirements/wordpress/tools/entrypoint.sh` (gated on `[ "${BONUS_SETUP:-false}" = "true" ]`)
7. Rebuild and verify with `make fclean && make bonus`

> **Why `profiles: [bonus]` matters:** without it the service starts with plain `make`, collapsing the mandatory/bonus separation. Every bonus service must carry this key.

---

## Accessing Bonus Services

All bonus services start with `make bonus`. Run from the **repository root**.

### Redis — Object Cache (internal only)

Redis has no exposed host port. Verify it is running and the WordPress cache is connected:

```bash
# Ping the Redis server
docker exec redis redis-cli PING
# Expected: PONG

# Check WordPress Redis cache status via WP-CLI
docker exec wordpress wp redis status --path=/var/www/html --allow-root
# Expected: Status: Connected
```

Redis is used automatically by WordPress once the `redis-cache` plugin is active. No browser access needed.

### FTP — WordPress Volume Access

FTP is exposed on port **21** (passive ports 21100–21110). The FTP root maps to the WordPress web root (`/var/www/html`).

Credentials come from `srcs/.env`:

| Field    | Value                              |
|----------|------------------------------------|
| Host     | `localhost`                        |
| Port     | `21`                               |
| Username | value of `FTP_USER` in `srcs/.env` |
| Password | value of `FTP_PASSWORD` in `srcs/.env` |
| Mode     | Active or Passive                  |

Connect with any FTP client (FileZilla, `ftp`, `lftp`):

```bash
# CLI example
ftp localhost
# or
lftp -u "$FTP_USER","$FTP_PASSWORD" ftp://localhost
```

Verify the connection returns a listing of the WordPress root:

```bash
source srcs/.env
curl --silent --list-only \
    "ftp://${FTP_USER}:${FTP_PASSWORD}@localhost/" | head
```

### Adminer — MariaDB Web GUI

Adminer runs on port **8080** and provides a browser-based interface to the MariaDB database.

```
http://localhost:8080
```

Fill in the login form with these values:

| Field    | Value                                          |
|----------|------------------------------------------------|
| System   | MySQL                                          |
| Server   | `mariadb`                                      |
| Username | value of `WP_USER` in `srcs/.env`              |
| Password | value of `DB_PASSWORD` in `srcs/.env`          |
| Database | value of `WP_DATABASE` in `srcs/.env`          |

> `mariadb` resolves to the container IP via Docker DNS — both Adminer and MariaDB share `inception_network`.

Verify from the CLI:

```bash
curl -s http://localhost:8080/ | grep -i adminer
# Expected: HTML output containing "Adminer"
```

### Static Site — Showcase Page

The static site is a plain HTML/CSS page served on port **8888**. No authentication required.

```
http://localhost:8888
```

Verify from the CLI:

```bash
curl -s http://localhost:8888/ | grep -i "<title>"
```

---

## Modifying a Service Port

Each service falls into one of two categories:

| Category | Services | Where the port is declared |
|----------|----------|---------------------------|
| **Host-exposed** | nginx (443), ftp (21, 21100-21110), adminer (8080), static (8888) | `ports:` in `docker-compose.yml` |
| **Internal-only** | wordpress (9000), mariadb (3306), redis (6379) | App config only — no `ports:` entry |

Changing a port is a two-step operation: update the app config **and** every consumer that connects to it.

---

### nginx — change the HTTPS port (default: 443)

nginx is the only service the subject mandates on 443. Changing it breaks the 42 requirement, but for local dev:

1. `srcs/requirements/nginx/conf/wordpress.conf.template` — update `listen 443 ssl` to the new port
2. `srcs/docker-compose.yml` — change `"443:443"` to `"<new>:<new>"` under `nginx`
3. Rebuild: `make re`

---

### wordpress (php-fpm) — change the internal port (default: 9000)

php-fpm and nginx must agree on the same port.

1. `srcs/requirements/wordpress/conf/www.conf` — change `listen = 0.0.0.0:9000` to the new port
2. `srcs/requirements/nginx/conf/wordpress.conf.template` — change `"wordpress:9000"` in `set $wp_backend`
3. No `ports:` entry to touch (internal-only)
4. Rebuild: `make re`

---

### mariadb — change the internal port (default: 3306)

1. Add `--port=<new>` to the `mysqld` startup args in `srcs/requirements/mariadb/tools/entrypoint.sh`
2. Update `WP_HOST` in `srcs/.env` if you also embed the port, **or** set `DB_PORT=<new>` and pass it to `wp config set` in the WordPress entrypoint
3. No `ports:` entry to touch (internal-only)
4. Rebuild: `make re`

> Changing the MariaDB port is rarely needed — WordPress connects by hostname (`WP_HOST=mariadb`) and Docker DNS handles resolution. The port only matters if you expose it to the host for external tools.

---

### redis — change the internal port (default: 6379)

1. `srcs/bonus/redis/conf/redis.conf` (or entrypoint) — set `port <new>`
2. Add `WP_REDIS_PORT=<new>` to `srcs/.env` and pass it to `wp config set WP_REDIS_PORT` in the WordPress entrypoint
3. No `ports:` entry to touch (internal-only)
4. Rebuild: `make fclean && make bonus`

---

### adminer — change the host port (default: 8080)

1. `srcs/docker-compose.yml` — change `"8080:8080"` to `"<new>:8080"` (left side = host port)
2. No app config change needed — the container still listens on 8080 internally
3. Rebuild: `make fclean && make bonus`

---

### static site — change the host port (default: 8888)

1. `srcs/docker-compose.yml` — change `"8888:8888"` to `"<new>:<new>"`
2. If the static site's nginx config has a hardcoded `listen 8888`, update it in `srcs/bonus/static/conf/`
3. Rebuild: `make fclean && make bonus`

---

### FTP — change the control or passive ports (default: 21, 21100–21110)

FTP requires both the control port and the passive range to match between the server config and the host mapping.

1. `srcs/bonus/ftp/tools/entrypoint.sh` or vsftpd config — update `listen_port` and `pasv_min_port`/`pasv_max_port`
2. `srcs/docker-compose.yml` — update `"21:21"` and `"21100-21110:21100-21110"` accordingly
3. Rebuild: `make fclean && make bonus`

---

### Verify after any port change

```bash
# Confirm the container is listening on the new port
docker exec <container> ss -tlnp

# Confirm the host mapping
docker compose -f srcs/docker-compose.yml ps

# Run the full health check
make check
```

---

## Running the Health Check

```bash
make check
```

Saves a colour-stripped report to `release.txt`. Exit code `0` = all checks passed.

For interactive coloured output:

```bash
bash InceptionHealthCheck.sh
```
