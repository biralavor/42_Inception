FROM alpine:3.22

RUN apk add --no-cache nginx

COPY static/conf/nginx.conf /etc/nginx/http.d/default.conf
COPY static/www/ /var/www/static/
COPY ftp/tools/seeds/Inception-movie-poster-with-logo.webp /var/www/static/
COPY ftp/tools/seeds/Inception-Half-Remembered-Dream.mp3   /var/www/static/

EXPOSE 8888

CMD ["nginx", "-g", "daemon off;"]
