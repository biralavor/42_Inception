#!/bin/sh
set -e

# Read credentials from Docker secret files
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
DB_PASSWORD=$(cat /run/secrets/db_password)

# Non-sensitive config from environment (.env)
DB_NAME="${MARIADB_DATABASE:-wordpress}"
DB_USER="${MARIADB_USER:-wp_user}"

if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing MariaDB data directory..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null

    # Start a temporary instance (socket only, no TCP) for setup
    mariadbd --user=mysql --skip-networking &
    MYSQLD_PID=$!

    # Wait until the socket is ready (bounded: 30 attempts)
    i=0
    until mysqladmin ping --socket=/run/mysqld/mysqld.sock --silent 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -gt 30 ] && echo "ERROR: MariaDB did not start in time" && exit 1
        sleep 1
    done

    mysql --socket=/run/mysqld/mysqld.sock -uroot <<-EOSQL
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
        CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
        CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
        FLUSH PRIVILEGES;
EOSQL

    mysqladmin --socket=/run/mysqld/mysqld.sock -uroot \
        --password="${DB_ROOT_PASSWORD}" shutdown
    wait "$MYSQLD_PID"
    echo "MariaDB initialization complete."
else
    echo "MariaDB already initialized."
fi

exec mariadbd --user=mysql
