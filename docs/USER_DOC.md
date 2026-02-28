# User Documentation — Inception

## Services Overview

The Inception stack runs the following containers:

| Service    | Role                                        | Access                          |
|------------|---------------------------------------------|---------------------------------|
| **nginx**  | HTTPS reverse proxy and sole entry point    | `https://umeneses.42.fr` (443)  |
| **wordpress** | WordPress application (php-fpm)          | Via nginx (no direct access)    |
| **mariadb** | Relational database for WordPress          | Internal only (port 3306)       |
| **redis** *(bonus)* | Object cache for WordPress        | Internal only (port 6379)       |
| **ftp** *(bonus)*   | FTP access to the WordPress volume  | `ftp://localhost` (port 21)     |
| **adminer** *(bonus)* | MariaDB web GUI                 | `http://localhost:8080`         |
| **static** *(bonus)*  | Static showcase site with audio   | `http://localhost:8888`         |

All containers restart automatically on crash.

---

## Start and Stop

Run all commands from the **repository root**.

### Start the stack

```bash
make
```

Builds all Docker images and starts all containers in the background. Host data directories are created automatically before containers start.

### Stop the stack (keep data)

```bash
make down
```

Stops and removes containers and networks. Volumes and images are preserved — data persists.

### Remove containers and reclaim disk space

```bash
make clean
```

Stops containers and runs `docker system prune` to remove dangling resources. Volumes and images are preserved.

### Full reset (wipe everything)

```bash
make fclean
```

Removes all containers, volumes, images, and host data directories. The next `make` will reinstall WordPress from scratch.

### Rebuild from scratch

```bash
make re
```

Equivalent to `make fclean` followed by `make`.

### View container status

```bash
make ps
```

### Tail all service logs

```bash
make logs
```

---

## Accessing the Site

### Website

```
https://umeneses.42.fr
```

Requires `umeneses.42.fr` to resolve to `127.0.0.1` in `/etc/hosts` (see [Developer Documentation](DEV_DOC.md)).

> The connection uses TLS. Your browser may warn about a self-signed certificate — this is expected. Accept the exception to proceed.

### WordPress Administration Panel

```
https://umeneses.42.fr/wp-admin
```

Log in with `WP_ADMIN_USER` and `WP_ADMIN_PASS` from `srcs/.env`.

### Adminer — MariaDB GUI *(bonus)*

```
http://localhost:8080
```

Log in with the following values:

| Field    | Value                                                   |
|----------|---------------------------------------------------------|
| System   | MySQL                                                   |
| Server   | `mariadb`                                               |
| Username | value of `MYSQL_USER` in `srcs/.env`                   |
| Password | value of `DB_PASSWORD` in `srcs/.env`                  |
| Database | value of `WP_DATABASE` in `srcs/.env`                  |

> Adminer has no TLS. This is acceptable for 42 evaluation — the subject mandates TLS only on port 443.

### Static Site *(bonus)*

```
http://localhost:8888
```

### FTP Access *(bonus)*

```
ftp://localhost
```

Connect with `FTP_USER` and `FTP_PASSWORD` from `srcs/.env`. The FTP root is the WordPress web root (`/var/www/html`).

---

## Credentials

All credentials are stored in `srcs/.env`, which is **never committed to git**. Copy the template and fill in your values before starting the stack:

```bash
cp srcs/.env.example srcs/.env
$EDITOR srcs/.env
```

| Variable | Purpose |
|----------|---------|
| `DB_PASSWORD` | MariaDB password for the WordPress database user |
| `DB_ROOT_PASSWORD` | MariaDB root password |
| `WP_ADMIN_USER` | WordPress admin login (must NOT be `admin`/`administrator`) |
| `WP_ADMIN_PASS` | WordPress admin password |
| `WP_EDITOR` | WordPress editor username |
| `WP_EDITOR_PASS` | WordPress editor password |
| `FTP_PASSWORD` | FTP user password *(bonus)* |

---

## Health Check

Run the built-in integration health check to verify all services are working correctly:

```bash
make check
```

This runs `InceptionHealthCheck.sh` and saves a clean report to `release.txt`.

You can also run it directly for colored output:

```bash
bash InceptionHealthCheck.sh
```

The check verifies:
- All containers are running with a valid restart policy
- TLS 1.2 and 1.3 are accepted; TLS 1.0 and 1.1 are rejected
- HTTPS responds on port 443; wp-admin is reachable
- Domain resolves to local IP
- Docker volumes and host data directories exist
- Docker network is correctly configured
- MariaDB is alive and the WordPress database is populated
- WordPress has the required users (admin + editor)
- KALPA theme is active; Elementor and WPKoi plugins are active
- Redis cache is connected *(bonus)*
- Adminer is reachable on port 8080 *(bonus)*
- No Dockerfiles use `:latest` tags or hardcoded credentials
- No forbidden patterns (`network: host`, `--link`, infinite loops)

A passing run exits with code `0` and prints `All checks passed! Inception is healthy.`
