#!/bin/bash
WP_IP=""
#Installing Docker CE

#Installing Docker CE prerequisite packages using
yum install -y device-mapper-persistent-data lvm2 yum-utils

#Adding Docker repository
yum-config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

#Installing Docker CE
yum install -y docker-ce-18.06.2.ce

#Starting and enable Docker service
systemctl enable docker.service
systemctl start docker.service

docker run -d --restart always -p 3306:3306 --name myDataBase -v ~/database/mysql:/var/lib/mysql -v ~/database/mysql:/etc/mysql/conf.d -e MYSQL_ROOT_PASSWORD=password  mariadb:latest

#manul starting of the container
#sudo docker start myDataBase


#Creating wordpress database & creating localhost user
docker exec -i  myDataBase sh -c "exec mysql -uroot -p\$MYSQL_ROOT_PASSWORD <<EOF
CREATE DATABASE wordpress;
CREATE USER localuser@localhost IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON wordpress.* TO localuser@localhost IDENTIFIED BY 'password';
FLUSH PRIVILEGES;
EOF"
#creating database user
docker exec -i  myDataBase sh -c "exec mysql -uroot -p\$MYSQL_ROOT_PASSWORD <<EOF
CREATE USER wordpressuser@$WP_IP IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON wordpress.* TO wordpressuser@$WP_IP IDENTIFIED BY 'password';
FLUSH PRIVILEGES;
EOF"

#Setting backup
mkdir ~/database/mysql/base_dump/
touch ~/database/backup.sh


cat > ~/database/backup.sh <<EOF
#!/bin/bash
DUMP=\$(sudo docker exec -i  myDataBase sh -c 'exec mysqldump --all-databases -uroot -p\$MYSQL_ROOT_PASSWORD')
sudo su -c 'echo \$DUMP > ~/database/mysql/base_dump/dump-\$(date "+%Y.%m.%d-%H:%M").sql'
EOF

chmod +x ~/database/backup.sh

#SHELL=/bin/bash
#MAILTO=ec2-user
# adding cron job that starts every 3 days every month
echo '0 0 */3 * * ~/database/backup.sh'>>/etc/crontab

#Show existing databases
#sudo docker exec -i  myDataBase sh -c 'exec mysqlshow -uroot -p$MYSQL_ROOT_PASSWORD'
