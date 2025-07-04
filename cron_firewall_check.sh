  #!/bin/bash
  #Simple script that first checks that firewall is running, then ensures all rules required for operation are running.
  #First I will check this works with instructions within bash script, then store the firewall rules in a text file so it can be parsed as a variable.
if systemctl is-active --quiet ufw; then
    echo "Firewall service is running, checking to see if firewall is enabled"
    if ufw enable < <(echo "y"); then
    echo "Firewall running, woohoo!"
    else 
    echo "Firewall not running, oh no!"
    fi
else echo "Firewall is not active, activating and ensuring rules are added"
    systemctl enable ufw
    systemctl start ufw
    ufw enable
        
    #For all boxes
    sudo ufw allow 3306/tcp
    sudo ufw allow 22/tcp
    sudo ufw allow 22/udp
    sudo ufw allow 10.100.23.0/24
    sudo ufw allow 10.200.23.0/24
    sudo ufw allow 443/tcp
    sudo ufw allow 53/tcp
    #PerconaXtraDB Specific
    sudo ufw allow 4444
    sudo ufw allow 4567
    sudo ufw allow 4568
    #Samba Specific
    sudo ufw allow 445
    sudo ufw allow 135
    #Syncthing Specific
    sudo ufw allow 22000/tcp
    sudo ufw allow 8384
    #ProxySQL Specific
    sudo ufw allow 6032
    sudo ufw allow 6033
    #HAProxy Specific
    sudo ufw allow 6023
    exit 0
fi

exit 0