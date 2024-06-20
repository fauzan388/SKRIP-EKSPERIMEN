#!/bin/bash

if [ ! -f /boot/firmware/PPPwn/config.sh ]; then
    # Jika Anda memiliki file config.sh, Anda perlu mengedit nilai-nilai ini di file tersebut bukan di sini
    INTERFACE="eth0" 
    FIRMWAREVERSION="11.00" 
    SHUTDOWN=true
    USBETHERNET=false
    PPPOECONN=false
    USECPP=true
else
    source /boot/firmware/PPPwn/config.sh
fi

if [[ -z $USECPP ]]; then
    USECPP=true
fi

PITYP=$(tr -d '\0' </proc/device-tree/model) 

if [[ $PITYP == *"Raspberry Pi 2"* ]]; then
    coproc read -t 15 && wait "$!" || true
    CPPBIN="pppwn7"
elif [[ $PITYP == *"Raspberry Pi 3"* || $PITYP == *"Raspberry Pi 4"* || $PITYP == *"Raspberry Pi 5"* || $PITYP == *"Raspberry Pi Zero 2"* ]]; then
    coproc read -t 5 && wait "$!" || true
    CPPBIN="pppwn64"
elif [[ $PITYP == *"Raspberry Pi Zero"* || $PITYP == *"Raspberry Pi"* ]]; then
    coproc read -t 10 && wait "$!" || true
    CPPBIN="pppwn11"
else
    coproc read -t 5 && wait "$!" || true
    CPPBIN="pppwn64"
fi

arch=$(getconf LONG_BIT)
if [ $arch -eq 32 ] && [ $CPPBIN = "pppwn64" ]; then
    CPPBIN="pppwn7"
fi

# ASCII art yang ingin disisipkan
ASCII_ART='
\033[36m
 /$$   /$$ /$$$$$$$  /$$$$$$$   /$$$$$$  /$$   /$$         /$$       /$$$$$$$   /$$$$$$ 
| $$  | $$| $$__  $$| $$__  $$ /$$__  $$| $$$ | $$        | $$      | $$__  $$ /$$__  $$
| $$  | $$| $$  \ $$| $$  \ $$| $$  \ $$| $$$$| $$        | $$      | $$  \ $$| $$  \__/
| $$  | $$| $$$$$$$/| $$$$$$$ | $$$$$$$$| $$ $$ $$ /$$$$$$| $$      | $$$$$$$/| $$ /$$$$
| $$  | $$| $$__  $$| $$__  $$| $$__  $$| $$  $$$$|______/| $$      | $$____/ | $$|_  $$
| $$  | $$| $$  \ $$| $$  \ $$| $$  | $$| $$\  $$$        | $$      | $$      | $$  \ $$
|  $$$$$$/| $$  | $$| $$$$$$$/| $$  | $$| $$ \  $$        | $$$$$$$$| $$      |  $$$$$$/
 \______/ |__/  |__/|_______/ |__/  |__/|__/  \__/        |________/|__/       \______/ \033[0m
\n'

# Cetak ASCII art ke terminal
echo -e "$ASCII_ART" | sudo tee /dev/tty1

# Lanjutkan dengan bagian lain dari skrip Anda
if [ $USBETHERNET = true ]; then
    echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/unbind
    coproc read -t 2 && wait "$!" || true
    echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/bind
    coproc read -t 5 && wait "$!" || true
    sudo ip link set $INTERFACE up
else
    sudo ip link set $INTERFACE down
    coproc read -t 5 && wait "$!" || true
    sudo ip link set $INTERFACE up
fi

echo -e "\n\033[36m$PITYP\033[0m\n\033[32mReady for console connection\033[92m\nFirmware:\033[93m $FIRMWAREVERSION\033[92m\nInterface:\033[93m $INTERFACE\033[0m" | sudo tee /dev/tty1

if [ $PPPOECONN = true ]; then
    echo -e "\033[93mInternet Access Enabled\033[0m" | sudo tee /dev/tty1
fi

PIIP=$(hostname -I) || true
if [ "$PIIP" ]; then
    echo -e "\033[92mIP: \033[93m $PIIP\033[0m" | sudo tee /dev/tty1
fi

while true; do
    if [ $USECPP = true ]; then
        ret=$(sudo /boot/firmware/PPPwn/$CPPBIN --interface "$INTERFACE" --fw "${FIRMWAREVERSION//.}" --stage1 "/boot/firmware/PPPwn/stage1_$FIRMWAREVERSION.bin" --stage2 "/boot/firmware/PPPwn/stage2_$FIRMWAREVERSION.bin" --timeout 10 --auto-retry
    else
        ret=$(sudo python3 /boot/firmware/PPPwn/pppwn.py --interface=$INTERFACE --fw=$FIRMWAREVERSION --stage1=/boot/firmware/PPPwn/stage1_$FIRMWAREVERSION.bin --stage2=/boot/firmware/PPPwn/stage2_$FIRMWAREVERSION.bin)
    fi

    if [ $ret -ge 1 ]; then
        echo -e "\033[32m\nConsole PPPwned! \033[0m\n" | sudo tee /dev/tty1

        if [ $PPPOECONN = true ]; then
            if [ $USBETHERNET = true ]; then
                echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/unbind
                coproc read -t 3 && wait "$!" || true
                echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/bind
            else
                sudo ip link set $INTERFACE down
            fi

            coproc read -t 3 && wait "$!" || true
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
            coproc read -t 4 && wait "$!" || true
            echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/bind
        else
            sudo ip link set $INTERFACE down
            coproc read -t 4 && wait "$!" || true
            sudo ip link set $INTERFACE up
        fi
    fi
done
