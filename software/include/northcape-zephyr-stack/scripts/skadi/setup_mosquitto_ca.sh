#!/bin/sh

set -e

echo "Preparing OpenSSL CA for Mosquitto"

cd scripts/skadi

rm -r mosquitto-ca || true 
mkdir mosquitto-ca

cd mosquitto-ca

echo "Generating CA"

openssl req -nodes -new -x509 -subj "/C=AU"  -days 3600 -extensions v3_ca -keyout ca.key -out ca.crt

echo "Copying CA cert to sample application"
cat ca.crt | sed -e '1d;$d' | base64 -d |xxd -i > ../../../samples/boards/openhwgroup/cv64a6/mqtt_bench/src/ca_cert.inc

echo "Generating Server key and cert"
openssl genrsa -out server.key 2048
openssl req -out server.csr -subj "/C=AU/ST=ACT/L=Canberra/O=Example.inc/OU=Foobar/CN=foo.bar" -key server.key -new

echo "Signing server cert"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 3600

echo "Generating DH parameters"
openssl dhparam -out dhparam.pem 2048

cat ca.crt server.crt > fullchain.crt

echo "Generating password file"
touch mosquitto.pwd
mosquitto_passwd -b mosquitto.pwd foo bar
