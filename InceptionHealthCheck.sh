#!/bin/bash
# InceptionHealthCheck.sh
# Integration health check for the 42 Inception project.
# Run from the repository root: bash InceptionHealthCheck.sh

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ── State ─────────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
DOMAIN="umeneses.42.fr"

# ── Helpers ───────────────────────────────────────────────────────────────────
pass()    { printf "${GREEN}[PASS]${RESET} %s\n" "$1"; ((++PASS)); }
fail()    { printf "${RED}[FAIL]${RESET} %s\n" "$1"; ((++FAIL)); }
info()    { printf "${CYAN}[INFO]${RESET} %s\n" "$1"; }
section() { printf "\n${YELLOW}=== %s ===${RESET}\n" "$1"; }

container_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${1}$"
}

# ── 1. Container Status ────────────────────────────────────────────────────────
section "Container Status"
for svc in nginx wordpress mariadb; do
    if container_running "$svc"; then
        pass "Container '$svc' is running"
    else
        fail "Container '$svc' is NOT running"
    fi
done

# ── 2. Restart Policy ─────────────────────────────────────────────────────────
section "Restart Policy"
for svc in nginx wordpress mariadb; do
    policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$svc" 2>/dev/null || echo "N/A")
    if [[ "$policy" =~ ^(unless-stopped|always|on-failure)$ ]]; then
        pass "$svc restart policy: $policy"
    else
        fail "$svc has no valid restart policy (got: '$policy')"
    fi
done

# ── 3. TLS Versions ───────────────────────────────────────────────────────────
section "NGINX TLS (port 443)"
if command -v openssl &>/dev/null; then
    for proto in tls1_2 tls1_3; do
        if openssl s_client -connect localhost:443 -"${proto}" </dev/null 2>&1 | grep -q "Cipher"; then
            pass "TLS protocol ${proto} accepted"
        else
            fail "TLS protocol ${proto} NOT accepted"
        fi
    done
    for proto in tls1 tls1_1; do
        result=$(openssl s_client -connect localhost:443 -"${proto}" </dev/null 2>&1) || true
        if echo "$result" | grep -qiE "alert|error|no protocols"; then
            pass "TLS protocol ${proto} correctly rejected"
        else
            fail "TLS protocol ${proto} should be rejected but was accepted"
        fi
    done
else
    info "openssl not found — skipping TLS checks"
fi

# ── 4. HTTPS Response ─────────────────────────────────────────────────────────
section "HTTP/HTTPS Access"
if command -v curl &>/dev/null; then
    http_code=$(curl -sk -o /dev/null -w "%{http_code}" "https://localhost:443/" 2>/dev/null || echo "000")
    if [[ "$http_code" =~ ^(200|301|302)$ ]]; then
        pass "NGINX responds on port 443 (HTTP $http_code)"
    else
        fail "NGINX returned unexpected HTTP code: $http_code"
    fi

    # Port 80 must NOT be exposed
    if curl -s --connect-timeout 2 "http://localhost:80/" &>/dev/null; then
        fail "Port 80 is exposed (only port 443 is allowed)"
    else
        pass "Port 80 is not exposed"
    fi
else
    info "curl not found — skipping HTTP checks"
fi

# ── 5. Domain Resolution ──────────────────────────────────────────────────────
section "Domain Resolution"
local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
resolved=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' || echo "")
if [[ "$resolved" == "127.0.0.1" || "$resolved" == "$local_ip" ]]; then
    pass "$DOMAIN resolves to $resolved"
else
    fail "$DOMAIN does not resolve to local IP (got: '${resolved:-none}') — check /etc/hosts"
fi

# ── 6. Docker Volumes ─────────────────────────────────────────────────────────
section "Docker Volumes"
existing_vols=$(docker volume ls --format '{{.Name}}' 2>/dev/null)
for vol in wordpress_data db_data; do
    match=$(echo "$existing_vols" | grep "$vol" || true)
    if [[ -n "$match" ]]; then
        pass "Volume found: $match"
    else
        fail "Volume '$vol' not found"
    fi
done

for dir in wordpress mariadb; do
    host_path="/home/umeneses/data/$dir"
    if [[ -d "$host_path" ]]; then
        pass "Host data directory exists: $host_path"
    else
        fail "Host data directory missing: $host_path"
    fi
done

# ── 7. Docker Network ─────────────────────────────────────────────────────────
section "Docker Network"
net=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -i inception || true)
if [[ -n "$net" ]]; then
    pass "Docker network found: $net"
    for svc in nginx wordpress mariadb; do
        if docker network inspect "$net" 2>/dev/null | grep -q "\"$svc\""; then
            pass "$svc is connected to $net"
        else
            fail "$svc is NOT connected to $net"
        fi
    done
else
    fail "No Inception docker network found"
fi

# Check network: host is NOT used
if docker inspect nginx wordpress mariadb 2>/dev/null | grep -q '"NetworkMode": "host"'; then
    fail "At least one container uses 'network: host' (forbidden)"
else
    pass "No container uses 'network: host'"
fi

# ── 8. MariaDB Health ─────────────────────────────────────────────────────────
section "MariaDB"
if container_running mariadb; then
    db_ping=$(docker exec mariadb mysqladmin ping 2>/dev/null || echo "fail")
    if echo "$db_ping" | grep -q "alive"; then
        pass "MariaDB is alive"
    else
        fail "MariaDB ping failed"
    fi

    # Check WordPress DB user count (must have 2: admin + regular)
    wp_db=$(docker exec mariadb mysql -uroot \
        --password="$(cat secrets/db_root_password.txt 2>/dev/null)" \
        -e "SELECT User FROM mysql.user WHERE Host='localhost';" 2>/dev/null || echo "")
    user_count=$(echo "$wp_db" | grep -vc "User" || true)
    if [[ "$user_count" -ge 2 ]]; then
        pass "MariaDB has $user_count local user(s) (minimum 2 required)"
    else
        fail "MariaDB has fewer than 2 local users (got $user_count)"
    fi

    # Admin username must NOT contain 'admin' variants
    if echo "$wp_db" | grep -iE "^(admin|administrator|admin-[0-9]+)$"; then
        fail "An admin-like username was found — forbidden by subject rules"
    else
        pass "No forbidden admin username variants detected"
    fi

    # nginx must NOT be inside the mariadb container
    if docker exec mariadb which nginx &>/dev/null; then
        fail "nginx found inside mariadb container (must not be there)"
    else
        pass "nginx is NOT inside mariadb container"
    fi

    # WordPress database must not be empty
    mysql_db=$(grep "^MYSQL_DATABASE=" srcs/.env 2>/dev/null | cut -d= -f2 | tr -d '\r' || echo "wordpress")
    wp_tables=$(docker exec mariadb mysql -uroot \
        --password="$(cat secrets/db_root_password.txt 2>/dev/null)" \
        -e "SHOW TABLES FROM ${mysql_db};" 2>/dev/null | grep -vc "Tables_in" || true)
    if [[ "$wp_tables" -gt 0 ]]; then
        pass "WordPress database '${mysql_db}' has ${wp_tables} table(s) — not empty"
    else
        fail "WordPress database '${mysql_db}' appears to be empty"
    fi
else
    info "mariadb container not running — skipping DB checks"
fi

# ── 9. WordPress + php-fpm ────────────────────────────────────────────────────
section "WordPress (php-fpm)"
if container_running wordpress; then
    if docker exec wordpress php -v &>/dev/null; then
        pass "PHP is available in wordpress container"
    else
        fail "PHP not found in wordpress container"
    fi
    if docker exec wordpress pgrep php-fpm &>/dev/null; then
        pass "php-fpm process is running"
    else
        fail "php-fpm process not found"
    fi
    # nginx must NOT be inside the wordpress container
    if docker exec wordpress which nginx &>/dev/null; then
        fail "nginx found inside wordpress container (must not be there)"
    else
        pass "nginx is NOT inside wordpress container"
    fi
else
    info "wordpress container not running — skipping php checks"
fi

# ── 10. Dockerfile Safety ─────────────────────────────────────────────────────
section "Dockerfile Safety Checks"
dockerfiles=(
    "srcs/requirements/nginx/Dockerfile"
    "srcs/requirements/wordpress/Dockerfile"
    "srcs/requirements/mariadb/Dockerfile"
    "Dockerfile"
)
for df in "${dockerfiles[@]}"; do
    if [[ ! -f "$df" ]]; then
        info "$df not found — skipping"
        continue
    fi
    basename_df=$(basename "$(dirname "$df")")/$(basename "$df")

    if grep -q "FROM.*:latest" "$df"; then
        fail "$basename_df uses :latest tag (forbidden)"
    else
        pass "$basename_df: no :latest tag"
    fi

    # FROM must use a pinned penultimate Alpine or Debian version
    from_line=$(grep -m1 "^FROM" "$df" 2>/dev/null || echo "")
    if echo "$from_line" | grep -qiE "^FROM (alpine|debian):[0-9a-zA-Z]" && \
       ! echo "$from_line" | grep -qi ":latest"; then
        pass "$basename_df: FROM uses pinned Alpine/Debian version"
    else
        fail "$basename_df: FROM must be penultimate Alpine/Debian with explicit version (got: '${from_line:-empty}')"
    fi

    if grep -iE "(password|passwd|secret)\s*=\s*\S+" "$df" | grep -v "^#" | grep -q .; then
        fail "$basename_df may contain hardcoded credentials"
    else
        pass "$basename_df: no obvious hardcoded credentials"
    fi

    if grep -qE "tail -f|sleep infinity|while true" "$df"; then
        fail "$basename_df contains forbidden infinite loop pattern"
    else
        pass "$basename_df: no forbidden loop patterns"
    fi
done

# ── 11. docker-compose.yml Safety ────────────────────────────────────────────
section "Docker Compose Safety Checks"
COMPOSE_FILE="srcs/docker-compose.yml"
if [[ -f "$COMPOSE_FILE" ]]; then
    if grep -qE "network:\s*host|--link|^\s+links:" "$COMPOSE_FILE"; then
        fail "$COMPOSE_FILE contains forbidden network directives (network:host / --link / links:)"
    else
        pass "$COMPOSE_FILE: no forbidden network directives"
    fi

    if grep -q ":latest" "$COMPOSE_FILE"; then
        fail "$COMPOSE_FILE references :latest tag (forbidden)"
    else
        pass "$COMPOSE_FILE: no :latest tag"
    fi

    if grep -q "network:" "$COMPOSE_FILE"; then
        pass "$COMPOSE_FILE has a network definition"
    else
        fail "$COMPOSE_FILE is missing a network definition (required)"
    fi
else
    fail "$COMPOSE_FILE not found (must be at srcs/docker-compose.yml)"
fi

# ── 12. Secrets & Environment Files ──────────────────────────────────────────
section "Secrets & Environment"
for secret in secrets/db_password.txt secrets/db_root_password.txt secrets/credentials.txt; do
    if [[ -f "$secret" && -s "$secret" ]]; then
        pass "Secret file exists and non-empty: $secret"
    elif [[ -f "$secret" ]]; then
        fail "Secret file exists but is EMPTY: $secret"
    else
        fail "Secret file missing: $secret"
    fi
done

if [[ -f "srcs/.env" ]]; then
    pass "srcs/.env exists"
else
    fail "srcs/.env missing"
fi

# Secrets must not be tracked by git
if git rev-parse --git-dir &>/dev/null; then
    if git ls-files --error-unmatch secrets/ &>/dev/null 2>&1; then
        fail "secrets/ directory is tracked by git (CRITICAL — remove it from git history)"
    else
        pass "secrets/ directory is NOT tracked by git"
    fi
else
    info "Not a git repository — skipping git secret tracking check"
fi

# ── 13. Repository Structure ──────────────────────────────────────────────────
section "Repository Structure"

if [[ -f "Makefile" ]]; then
    pass "Makefile exists at repository root"
else
    fail "Makefile missing at repository root"
fi

if [[ -d "srcs" ]]; then
    pass "srcs/ directory exists at repository root"
else
    fail "srcs/ directory missing at repository root"
fi

# One non-empty Dockerfile per mandatory service
for svc in nginx wordpress mariadb; do
    df="srcs/requirements/$svc/Dockerfile"
    if [[ -f "$df" && -s "$df" ]]; then
        pass "Dockerfile exists and non-empty: srcs/requirements/$svc/"
    else
        fail "Dockerfile missing or empty: $df"
    fi
done

# No --link in Makefile or any script
if grep -rqE "\-\-link" Makefile srcs/ 2>/dev/null; then
    fail "--link found in Makefile or srcs/ (forbidden)"
else
    pass "No --link found in Makefile or srcs/"
fi

# ── 14. Entrypoint Script Safety ──────────────────────────────────────────────
section "Entrypoint Script Safety"

mapfile -t entrypoint_scripts < <(find srcs/requirements -name "*.sh" 2>/dev/null | sort)
if [[ ${#entrypoint_scripts[@]} -eq 0 ]]; then
    info "No shell scripts found in srcs/requirements/ — skipping"
else
    for script in "${entrypoint_scripts[@]}"; do
        # Forbidden: background process after daemon (e.g. "nginx & bash"), tail -f, sleep infinity
        if grep -qE "(nginx|php-fpm|mysqld)\s*&\s*(bash|sh)|tail\s+-f|sleep\s+infinity" "$script"; then
            fail "$script: contains forbidden background/infinite-loop pattern"
        else
            pass "$script: no forbidden background patterns"
        fi
    done
fi

# ── 15. Docker Image Names Match Services ─────────────────────────────────────
section "Docker Image Names"

existing_images=$(docker images --format '{{.Repository}}' 2>/dev/null)
for svc in nginx wordpress mariadb; do
    if echo "$existing_images" | grep -qE "^${svc}$"; then
        pass "Docker image named '${svc}' exists (matches service name)"
    else
        fail "No Docker image named '${svc}' found (image name must match service name)"
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${YELLOW}══════════════════════════════${RESET}\n"
printf "${GREEN}PASSED: %-3d${RESET}  ${RED}FAILED: %-3d${RESET}\n" "$PASS" "$FAIL"
printf "${YELLOW}══════════════════════════════${RESET}\n"

if [[ $FAIL -eq 0 ]]; then
    printf "${GREEN}All checks passed! Inception is healthy.${RESET}\n"
    exit 0
else
    printf "${RED}%d check(s) failed. Review the output above.${RESET}\n" "$FAIL"
    exit 1
fi
