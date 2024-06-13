#!/bin/bash

# raspberry pi ethernet interface
INTERFACE="eth0" 

# console firmware version  [11.00 | 9.00]
FIRMWAREVERSION="11.00" 

# shutdown pi on successful pppwn  [true | false]
SHUTDOWN=true

# using a usb to ethernet adapter  [true | false]
USBETHERNET=false

#use c++ version of pppwn
USECPP=true

# enable pppoe after pwn  [true | false]
#this does not work if you did not set the console to connect to the internet during the install
PPPOECONN=false
