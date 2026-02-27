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

### 2. Create secret files

These files are **never committed** (covered by `.gitignore`). Create them manually:

```bash
# WordPress admin + editor credentials
# Line 1: admin username (must NOT contain 'admin', 'Admin', 'administrator')
# Line 2: admin password
# Line 3: editor username
# Line 4: editor password
cat > secrets/credentials.txt << 'EOF'
wpmaster
StrongAdminPass42!
wreditor
StrongEditorPass42!
EOF

# MariaDB password for the WordPress user
echo "StrongDbPass42!" > secrets/db_password.txt

# MariaDB root password
echo "StrongRootPass42!" > secrets/db_root_password.txt

# FTP user password (bonus)
echo "StrongFtpPass42!" > secrets/ftp_password.txt
```

### 3. Review `srcs/.env`

The `.env` file holds non-sensitive configuration. Key variables:

| Variable | Default value | Purpose |
|----------|--------------|---------|
| `DOMAIN_NAME` | `umeneses.42.fr` | WordPress site URL and nginx server name |
| `DATA_PATH` | `/home/biralavor/data` | Host path for persistent volume data |
| `WP_DATABASE` | `wordpress` | WordPress database name |
| `WP_USER` | `wp_user` | WordPress database username |
| `WP_HOST` | `mariadb` | Database hostname (must match container name) |
| `FTP_USER` | `ftpuser` | FTP username *(bonus)* |
| `WP_REDIS_HOST` | `redis` | Redis hostname for WordPress object cache *(bonus)* |

Adjust `DATA_PATH` if your home directory differs.

### 4. Add the domain to `/etc/hosts`

```bash
echo "127.0.0.1   umeneses.42.fr" | sudo tee -a /etc/hosts
```

Verify:

```bash
getent hosts umeneses.42.fr
# Expected: 127.0.0.1   umeneses.42.fr
```

### 5. Generate a self-signed TLS certificate

Place the certificate and key in `srcs/requirements/nginx/conf/` (or wherever your nginx Dockerfile COPYs them from). Example:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout srcs/requirements/nginx/conf/umeneses.key \
    -out srcs/requirements/nginx/conf/umeneses.crt \
    -subj "/C=BR/ST=SP/L=SaoPaulo/O=42/CN=umeneses.42.fr"
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
2. `docker compose up -d --build` builds all images from their Dockerfiles and starts containers
3. WordPress installs itself on first boot (downloads core, creates DB tables, installs theme and plugins)

Typical first-boot time: **30–90 seconds** depending on network speed (WordPress core, theme, and plugins are downloaded at runtime).

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
docker exec mariadb mysql -uroot -p$(cat secrets/db_root_password.txt) \
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

Volumes are **direct bind mounts** — no named Docker volumes. Docker Engine (Linux) mounts the host directories straight into the containers:

```yaml
volumes:
  - ${DATA_PATH}/wordpress:/var/www/html
  - ${DATA_PATH}/mariadb:/var/lib/mysql
```

Stopping containers (`make down`) does **not** delete data — only `make fclean` wipes the host directories.

### Reset data without removing images

```bash
make clean                                     # stop containers
sudo rm -rf ${DATA_PATH}/wordpress ${DATA_PATH}/mariadb   # wipe data only
make                                           # restart — WordPress reinstalls
```

### Inspect bind mounts

```bash
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
5. If it needs credentials, add a secret under `secrets:` — never hardcode passwords
6. If it installs WordPress plugins/themes, add the install commands inside the `BONUS_SETUP` block in `srcs/requirements/wordpress/tools/entrypoint.sh` (gated on `[ "${BONUS_SETUP:-false}" = "true" ]`)
7. Rebuild and verify with `make fclean && make bonus`

> **Why `profiles: [bonus]` matters:** without it the service starts with plain `make`, collapsing the mandatory/bonus separation. Every bonus service must carry this key.

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
