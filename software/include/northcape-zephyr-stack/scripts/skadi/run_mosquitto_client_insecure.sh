#!/bin/sh

mosquitto_sub -p 1883 -t sensors -u foo -P bar --insecure
