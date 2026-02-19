# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Token Optimization Strategies
The goal here is to minimize token usage while maximizing efficiency and clarity in interactions. Please, use rigor to think about my prompts. As a User, I'll probably need to fix my prompt - and that's what I expect, if you follow these strategies:

### Compact history
When referencing previous interactions, summarize them concisely instead of copying entire exchanges. Focus on key points relevant to the current task. If our last interaction were more than 1 hour ago, summarize the context instead of reading the full history.

### Optimize Limit usage - starts with Model Haiku ON
For simple tasks, use Claude's smaller models (e.g., Claude 2, Claude 1.3) to conserve token usage. Reserve larger models (Claude 3, Claude 4) for complex tasks requiring deep understanding or generation.
`--model haiku` should be the default for most interactions, like:
- Running/checking tests
- Simple code modifications
- Basic explanations
- Simple file searches
- Syntax checks and corrections
- Build commands
For complex tasks, switch to Sonnet/Opus only for:
- Major refactoring
- Complex debugging
- Architectural decisions

### Force me to be specific
Claude, If I provide you cloudy and not clear instructions, ask me to be specific. For example:
- Instead of "Fix the code", I should prompt you "Fix the memory leak in Module03/ex02".
- Instead of "Add tests", I should prompt you "Add Google Test cases for edge cases in Module05/ex01".
- Instead of "Explain this module", I should prompt you "Explain the purpose and functionality of Module04/ex03".

### Ask me to optimize the prompt, using batching
Claude, If you notice that I have multiple related tasks, ask me to batch them into a single prompt to reduce token usage. For example:
- "Batch the following tasks: 1) Add tests for Module02/ex01, 2) Fix bugs in Module03/ex02, 3) Update README for Module01."
For Module 06 ex00, you can say:
- "Batch the following tasks for Module06/ex00: 1) Write Google Test cases, 2) Implement the required functionality, 3) Update the README with build instructions."

### Limit File Reading
Avoid reading files entirely. Instead, ask me to specify only the necessary files or sections.
- Read specific lines or functions instead of entire files, unless necessary
- Use Grap/Glob before Read to limit files
I should prompt you, for example:
- "Read only the header files in Module02/ex01."
- "Read the implementation of the main class in Module03/ex02."

### Count down current session available tokens
Provide a countdown of remaining tokens of the current session after each response.

## Repository Structure

42 School Inception project — Docker Compose infrastructure.

```
.
├── Makefile                   # Root: builds images via docker-compose.yml
├── README.md
├── USER_DOC.md                # User documentation (required for validation)
├── DEV_DOC.md                 # Developer documentation (required for validation)
├── secrets/                   # Credentials (NOT committed to git)
│   ├── credentials.txt
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── .env                   # Non-sensitive environment variables
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
        ├── wordpress/
        │   ├── conf/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   └── tools/
        └── bonus/             # Optional bonus services
```

## Build Commands

```bash
make          # Build images and start all services (docker compose up --build)
make down     # Stop and remove containers
make clean    # Remove containers + networks
make fclean   # Full clean: containers + volumes + images
make re       # fclean + make
```

## Services Overview

| Container | Base OS | Port | Role |
|-----------|---------|------|------|
| nginx | Alpine/Debian | 443 (host) | Sole entrypoint (TLSv1.2/1.3) |
| wordpress | Alpine/Debian | 9000 (internal) | php-fpm app server |
| mariadb | Alpine/Debian | 3306 (internal) | Database |

## Key Constraints (from subject)

- **No `latest` tag** in any Dockerfile
- **No passwords** in Dockerfiles or docker-compose.yml — use `.env` + secrets
- **No `network: host`**, `--link`, or `links:` — use custom bridge network
- **No infinite loop hacks**: `tail -f`, `sleep infinity`, `while true` are forbidden
- **No pre-built images** pulled from DockerHub (Alpine/Debian base is allowed)
- Containers must **restart automatically** on crash
- WordPress DB must have **2 users** (admin username must NOT contain "admin"/"Admin"/"administrator")
- Domain: `login.42.fr` → local IP, via NGINX port 443 only
- Volumes stored at `/home/login/data` on the host

## Required Documentation Files

Per subject Chapter VII, these must exist at repository root:

- **`USER_DOC.md`** — end-user guide: services overview, start/stop, website access, credentials location, health checks
- **`DEV_DOC.md`** — developer guide: setup from scratch, build/launch with Makefile, container management, data persistence

## Learning Path & Current Progress

Subject documented at `Inception-subject.pdf` (v5.0).

Current progress:
- Infrastructure: to be implemented
- Mandatory services (nginx, wordpress, mariadb): to be implemented
- `USER_DOC.md` and `DEV_DOC.md`: to be written
- Bonus services (redis, FTP, static site, Adminer, custom): optional

Task order:
1. Set up `srcs/.env` and `secrets/` files
2. Write Dockerfile + config for MariaDB
3. Write Dockerfile + config for WordPress (php-fpm)
4. Write Dockerfile + config for NGINX (TLS)
5. Write `docker-compose.yml` with volumes and network
6. Write `USER_DOC.md` and `DEV_DOC.md`
7. Bonus services (only after mandatory part is perfect)