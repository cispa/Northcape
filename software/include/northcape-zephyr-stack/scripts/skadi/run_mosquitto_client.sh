#!/bin/sh

mosquitto_sub -p 8883 --cafile scripts/skadi/mosquitto-ca/ca.crt -t sensors --insecure -u foo -P bar
