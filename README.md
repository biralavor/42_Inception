*This project has been created as part of the 42 curriculum by umeneses.*

# Inception 5.0

## Description

Inception is a System Administration exercise that broadens knowledge of Docker by virtualizing several Docker images inside a personal virtual machine. The goal is to set up a small infrastructure composed of different services under specific rules, orchestrated with Docker Compose.

The stack consists of three containers communicating over a private Docker network:
- **NGINX** — sole entrypoint via HTTPS (TLSv1.2/TLSv1.3, port 443)
- **WordPress + php-fpm** — application server (no nginx inside)
- **MariaDB** — database server (no nginx inside)

Data is persisted via two Docker volumes (WordPress files and database), and all sensitive configuration is managed through environment variables and Docker secrets — never hardcoded.

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
├── secrets/
│   ├── credentials.txt
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── .env
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── conf/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   └── tools/
        ├── nginx/
        │   ├── conf/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   └── tools/
        └── wordpress/
            ├── conf/
            ├── Dockerfile
            ├── .dockerignore
            └── tools/
```

### Configuration

1. Copy `.env.example` to `srcs/.env` and fill in your values:

```env
DOMAIN_NAME=login.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
```

2. Create secret files under `secrets/` (these are **not** committed to git):

```bash
echo "your_db_password"      > secrets/db_password.txt
echo "your_root_password"    > secrets/db_root_password.txt
echo "your_wp_credentials"   > secrets/credentials.txt
```

3. Add your domain to `/etc/hosts`:

```
127.0.0.1   login.42.fr
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

| | Docker Secrets | Environment Variables |
|---|---|---|
| Storage | Encrypted in-memory tmpfs | Plaintext in process env |
| Visibility | Only to authorized services | Visible via `docker inspect` |
| Git safety | Never in repository | Risk of accidental commit |
| Best for | Passwords, API keys, tokens | Non-sensitive config (domain, ports) |

This project uses a `.env` file for non-sensitive configuration and Docker secrets (mounted as files) for all credentials — passwords never appear in Dockerfiles or `docker-compose.yml`.

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

This project uses **Docker volumes** for the WordPress database and website files. Volumes are stored under `/home/login/data` on the host machine.

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
- [Docker secrets documentation](https://docs.docker.com/engine/swarm/secrets/)

### AI Usage

AI tools (Claude Code) were used in this project for the following tasks:
- Generating the initial `README.md` structure based on the project subject
- Explaining differences between Docker concepts (volumes vs bind mounts, secrets vs env vars)
- Drafting Dockerfile best practices and reviewing configurations
- Suggesting nginx TLS configuration snippets

All AI-generated content was reviewed, tested, and validated before inclusion. No configuration was blindly copy-pasted — each piece was understood and adapted to the project requirements.
