#!/bin/bash
WP_IP=""
yum update -y
#Creating reverse proxy based on haproxy
yum install -y haproxy
# systemctl do not works
service haproxy enable
service haproxy start
echo "global
   log /dev/log local0
   log /dev/log local1 notice
   chroot /var/lib/haproxy
   stats timeout 30s
   user haproxy
   group haproxy
   daemon

defaults
   log global
   option dontlognull
   timeout connect 5000
   timeout client 50000
   timeout server 50000

frontend http_front
   bind *:80
   mode http
   option httplog
   stats uri /haproxy?stats
   default_backend http_back

backend http_back
   mode http
   option forwardfor
   server wp_server_1 $WP_IP:80 check

frontend https_front
   bind *:443
   mode tcp
   option tcplog
   stats uri /haproxy?stats
   default_backend https_back

backend https_back
   mode tcp
   option ssl-hello-chk
   server wp_server_1 $WP_IP:443 check">/etc/haproxy/haproxy.cfg
service haproxy restart
