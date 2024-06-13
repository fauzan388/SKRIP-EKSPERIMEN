#!/bin/bash

# Load configuration if exists
CONFIG_FILE="/boot/firmware/PPPwn/config.sh"
if [ -f $CONFIG_FILE ]; then
    source $CONFIG_FILE
else
    INTERFACE="eth0"
    FIRMWAREVERSION="11.00"
    SHUTDOWN=true
    USBETHERNET=false
    PPPOECONN=false
    USECPP=true
fi

# Default USECPP to true if not set
: ${USECPP:=true}

# Get Raspberry Pi model
PITYP=$(tr -d '\0' </proc/device-tree/model)

# Determine the appropriate binary based on Raspberry Pi model
case $PITYP in
    *"Raspberry Pi 2"*) CPPBIN="pppwn7"; TIMEOUT=15 ;;
    *"Raspberry Pi 3"*) CPPBIN="pppwn64"; TIMEOUT=10 ;;
    *"Raspberry Pi 4"*) CPPBIN="pppwn64"; TIMEOUT=5 ;;
    *"Raspberry Pi 5"*) CPPBIN="pppwn64"; TIMEOUT=5 ;;
    *"Raspberry Pi Zero 2"*) CPPBIN="pppwn64"; TIMEOUT=8 ;;
    *"Raspberry Pi Zero"*) CPPBIN="pppwn11"; TIMEOUT=10 ;;
    *"Raspberry Pi"*) CPPBIN="pppwn11"; TIMEOUT=15 ;;
    *) CPPBIN="pppwn64"; TIMEOUT=5 ;;
esac

# Adjust binary for 32-bit architecture
if [ $(getconf LONG_BIT) -eq 32 ] && [ $CPPBIN = "pppwn64" ]; then
    CPPBIN="pppwn7"
fi

# Display banner
cat << 'EOF' | sudo tee /dev/tty1
\n\n\033[36m /$$   /$$ /$$$$$$$  /$$$$$$$   /$$$$$$  /$$   /$$         /$$       /$$$$$$$   /$$$$$$ 
| $$  | $$| $$__  $$| $$__  $$ /$$__  $$| $$$ | $$        | $$      | $$__  $$ /$$__  $$
| $$  | $$| $$  \ $$| $$  \ $$| $$  \ $$| $$$$| $$        | $$      | $$  \ $$| $$  \__/
| $$  | $$| $$$$$$$/| $$$$$$$ | $$$$$$$$| $$ $$ $$ /$$$$$$| $$      | $$$$$$$/| $$ /$$$$ \\
| $$  | $$| $$__  $$| $$__  $$| $$__  $$| $$  $$$$|______/| $$      | $$____/ | $$|_  $$
| $$  | $$| $$  \ $$| $$  \ $$| $$  | $$| $$\  $$$        | $$      | $$      | $$  \ $$
|  $$$$$$/| $$  | $$| $$$$$$$/| $$  | $$| $$ \  $$        | $$$$$$$$| $$      |  $$$$$$/
 \______/ |__/  |__/|_______/ |__/  |__/|__/  \__/        |________/|__/       \______/ \033[0m
\n\033[33mhttps://github.com/TheOfficialFloW/PPPwn\033[0m\n
EOF

# Configure network interface
if [ $USBETHERNET = true ]; then
    echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/unbind
    sleep 2
    echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/bind
    sleep 5
else
    sudo ip link set $INTERFACE down
    sleep 5
    sudo ip link set $INTERFACE up
fi

# Display device information
echo -e "\n\033[36m$PITYP\033[0m\n\033[32mReady for console connection\033[92m\nFirmware:\033[93m $FIRMWAREVERSION\033[92m\nInterface:\033[93m $INTERFACE\033[0m" | sudo tee /dev/tty1

# Display internet access status if PPPOECONN is true
if [ $PPPOECONN = true ]; then
    echo -e "\033[93mInternet Access Enabled\033[0m" | sudo tee /dev/tty1
fi

# Display IP address if available
PIIP=$(hostname -I) || true
if [ "$PIIP" ]; then
    echo -e "\033[92mIP: \033[93m $PIIP\033[0m" | sudo tee /dev/tty1
fi

# Main loop
while true; do
    if [ $USECPP = true ]; then
        ret=$(sudo /boot/firmware/PPPwn/$CPPBIN --interface "$INTERFACE" --fw "${FIRMWAREVERSION//.}" --stage1 "/boot/firmware/PPPwn/stage1_$FIRMWAREVERSION.bin" --stage2 "/boot/firmware/PPPwn/stage2_$FIRMWAREVERSION.bin")
    else
        ret=$(sudo python3 /boot/firmware/PPPwn/pppwn.py --interface=$INTERFACE --fw=$FIRMWAREVERSION --stage1=/boot/firmware/PPPwn/stage1_$FIRMWAREVERSION.bin --stage2=/boot/firmware/PPPwn/stage2_$FIRMWAREVERSION.bin")
    fi
    
    if [ $ret -ge 1 ]; then
        echo -e "\033[32m\nConsole PPPwned! \033[0m\n" | sudo tee /dev/tty1
        
        if [ $PPPOECONN = true ]; then
            if [ $USBETHERNET = true ]; then
                echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/unbind
                sleep 3
                echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/bind
            else    
                sudo ip link set $INTERFACE down
                sleep 3
                sudo ip link set $INTERFACE up
            fi
            
            sleep 3
            sudo sysctl net.ipv4.ip_forward=1
            sudo sysctl net.ipv4.conf.all.route_localnet=1
            sudo iptables -t nat -I PREROUTING -s 192.168.2.0/24 -p udp -m udp --dport 53 -j DNAT --to-destination 127.0.0.1:5353
            sudo iptables -t nat -I PREROUTING -p tcp --dport 2121 -j DNAT --to 192.168.2.2:2121
            sudo iptables -t nat -I PREROUTING -p tcp --dport 3232 -j DNAT --to 192.168.2.2:3232
            sudo iptables -t nat -I PREROUTING -p tcp --dport 9090 -j DNAT --to 192.168.2.2:9090
            sudo iptables -t nat -A POSTROUTING -s 192.168.2.0/24 ! -d 192.168.2.0/24 -j MASQUERADE
            echo -e "\n\n\033[93m\nPPPoE Enabled \033[0m\n" | sudo tee /dev/tty1
            sudo pppoe-server -I $INTERFACE -T 60 -N 1 -C PS4 -S PS4 -L 192.168.2.1 -R 192.168.2.2 -F
        else
            if [ $SHUTDOWN = true ]; then
                sudo poweroff
            else
                sudo ip link set $INTERFACE down
            fi
        fi
        exit 1
    else
        echo -e "\033[31m\nFailed retrying...\033[0m\n" | sudo tee /dev/tty1
        
        if [ $USBETHERNET = true ]; then
            echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/unbind
            sleep 4
            echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/bind
        else    
            sudo ip link set $INTERFACE down
            sleep 4
            sudo ip link set $INTERFACE up
        fi
    fi
done
