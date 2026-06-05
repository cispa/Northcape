#!/bin/bash
echo "Sending 100 UDP packets and awaiting response"
(for i in {1..100}; do echo -e "Hello zephyr $i\0"; sleep 1; done && sleep 110) > >(nc -u 192.0.2.1 8080);
echo "Test complete"
