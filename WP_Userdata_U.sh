#!/bin/bash

DB_IP=""

#Updating repository

apt-get update -y
apt-get upgrade -y

#Installing Docker CE

apt-get install -y docker.io

#Enabling starting docker with system launch

systemctl enable docker.service

#Starting docker

systemctl start docker.service

#Installing docker compose

curl -L "https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m)" -o /bin/docker-compose
chmod +x /bin/docker-compose

mkdir -p ~/wordpress-compose
touch ~/wordpress-compose/docker-compose.yml
mkdir -p ~/wordpress-compose/nginx/
mkdir -p ~/wordpress-compose/nginx/ssl/
mkdir -p ~/wordpress-compose/logs/nginx/
mkdir -p ~/wordpress-compose/wordpress/

#Generating selfsigned SSL certificate

openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ~/wordpress-compose/nginx/ssl/nginx.key -out ~/wordpress-compose/nginx/ssl/nginx.crt -subj "/C=  /ST=  /L=  /O=  /OU=  /CN=  "

#Nginx configuration

echo \
'ssl_certificate /etc/nginx/ssl/nginx.crt;
ssl_certificate_key /etc/nginx/ssl/nginx.key;

server {
    listen 80;
    server_name sevice-task-9000;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name sevice-task-9000;

    root /var/www/html;
    index index.php;

    access_log /var/log/nginx/service-task-9000-access.log;
    error_log /var/log/nginx/service-task-9000-error.log;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass wordpress:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
    }
}'> ~/wordpress-compose/nginx/wordpress.conf

#Docker compose service configuration

echo \
"nginx:
    image: nginx:latest
    ports:
        - '80:80'
        - '443:443'
    volumes:
        - ./nginx:/etc/nginx/conf.d
        - ./logs/nginx:/var/log/nginx
        - ./wordpress:/var/www/html
        - ./nginx/ssl:/etc/nginx/ssl
    links:
        - wordpress
    restart: always
wordpress:
    image: wordpress:4.7.1-php7.0-fpm
    ports:
        - '9000:9000'
        - '3306:3306'
    volumes:
        - ./wordpress:/var/www/html
    environment:
        - WORDPRESS_DB_NAME=wordpressuser
        - WORDPRESS_DB_HOST=$DB_IP
        - WORDPRESS_DB_PASSWORD=password
    restart: always
" > ~/wordpress-compose/docker-compose.yml

#Starting services

cd ~/wordpress-compose
docker-compose up -d
