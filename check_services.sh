#!/bin/bash

#export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"


# STABILIM LOCATIA FISIERULUI DE METRICE

METRICS_FILE="/var/lib/node_exporter/textfile_collector/services.prom"


# Lista de servicii de verificat
services=("hemi.service" "cysic.service" "squid.service" "pipe-pop.service" "initverse.service" "dria.service" "vana.service" "gaia-bot.service" "t3rn.service")

# Lista de procese de verificat (poți adăuga mai multe aici)
processes=("multiple-node")

# Golim fișierul înainte de a scrie noile date
> "$METRICS_FILE"

# Funcție pentru verificarea existenței unui serviciu
service_exists() {
    systemctl list-unit-files "$1" &> /dev/null
}

# Funcție pentru verificarea unui serviciu și generarea metricilor
check_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        echo "service_status{name=\"$service\"} 1" >> "$METRICS_FILE"
    else
        echo "service_status{name=\"$service\"} 0" >> "$METRICS_FILE"
    fi
}

# Verifică și salvează doar serviciile existente
for service in "${services[@]}"; do
    if service_exists "$service"; then
        check_service "$service"
    fi
done

# Obține toate containerele Docker și starea lor
for container in $(docker ps -aq); do
    status=$(docker inspect -f '{{.State.Running}}' "$container")
    state=0
    [[ "$status" == "true" ]] && state=1
    echo "service_status{name=\"$(docker inspect -f '{{.Name}}' "$container" | sed 's/\///')\"} $state" >> "$METRICS_FILE"
done

# Verifică existența și starea procesului gaianet
GAIANET_STATUS="0"

if [[ -x "/root/gaianet/bin/gaias" && -x "/root/gaianet/bin/frpc" ]]; then
    GAIAS_PID=$(pgrep -x "gaias")
    FRPC_PID=$(pgrep -x "frpc")

    if [[ -n "$GAIAS_PID" && -n "$FRPC_PID" ]]; then
        GAIANET_STATUS="1"
    fi

    echo "service_status{name=\"gaianet\"} $GAIANET_STATUS" >> "$METRICS_FILE"
fi

# Verifică existența și starea proceselor din lista 'processes'
for process in "${processes[@]}"; do

    if ps aux | grep -v grep | grep -q "$process"; then

        PROCESS_CPU=$(ps -eo comm,%cpu --no-headers | grep -F "$process" | awk '{print $2}')
        
        if [[ -n "$PROCESS_CPU" ]]; then
            if (( $(echo "$PROCESS_CPU > 0" | bc -l) )); then
                echo "service_status{name=\"$process\"} 1" >> "$METRICS_FILE"
            else
                echo "service_status{name=\"$process\"} 0" >> "$METRICS_FILE"
            fi
        else
            echo "service_status{name=\"$process\"} 0" >> "$METRICS_FILE"
        fi
    fi
done

# Setează permisiuni corecte
chmod 644 "$METRICS_FILE"
