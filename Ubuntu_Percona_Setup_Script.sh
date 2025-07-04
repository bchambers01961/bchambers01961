#!/bin/bash

#Purpose: This script automates the setup of Linux boxes for the MES2019 Percona Cluster environment in a standard configuration.
#It also installs key useful software not installed on Ubuntu as standard. Anything that is already installed will be skipped.

#Changelog: 
#04/01/24: Added option to skip percona installation to speed up troubleshooting.
#04/01/24: Added 3rd option to just copy SSL Certificates to additional nodes
#04/01/24: Tidied up config file and added InnoDB performance options, also added line to remove the config file if it exists (To Prevent Multiple Settings)
#04/06/24: Added user instructions.
#Must be run as root.
#Need a better way to handle certificates.

#Instructions for user:
#Note: If installing nodes after the bootstrapped node. Certificates will need copying manually prior to running this.
#rsync -avrP /var/lib/mysql/ca.pem /var/lib/mysql/server-key.pem /var/lib/mysql/server-cert.pem mesadmin@"$cluster_ip_node2":/home/mesadmin;
#1: Confirm if Xtradb Cluster is to be installed or if it is already installed.
#2: Enter server_id which must be unique and numeric.
#3: Enter the name of the cluster.
#4: Enter IP address for first additional node to this one.
#5: Enter IP address for second additional node to this one.
#6: Confirm if it is the first or additional node

#Set Variables

user="bchambers"

#Ubuntu Important Tools Installation
sudo apt install net-tools -y
sudo apt install unzip -y
sudo apt install zip -y
sudo timedatectl set-timezone Europe/London

sudo ufw enable
sudo ufw allow 3306/tcp
sudo ufw allow 22/tcp
sudo ufw allow 22/udp
sudo ufw allow 10.100.23.0/24
sudo ufw allow 10.200.23.0/24
#sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 53/tcp
#PerconaXtraDB Specific
sudo ufw allow 4444
sudo ufw allow 4567
sudo ufw allow 4568
#Make directories crucial for server management
sudo mkdir -p /root/scripts
sudo mkdir -p /data/backups/full
sudo mkdir -p /data/backups/incremental

#Percona Installation
echo "Does Percona Xtradb need to be installed or would you like to skip?"
    options2=("Install Percona XtraDB" "Skip Installation")
    select opt2 in "${options2[@]}"; do
        case $opt2 in
        "Install Percona XtraDB")
            sudo apt update
            sudo apt install -y wget gnupg2 lsb-release curl
            wget https://repo.percona.com/apt/percona-release_latest.generic_all.deb
            sudo dpkg -i percona-release_latest.generic_all.deb
            sudo apt update
            sudo percona-release setup pxc80
            sudo apt install -y percona-xtradb-cluster
            sudo apt install -y percona-xtrabackup-80
            break
        ;;
        "Skip Installation")
            echo "Skipping installation, moving to configuration stage"
            break
        esac
    done


#This next section confirms details to be entered in the config file
echo "Please set a server ID (Must be unique & numeric)"
    while true; do
        read server_id
        if [[ -z "$server_id" ]]; then
            echo "No Server ID entered, please enter this to continue."
        elif [[ -z $server_id || ! $server_id =~ ^[0-9]+$ ]]; then 
            echo "Invalid server ID entered, please enter a numerical value"
        else
            echo "$server_id is server ID of this node, this will be added to the my.cnf"
            break
        fi
    done

echo "Please enter the name of the cluster"
    while true; do
        read cluster_name
        if [[ -z "$cluster_name" ]]; then
        echo "No Cluster Name entered, please enter this to continue."
        else
        echo "$cluster_name is the name of the cluster, this will be added to the my.cnf"
        break
        fi
    done
memory=$(awk '/MemTotal/ {printf "%.0f", $2/1048576 * 0.75}' /proc/meminfo); 
echo "${memory}G is what will be set for 'innodb_buffer_pool_size'in My.cnf."
echo "Please confirm the IP addresses to be included in this cluster (not including this one)"
echo "Please enter the IP address for the first additional node"
    while true; do
        read cluster_ip_node2
        if [[ -z "$cluster_ip_node2" ]]; then
            echo "No IP for first additional node entered, please enter this to continue."
        elif [[ -z $cluster_ip_node2 || ! $cluster_ip_node2 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then 
            echo "Invalid IP Address entered, please enter a valid value"
        else
            echo "$cluster_ip_node2 is the second node IP Address, adding to my.cnf"
            break
        fi
    done

echo "Please enter the IP address for the second additional node"
    while true; do
        read cluster_ip_node3
        if [[ -z "$cluster_ip_node3" ]]; then
            echo "No IP for second additional node entered, please enter this to continue."
        elif [[ -z $cluster_ip_node3 || ! $cluster_ip_node3 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then 
            echo "Invalid IP Address entered, please enter a valid value"
        else
            echo "$cluster_ip_node3 is the third node IP Address, adding to my.cnf"
            break
        fi
    done

node_ip=$(hostname -I | cut -f1 -d' ')
export HOSTNAME
echo "This nodes IP address is $node_ip, the name of the node is $HOSTNAME. These will be added to my.cnf."
#    while true; do
#        read node_name
#        if [[ -z "$node_name" ]]; then
#        echo "No Node Name entered, please enter this to continue."
#        else
#        echo "$node_name is the name of the cluster, this will be added to the my.cnf"
#        fi
#    done

echo "Is this the first node to be bootstrapped or an additional node? Or do bootstrap nodes SSL Certificates Require Copying?"
echo "Note that prior to setting up any additional nodes that the first node must be bootstrapped and working."
    options=("First Node" "Additional Node" "Copy SSL Certificates To Additional Nodes")
    select opt in "${options[@]}"; do
        case $opt in
            "First Node")
            echo "First Node Selected"
            rm /etc/mysql/my.cnf
                echo '
                [client]
                #socket=/var/lib/mysql/mysqld.sock

                [mysqld]
                server-id               = '"$server_id"'
                datadir                 = /var/lib/mysql
                #socket                 = /var/lib/mysql/mysqld.sock
                log-error               = /var/lib/mysql/mysqld.log
                pid-file                = /var/run/mysqld/mysqld.pid
                binlog_expire_logs_seconds      = 432000
                binlog_format           = ROW
                max_binlog_size         = 1024M
                default-storage-engine  = innodb
				
				#default charset
				character-set-server = utf8mb4
				collation-server = utf8mb4_0900_ai_ci
				init-connect='SET NAMES utf8mb4'

                disabled_storage_engines="MyISAM"
                max_allowed_packet= 1G
                innodb_autoinc_lock_mode= 2
                bind-address           = 0.0.0.0
                skip_name_resolve       = ON
                port                    = 3306
                #ssl                    = 0

                # InnoDB Performance Settings (If commented set manually)
                innodb_log_buffer_size=64M
                innodb_buffer_pool_size= '"${memory}G"'
                innodb_log_file_size=512M	
                innodb_buffer_pool_instances=8	
                innodb_thread_concurrency=0

                # Galera Provider Configuration
                wsrep_on=ON
                wsrep_provider=/usr/lib/galera4/libgalera_smm.so
                wsrep_provider_options=”socket.ssl_key=/var/lib/mysql/server-key.pem;socket.ssl_cert=/var/lib/mysql/server-cert.pem;socket.ssl_ca=/var/lib/mysql/ca.pem

                # Galera Cluster Configuration
                wsrep_cluster_name="'"$cluster_name"'"
                wsrep_cluster_address="gcomm://'"$node_ip"','"$cluster_ip_node2"','"$cluster_ip_node3"'"

                # Galera Synchronization Configuration
                wsrep_sst_method=xtrabackup-v2
                #wsrep-sst-auth=sstuser:P@ssw0rd

                # Galera Node Configuration
                wsrep_node_address="'"$node_ip"'"
                wsrep_node_name="'"$HOSTNAME"'"

                #Slave Thread to Use
                wsrep_slave_threads=8
                wsrep_log_conflicts

                ssl-key=/var/lib/mysql/server-key.pem
                ssl-ca=/var/lib/mysql/ca.pem
                ssl-cert=/var/lib/mysql/server-cert.pem

                #File Import Settings
                local_infile=ON
                secure-file-priv="/file"

                #logging settings
                log_error_verbosity = 2
                log_error_suppression_list = 'MY-013360'
                log_timestamps = 'SYSTEM'
                ' >> /etc/mysql/my.cnf
                systemctl start mysql@bootstrap
                    if systemctl is-active --quiet mysql@bootstrap; then
                    read -s -p "Enter MySQL root password: "mysql_password
                    mysql -uroot -p"$mysql_password" -e "CREATE FUNCTION fnv1a_64 RETURNS INTEGER SONAME 'libfnv1a_udf.so'"
                    mysql -uroot -p"$mysql_password" -e "CREATE FUNCTION fnv_64 RETURNS INTEGER SONAME 'libfnv_udf.so'"
                    mysql -uroot -p"$mysql_password" -e "CREATE FUNCTION murmur_hash RETURNS INTEGER SONAME 'libmurmur_udf.so'"

                    #mysql -e "CREATE FUNCTION fnv1a_64 RETURNS INTEGER SONAME 'libfnv1a_udf.so'"
                    #mysql -e "CREATE FUNCTION fnv_64 RETURNS INTEGER SONAME 'libfnv_udf.so'"
                    #mysql -e "CREATE FUNCTION murmur_hash RETURNS INTEGER SONAME 'libmurmur_udf.so'"
                        echo "mysql@bootstrap is running, you can now add other nodes to this cluster"
                        # below commented out as L1 not live so won't work.
                       # echo "Copying SSL certificates to additional nodes specified."
                       # ssh-keygen -t rsa -b 4096 -C "mesadmin" -q -f /root/.ssh/id_rsa
                       # ssh-copy-id mesadmin@"$cluster_ip_node2"
                       # ssh-copy-id mesadmin@"$cluster_ip_node3"
                       # scp /var/lib/mysql/ca.pem /var/lib/mysql/server-key.pem /var/lib/mysql/server-cert.pem
                       # mesadmin@"$cluster_ip_node2":/var/lib/mysql
                       # scp /var/lib/mysql/ca.pem /var/lib/mysql/server-key.pem /var/lib/mysql/server-cert.pem
                       # mesadmin@"$cluster_ip_node3":/var/lib/mysql
                        echo "Copying SSL certificates to additional nodes specified."
                        ssh-keygen -t rsa -b 4096 -C "$user" -q -f /root/.ssh/id_rsa
                        ssh-copy-id "$user"@"$cluster_ip_node2"
                        ssh-copy-id "$user"@"$cluster_ip_node3"
                        rsync -avrP /var/lib/mysql/ca.pem /var/lib/mysql/server-key.pem /var/lib/mysql/server-cert.pem mesadmin@"$cluster_ip_node2":/home/mesadmin;
                        rsync -avrP /var/lib/mysql/ca.pem /var/lib/mysql/server-key.pem /var/lib/mysql/server-cert.pem mesadmin@"$cluster_ip_node3":/home/mesadmin;
                        echo "Certificates copied to any online nodes specified. If either node was offline, these will need sending manually"

                        systemctl enable mysql@bootstrap
                        echo "mysql@bootstrap service is now set to run at startup"
                        echo "Bootstrapped node setup complete, config file created. Please review config files and set InnoDB parameters."
                        exit
                    else echo "mysql@bootstrap is not running, this will need further troubleshooting. See /var/lib/mysql/mysqld.log to help."
                    fi
            break
            exit
            ;;
            "Additional Node")
            echo "Additional Node Selected"
            rm /etc/mysql/my.cnf
            echo '
                [client]
                #socket=/var/lib/mysql/mysqld.sock

                [mysqld]
                server-id               = '"$server_id"'
                datadir                 = /var/lib/mysql
                #socket                 = /var/lib/mysql/mysqld.sock
                log-error               = /var/lib/mysql/mysqld.log
                pid-file                = /var/run/mysqld/mysqld.pid
                binlog_expire_logs_seconds      = 432000
                binlog_format           = ROW
                max_binlog_size         = 1024M
                default-storage-engine  = innodb
				
				#default charset
				character-set-server = utf8mb4
				collation-server = utf8mb4_0900_ai_ci
				init-connect='SET NAMES utf8mb4'

                disabled_storage_engines="MyISAM"
                max_allowed_packet= 1G
                innodb_autoinc_lock_mode= 2
                bind-address           = 0.0.0.0
                skip_name_resolve       = ON
                port                    = 3306
                #ssl                    = 0

                # InnoDB Performance Settings (If commented set manually)
                innodb_log_buffer_size=64M
                innodb_buffer_pool_size= '"${memory}G"'
                innodb_log_file_size=512M	
                innodb_buffer_pool_instances=8	
                innodb_thread_concurrency=0

                # Galera Provider Configuration
                wsrep_on=ON
                wsrep_provider=/usr/lib/galera4/libgalera_smm.so
                wsrep_provider_options=”socket.ssl_key=/var/lib/mysql/server-key.pem;socket.ssl_cert=/var/lib/mysql/server-cert.pem;socket.ssl_ca=/var/lib/mysql/ca.pem

                # Galera Cluster Configuration
                wsrep_cluster_name="'"$cluster_name"'"
                wsrep_cluster_address="gcomm://'"$node_ip"','"$cluster_ip_node2"','"$cluster_ip_node3"'"

                # Galera Synchronization Configuration
                wsrep_sst_method=xtrabackup-v2
                #wsrep-sst-auth=sstuser:P@ssw0rd

                # Galera Node Configuration
                wsrep_node_address="'"$node_ip"'"
                wsrep_node_name="'"$HOSTNAME"'"

                #Slave Thread to Use
                wsrep_slave_threads=8
                wsrep_log_conflicts

                ssl-key=/var/lib/mysql/server-key.pem
                ssl-ca=/var/lib/mysql/ca.pem
                ssl-cert=/var/lib/mysql/server-cert.pem

                #File Import Settings
                local_infile=ON
                secure-file-priv="/file"

                #logging settings
                log_error_verbosity = 2
                log_error_suppression_list = 'MY-013360'
                log_timestamps = 'SYSTEM'

                ' >> /etc/mysql/my.cnf
                echo "Sending SSH Certificates from mesadmin to /var/lib/mysql and changing owner."
                rsync -avrP /home/mesadmin/*.pem /var/lib/mysql
                chown -R --verbose mysql:mysql /var/lib/mysql
                systemctl start mysql
                if systemctl is-active --quiet mysql; then
                        echo "mysql is now running on this node and is part of the cluster. Setup complete, exiting."
                        systemctl enable mysql
                        echo "mysql service set to run on startup"
                        echo "Bootstrapped node setup complete, config file created. Please review config files and set InnoDB parameters."
                        exit 0
                    else echo "mysql is not running, this will need further troubleshooting. See /var/lib/mysql/mysqld.log to help."
                    fi
            break
            exit
            ;;
            "Copy SSL Certificates To Additional Nodes")
           echo "Copying SSL certificates to additional nodes specified."
                        ssh-keygen -t rsa -b 4096 -C "mesadmin" -q -f /root/.ssh/id_rsa
                        ssh-copy-id mesadmin@"$cluster_ip_node2"
                        ssh-copy-id mesadmin@"$cluster_ip_node3"
                        rsync -avrP /var/lib/mysql/ca.pem /var/lib/mysql/server-key.pem /var/lib/mysql/server-cert.pem mesadmin@"$cluster_ip_node2":/home/mesadmin;
                        rsync -avrP /var/lib/mysql/ca.pem /var/lib/mysql/server-key.pem /var/lib/mysql/server-cert.pem mesadmin@"$cluster_ip_node3":/home/mesadmin; 
                        echo "Certificates copied to any online nodes specified. If either node was offline, these will need sending manually"
                        exit 0
            ;;
            *) echo "Invalid option $REPLY";;
        esac
    done
exit 0
