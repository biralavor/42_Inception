FROM alpine:3.22

RUN apk add --no-cache vsftpd shadow

COPY conf/vsftpd.conf /etc/vsftpd/vsftpd.conf
COPY tools/seeds/ /seed/
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 21 21100-21110

ENTRYPOINT ["/entrypoint.sh"]
