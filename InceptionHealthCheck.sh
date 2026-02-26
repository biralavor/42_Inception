#!/bin/bash
# InceptionHealthCheck.sh
# Integration health check for the 42 Inception project.
# Run from the repository root: bash InceptionHealthCheck.sh
#
# Mandatory tests always run; bonus tests always run too but their failures
# are tracked separately and do NOT affect the exit code.
# Bonus tests pass only when the stack was started with `make bonus`.

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
RESET='\033[0m'

# ── State ─────────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
BONUS_PASS=0
BONUS_FAIL=0
DOMAIN="umeneses.42.fr"

# ── Helpers ───────────────────────────────────────────────────────────────────
pass()         { printf "${GREEN}[PASS]${RESET} %s\n" "$1"; ((++PASS)); }
fail()         { printf "${RED}[FAIL]${RESET} %s\n" "$1"; ((++FAIL)); }
info()         { printf "${CYAN}[INFO]${RESET} %s\n" "$1"; }
section()      { printf "\n${YELLOW}=== %s ===${RESET}\n" "$1"; }
bpass()        { printf "${GREEN}[BONUS PASS]${RESET} %s\n" "$1"; ((++BONUS_PASS)); }
bfail()        { printf "${MAGENTA}[BONUS FAIL]${RESET} %s\n" "$1"; ((++BONUS_FAIL)); }
bonus_section(){ printf "\n${MAGENTA}=== BONUS: %s ===${RESET}\n" "$1"; }

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

    # Port 80 must NOT be exposed by any Docker container
    if docker ps --format '{{.Ports}}' | grep -q ':80->'; then
        fail "Port 80 is exposed by a Docker container (only port 443 is allowed)"
    else
        pass "Port 80 is not exposed by Docker"
    fi

    # wp-admin must be reachable (200 or 302 redirect to login)
    wp_admin_code=$(curl -sk -o /dev/null -w "%{http_code}" "https://localhost:443/wp-admin/" 2>/dev/null || echo "000")
    if [[ "$wp_admin_code" =~ ^(200|302)$ ]]; then
        pass "WordPress wp-admin reachable (HTTP $wp_admin_code)"
    else
        fail "WordPress wp-admin not reachable (HTTP $wp_admin_code)"
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
# Volumes use direct bind mounts (not named volumes); verify containers have bind mounts
for svc in wordpress mariadb; do
    bind_src=$(docker inspect "$svc" --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}} {{end}}{{end}}' 2>/dev/null | tr ' ' '\n' | grep -v "^$" | head -1 || true)
    if [[ -n "$bind_src" ]]; then
        pass "Container '$svc' uses bind mount: $bind_src"
    else
        fail "Container '$svc' has no bind mount (data persistence may be missing)"
    fi
done

data_path=$(grep "^DATA_PATH=" srcs/.env 2>/dev/null | cut -d= -f2 | tr -d '\r' || echo "")
for dir in wordpress mariadb; do
    if [[ -n "$data_path" ]]; then
        host_path="${data_path}/$dir"
    else
        host_path="/home/umeneses/data/$dir"
    fi
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
    db_ping=$(docker exec mariadb sh -c 'mariadb-admin ping -uroot -p"$(cat /run/secrets/db_root_password)" --skip-ssl 2>/dev/null' || echo "fail")
    if echo "$db_ping" | grep -q "alive"; then
        pass "MariaDB is alive"
    else
        fail "MariaDB ping failed"
    fi

    # nginx must NOT be inside the mariadb container
    if docker exec mariadb which nginx &>/dev/null; then
        fail "nginx found inside mariadb container (must not be there)"
    else
        pass "nginx is NOT inside mariadb container"
    fi

    # MariaDB port 3306 must NOT be reachable from the host
    if command -v nc &>/dev/null; then
        if nc -z -w1 127.0.0.1 3306 2>/dev/null; then
            fail "MariaDB port 3306 is reachable from the host (must be internal only)"
        else
            pass "MariaDB port 3306 is NOT exposed to the host"
        fi
    elif command -v curl &>/dev/null; then
        if curl -s --connect-timeout 1 "mysql://127.0.0.1:3306" &>/dev/null || \
           curl -s --max-time 1 -o /dev/null "http://127.0.0.1:3306" 2>&1 | grep -q "Received"; then
            fail "MariaDB port 3306 is reachable from the host (must be internal only)"
        else
            pass "MariaDB port 3306 is NOT exposed to the host"
        fi
    else
        # Fallback: check docker ps for published 3306 port
        if docker ps --format '{{.Ports}}' | grep -q ':3306->'; then
            fail "MariaDB port 3306 is exposed by Docker (must be internal only)"
        else
            pass "MariaDB port 3306 is NOT exposed by Docker"
        fi
    fi

    # WordPress database must not be empty (connect via socket as root — no password needed from docker exec)
    mysql_db=$(grep "^WP_DATABASE=" srcs/.env 2>/dev/null | cut -d= -f2 | tr -d '\r' || echo "wordpress")
    wp_tables=$(docker exec mariadb sh -c "mariadb -uroot -p\"\$(cat /run/secrets/db_root_password)\" --skip-ssl -e \"SHOW TABLES FROM \\\`${mysql_db}\\\`;\" 2>/dev/null" | grep -vc "Tables_in" || true)
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
wp_path=$(grep "^DOMAIN_ROOT=" srcs/.env 2>/dev/null | cut -d= -f2 | tr -d '\r' || echo "/var/www/html")
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

    # WordPress must have at least 2 users (admin + regular editor)
    wp_user_list=$(docker exec wordpress wp user list \
        --path="${wp_path:-/var/www/html}" \
        --fields=user_login,roles --allow-root 2>/dev/null || echo "")
    wp_user_count=$(echo "$wp_user_list" | grep -vc "user_login" || true)
    if [[ "$wp_user_count" -ge 2 ]]; then
        pass "WordPress has $wp_user_count user(s) (minimum 2 required)"
    else
        fail "WordPress has fewer than 2 users (got $wp_user_count) — subject requires admin + regular user"
    fi

    # Admin username must NOT contain 'admin' variants
    if echo "$wp_user_list" | grep -iE "^(admin|administrator|admin-[0-9]+)\s"; then
        fail "A forbidden admin-like WordPress username was found"
    else
        pass "No forbidden admin username variants in WordPress users"
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

# Check that each running container uses an image whose name matches the service.
# This avoids false positives from official nginx/wordpress/mariadb images that
# may exist on the system from unrelated pulls.
for svc in nginx wordpress mariadb; do
    img=$(docker inspect "$svc" --format '{{.Config.Image}}' 2>/dev/null || echo "")
    if [[ "$img" == "$svc" ]]; then
        pass "Container '$svc' uses image named '$svc' (matches service name)"
    else
        fail "Container '$svc' uses image '${img:-N/A}' (expected image named '$svc')"
    fi
done

# ════════════════════════════════════════════════════════════════════════════
# BONUS SECTION — tests below pass only when started with `make bonus`.
# Failures here are expected in mandatory-only mode and do NOT affect exit code.
# ════════════════════════════════════════════════════════════════════════════

# ── B1. Bonus Container Status ───────────────────────────────────────────────
bonus_section "Container Status"
if container_running ftp; then
    bpass "Container 'ftp' is running"
else
    bfail "Container 'ftp' is NOT running (expected after 'make bonus')"
fi

# ── B2. FTP Accessibility ─────────────────────────────────────────────────────
bonus_section "FTP Server"
if container_running ftp; then
    # Restart policy
    ftp_policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' ftp 2>/dev/null || echo "N/A")
    if [[ "$ftp_policy" =~ ^(unless-stopped|always|on-failure)$ ]]; then
        bpass "ftp restart policy: $ftp_policy"
    else
        bfail "ftp has no valid restart policy (got: '$ftp_policy')"
    fi

    # Port 21 must be exposed on the host
    if docker ps --format '{{.Ports}}' | grep -q ':21->'; then
        bpass "FTP port 21 is exposed on the host"
    else
        bfail "FTP port 21 is NOT exposed on the host"
    fi

    # Passive port range must be exposed
    if docker ps --format '{{.Ports}}' | grep -q '21100-21110->'; then
        bpass "FTP passive port range 21100-21110 is exposed"
    else
        bfail "FTP passive port range 21100-21110 is NOT exposed"
    fi

    # ftp container must be on the inception network
    net_bonus=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -i inception || true)
    if [[ -n "$net_bonus" ]] && docker network inspect "$net_bonus" 2>/dev/null | grep -q '"ftp"'; then
        bpass "ftp container is connected to $net_bonus"
    else
        bfail "ftp container is NOT connected to the inception network"
    fi
else
    info "ftp container not running — skipping FTP checks"
    bfail "FTP port 21 not tested (container not running)"
    bfail "FTP passive port range not tested (container not running)"
    bfail "FTP network not tested (container not running)"
fi

# ── B3. WordPress Bonus Theme & Plugins ───────────────────────────────────────
bonus_section "WordPress Theme & Plugins"
if container_running wordpress; then
    # Active theme must be KALPA
    if docker exec wordpress wp theme is-active kalpa \
        --path="${wp_path:-/var/www/html}" \
        --allow-root 2>/dev/null; then
        bpass "Active WordPress theme is KALPA"
    else
        bfail "Active WordPress theme is NOT KALPA (expected after 'make bonus')"
    fi

    # Required bonus plugins must be active
    for plugin in elementor wpkoi-templates-for-elementor; do
        if docker exec wordpress wp plugin is-active "${plugin}" \
            --path="${wp_path:-/var/www/html}" \
            --allow-root 2>/dev/null; then
            bpass "Plugin '${plugin}' is active"
        else
            bfail "Plugin '${plugin}' is not active (expected after 'make bonus')"
        fi
    done

    # Cast users: bonus mode adds more than 2 users
    wp_bonus_users=$(docker exec wordpress wp user list \
        --path="${wp_path:-/var/www/html}" \
        --fields=user_login --allow-root 2>/dev/null | grep -vc "user_login" || true)
    if [[ "$wp_bonus_users" -gt 2 ]]; then
        bpass "WordPress has $wp_bonus_users users — cast users present"
    else
        bfail "WordPress has only $wp_bonus_users user(s) — cast users not created (expected after 'make bonus')"
    fi
else
    info "wordpress container not running — skipping bonus WordPress checks"
    bfail "KALPA theme not tested (container not running)"
    bfail "Elementor plugin not tested (container not running)"
    bfail "wpkoi plugin not tested (container not running)"
    bfail "Cast users not tested (container not running)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${YELLOW}══════════════════════════════════════════${RESET}\n"
printf "  ${YELLOW}MANDATORY${RESET}  ${GREEN}PASSED: %-3d${RESET}  ${RED}FAILED: %-3d${RESET}\n" "$PASS" "$FAIL"
printf "  ${MAGENTA}BONUS${RESET}      ${GREEN}PASSED: %-3d${RESET}  ${MAGENTA}FAILED: %-3d${RESET}\n" "$BONUS_PASS" "$BONUS_FAIL"
printf "${YELLOW}══════════════════════════════════════════${RESET}\n"

if [[ $FAIL -eq 0 ]]; then
    printf "${GREEN}All mandatory checks passed! Inception is healthy.${RESET}\n"
    if [[ $BONUS_FAIL -gt 0 ]]; then
        printf "${MAGENTA}%d bonus check(s) failed — run 'make bonus' to enable bonus services.${RESET}\n" "$BONUS_FAIL"
    else
        printf "${GREEN}All bonus checks passed too!${RESET}\n"
    fi
    exit 0
else
    printf "${RED}%d mandatory check(s) failed. Review the output above.${RESET}\n" "$FAIL"
    if [[ $BONUS_FAIL -gt 0 ]]; then
        printf "${MAGENTA}%d bonus check(s) also failed — run 'make bonus' to enable bonus services.${RESET}\n" "$BONUS_FAIL"
    fi
    exit 1
fi
