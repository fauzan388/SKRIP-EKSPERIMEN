#!/bin/bash

VERBOSE=true

log() {
    if [ "$VERBOSE" = true ]; then
        echo "$1" | sudo tee /dev/tty1
    fi
}

log "Starting script..."

if [ ! -f /boot/firmware/PPPwn/config.sh ]; then
    log "Config file not found. Using default settings."
    # Jika Anda memiliki file config.sh, Anda perlu mengedit nilai-nilai ini di file tersebut bukan di sini
    INTERFACE="eth0" 
    FIRMWAREVERSION="11.00" 
    SHUTDOWN=true
    USBETHERNET=false
    PPPOECONN=false
    USECPP=true
else
    log "Loading config file."
    source /boot/firmware/PPPwn/config.sh
fi

if [[ -z $USECPP ]]; then
    USECPP=true
fi

PITYP=$(tr -d '\0' </proc/device-tree/model)
log "Detected device type: $PITYP"

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
log "System architecture: $arch-bit"

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
log "Printing ASCII art."
echo -e "$ASCII_ART" | sudo tee /dev/tty1

# Lanjutkan dengan bagian lain dari skrip Anda
if [ $USBETHERNET = true ]; then
    log "Configuring USB Ethernet."
    echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/unbind
    coproc read -t 2 && wait "$!" || true
    echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/bind
    coproc read -t 5 && wait "$!" || true
    sudo ip link set $INTERFACE up
else
    log "Configuring Ethernet interface."
    sudo ip link set $INTERFACE down
    coproc read -t 5 && wait "$!" || true
    sudo ip link set $INTERFACE up
fi

log "Device Type: $PITYP"
log "Ready for console connection"
log "Firmware: $FIRMWAREVERSION"
log "Interface: $INTERFACE"

if [ $PPPOECONN = true ]; then
    log "Internet Access Enabled"
fi

PIIP=$(hostname -I) || true
if [ "$PIIP" ]; then
    log "IP: $PIIP"
fi

while true; do
    if [ $USECPP = true ]; then
        log "Executing $CPPBIN binary."
        ret=$(sudo /boot/firmware/PPPwn/$CPPBIN --interface "$INTERFACE" --fw "${FIRMWAREVERSION//.}" --stage1 "/boot/firmware/PPPwn/stage1_$FIRMWAREVERSION.bin" --stage2 "/boot/firmware/PPPwn/stage2_$FIRMWAREVERSION.bin")
    else
        log "Executing Python script."
        ret=$(sudo python3 /boot/firmware/PPPwn/pppwn.py --interface=$INTERFACE --fw=$FIRMWAREVERSION --stage1=/boot/firmware/PPPwn/stage1_$FIRMWAREVERSION.bin --stage2=/boot/firmware/PPPwn/stage2_$FIRMWAREVERSION.bin)
    fi

    if [ $ret -ge 1 ]; then
        log "Console PPPwned!"

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
            log "PPPoE Enabled"
            sudo pppoe-server -I $INTERFACE -T 60 -N 1 -C PS4 -S PS4 -L 192.168.2.1 -R 192.168.2.2 -F
        else
            if [ $SHUTDOWN = true ]; then
                log "Shutting down system."
                sudo poweroff
            else
                sudo ip link set $INTERFACE down
            fi
        fi

        exit 1
    else
        log "Failed retrying..."

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
