#!/bin/sh
sudo killall mosquitto && sleep 2
mosquitto -v -c scripts/skadi/mosquitto_insecure.conf
