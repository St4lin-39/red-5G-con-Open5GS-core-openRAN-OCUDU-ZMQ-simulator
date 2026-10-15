#!/bin/bash

# Esperar hasta 60 segundos a que srsUE cree tun_srsue dentro de ue1
for i in {1..60}; do
    if ip netns exec ue1 ip link show tun_srsue >/dev/null 2>&1; then
        ip netns exec ue1 ip route replace default dev tun_srsue
        exit 0
    fi

    sleep 1
done

echo "tun_srsue no apareció dentro de ue1 después de 60 segundos"
exit 1
