#!/bin/bash

# Verificar que exista el namespace ue1
if ! ip netns list | grep -qw ue1; then
    echo "ERROR: El namespace ue1 no existe."
    exit 1
fi

# Preparar en segundo plano la ruta cuando aparezca tun_srsue
/usr/local/sbin/configure-srsue-route.sh &

# Iniciar srsUE
cd /home/david/5g-project/srsRAN_4G/build || exit 1
exec ./srsue/src/srsue ue-5g-zmq.conf
