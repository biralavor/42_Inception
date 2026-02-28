*This project has been created as part of the 42 curriculum by umeneses.*

# Inception 5.0

## Description

Inception is a System Administration exercise that broadens knowledge of Docker by virtualizing several Docker images inside a personal virtual machine. The goal is to set up a small infrastructure composed of different services under specific rules, orchestrated with Docker Compose.

The stack consists of three containers communicating over a private Docker network:
- **NGINX** — sole entrypoint via HTTPS (TLSv1.2/TLSv1.3, port 443)
- **WordPress + php-fpm** — application server (no nginx inside)
- **MariaDB** — database server (no nginx inside)

Data is persisted via two bind-mount volumes (WordPress files and database), and all configuration — including credentials — is managed through `srcs/.env`, which is never committed to the repository.

---

## Instructions

### Prerequisites

- A Virtual Machine running Linux (Alpine or Debian penultimate stable)
- Docker and Docker Compose installed
- `make` available

### Directory structure

```
.
├── Makefile
└── srcs/
    ├── .env              ← create from .env.example (never committed)
    ├── .env.example      ← tracked template: copy and fill in before running
    ├── docker-compose.yml
    ├── requirements/
    │   ├── mariadb/
    │   │   ├── conf/
    │   │   ├── Dockerfile
    │   │   └── tools/
    │   ├── nginx/
    │   │   ├── conf/
    │   │   ├── Dockerfile
    │   │   └── tools/
    │   └── wordpress/
    │       ├── conf/
    │       ├── Dockerfile
    │       └── tools/
    └── bonus/            ← optional bonus services
        ├── adminer/
        ├── ftp/
        ├── redis/
        └── static/
```

### Build and run

```bash
# Build images and start all services
make

# Stop and remove containers
make down

# Full clean (containers + volumes + images)
make fclean

# Rebuild from scratch
make re
```

### Bonus services

The bonus stack adds an FTP server, an Adminer MariaDB GUI, and a themed WordPress setup (Kalpa + Elementor + cast users) on top of the mandatory services.

```bash
# Start mandatory + all bonus services
make bonus

# Stop bonus services (keeps volumes)
make bonus_down
```

**Switching between mandatory and bonus:**

| Goal | Command |
|------|---------|
| Mandatory only (fresh) | `make fclean && make` |
| Add bonus on top of running mandatory | `make bonus` |
| Back to mandatory only | `make fclean && make` |
| Fresh bonus build | `make fclean && make bonus` |

> Both `make` and `make bonus` block until WordPress (php-fpm) is actually ready before printing the "up!" message. Wait for that message before opening the browser.

### Access

- WordPress site: `https://login.42.fr`
- All traffic goes through NGINX on port **443** (TLS only)

---

## Project Description

### Docker and design choices

This project builds all Docker images from scratch using custom Dockerfiles based on the **penultimate stable Alpine or Debian** release. Pulling pre-built images from DockerHub (other than the base OS) is forbidden.

Each service runs in its own isolated container, connected through a dedicated `docker-network`. Containers are configured to restart automatically on crash.

### Virtual Machines vs Docker

| | Virtual Machines | Docker |
|---|---|---|
| Isolation | Full OS virtualization | Process-level isolation |
| Resource usage | High (full OS per VM) | Low (shared kernel) |
| Startup time | Minutes | Seconds |
| Portability | Harder (large images) | Easy (layered images) |
| Use case | Strong isolation needs | Microservices, dev/prod parity |

Docker containers share the host kernel but isolate processes via namespaces and cgroups — lighter and faster than VMs, but with less isolation.

### Secrets vs Environment Variables

| | `.env` file | Hardcoded in Dockerfile / compose |
|---|---|---|
| Git safety | Gitignored — never committed | Exposed in repository history |
| Flexibility | Changed without rebuilding | Requires image rebuild |
| Visibility | Only to processes that need it | Visible to anyone with repo access |
| Best for | All credentials and config | Nothing — never do this |

This project stores all credentials (`DB_PASSWORD`, `WP_ADMIN_PASS`, etc.) in `srcs/.env`, which is covered by `.gitignore`. A tracked `srcs/.env.example` template shows evaluators which variables to fill in. Passwords never appear in Dockerfiles or `docker-compose.yml`.

### Docker Network vs Host Network

| | Docker Network (bridge) | Host Network |
|---|---|---|
| Isolation | Containers in private subnet | Shares host network stack |
| Port exposure | Explicit (`ports:`) | All ports exposed |
| Security | Better (controlled exposure) | Poor (no isolation) |
| Inter-container | By service name (DNS) | By localhost |

This project uses a custom **bridge network** (`docker-network`). Only NGINX exposes port 443 to the host. WordPress and MariaDB are reachable only from within the Docker network — `network: host` is explicitly forbidden.

### Docker Volumes vs Bind Mounts

| | Docker Volumes | Bind Mounts |
|---|---|---|
| Location | Managed by Docker | Specific host path |
| Portability | High | Low (host-dependent) |
| Performance | Optimized | Depends on OS |
| Use case | Persistent data | Dev (live code reload) |

This project uses **bind mounts** for the WordPress database and website files. Data is stored under `DATA_PATH` (default `/home/login/data`) on the host machine, set via `srcs/.env`.

---

## Documentation

Full project documentation lives in the `docs/` directory:

| File | Audience | Contents |
|------|----------|----------|
| [`docs/USER_DOC.md`](docs/USER_DOC.md) | End users / administrators | Services overview, start/stop, site access, credentials, health check |
| [`docs/DEV_DOC.md`](docs/DEV_DOC.md) | Developers | Setup from scratch, build & launch, container and volume management, architecture |

---

## Resources

### Documentation
- [Docker official documentation](https://docs.docker.com/)
- [Docker Compose reference](https://docs.docker.com/compose/compose-file/)
- [NGINX configuration guide](https://nginx.org/en/docs/)
- [MariaDB documentation](https://mariadb.com/kb/en/)
- [WordPress CLI (WP-CLI)](https://wp-cli.org/)
- [php-fpm configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [TLS/SSL best practices](https://wiki.mozilla.org/Security/Server_Side_TLS)
- [PID 1 and Docker best practices](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)
- [Docker Compose env_file reference](https://docs.docker.com/compose/environment-variables/env-file/)

### AI Usage

AI tools (Claude Code) were used in this project for the following tasks:
- Generating the initial `README.md` structure based on the project subject
- Explaining differences between Docker concepts (volumes vs bind mounts, secrets vs env vars)
- Drafting Dockerfile best practices and reviewing configurations
- Suggesting nginx TLS configuration snippets

All AI-generated content was reviewed, tested, and validated before inclusion. No configuration was blindly copy-pasted — each piece was understood and adapted to the project requirements.
