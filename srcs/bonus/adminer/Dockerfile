FROM alpine:3.22

RUN apk add --no-cache php84 php84-session php84-mysqli wget

RUN ln -s /usr/bin/php84 /usr/bin/php

RUN mkdir -p /var/www/adminer

RUN wget -qO /var/www/adminer/index.php https://www.adminer.org/latest.php

EXPOSE 8080

CMD ["php", "-S", "0.0.0.0:8080", "-t", "/var/www/adminer"]
