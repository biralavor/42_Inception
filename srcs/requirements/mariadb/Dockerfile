FROM alpine:3.22

RUN apk add --no-cache mariadb mariadb-client

RUN mkdir -p /run/mysqld /var/log/mysql \
    && chown -R mysql:mysql /run/mysqld /var/log/mysql

COPY conf/mariadb.cnf /etc/my.cnf.d/mariadb-server.cnf
COPY tools/init-db.sh /init-db.sh
RUN chmod +x /init-db.sh

EXPOSE 3306

ENTRYPOINT ["/init-db.sh"]
