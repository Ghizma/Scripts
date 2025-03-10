#!/bin/bash

# Цвета текста
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # Нет цвета (сброс цвета)

# Проверка наличия curl и установка, если не установлен
if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Installing curl...${NC}"
    sudo apt update
    sudo apt install curl -y
fi

# Отображаем логотип
curl -s https://raw.githubusercontent.com/noxuspace/cryptofortochka/main/logo_forto.sh | bash

# Скачиваем node_exporter, разархивируем, настраиваем права и удаляем ненужное
cd $HOME || exit
wget https://github.com/prometheus/node_exporter/releases/download/v1.2.0/node_exporter-1.2.0.linux-amd64.tar.gz
tar xvf node_exporter-1.2.0.linux-amd64.tar.gz
rm -f node_exporter-1.2.0.linux-amd64.tar.gz
sudo mv node_exporter-1.2.0.linux-amd64 node_exporter
sudo chmod +x $HOME/node_exporter/node_exporter
sudo mv $HOME/node_exporter/node_exporter /usr/bin
sudo rm -rf $HOME/node_exporter

# Создаем директорию для сбора метрик по сервисам
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chmod 755 /var/lib/node_exporter/textfile_collector
sudo chown root:root /var/lib/node_exporter/textfile_collector

# Создаем файл сервиса exporterd
sudo tee /etc/systemd/system/exporterd.service > /dev/null <<EOF
[Unit]
Description=node_exporter
After=network-online.target

[Service]
User=root
ExecStart=/usr/bin/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Запускаем сервис exporterd
sudo systemctl daemon-reload
sudo systemctl enable exporterd
sudo systemctl restart exporterd

# Открываем порт 9100
sudo ufw allow 9100

# Создаем скрипт сбора метрик по сервисам и контейнерам Docker
sudo tee /root/check_services.sh > /dev/null <<'EOF'
#!/bin/bash

# Файл для сохранения метрик
METRICS_FILE="/var/lib/node_exporter/textfile_collector/services.prom"

# Список сервисов для проверки
services=("hemi.service" "cysic.service" "squid.service" "pipe-pop.service" "initverse.service" "dria.service" "vana.service")

# Очищаем файл метрик перед записью новых данных
> "$METRICS_FILE"

# Функция для проверки существования сервиса
service_exists() {
    local service=$1
    if systemctl list-unit-files "$service" &> /dev/null; then
        return 0 # Сервис существует
    else
        return 1 # Сервис не существует
    fi
}

# Функция для проверки состояния сервиса и генерации метрик
check_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        echo "service_status{name=\"$service\"} 1" >> "$METRICS_FILE"
    else
        echo "service_status{name=\"$service\"} 0" >> "$METRICS_FILE"
    fi
}

# Проверяем каждый сервис из списка только если он существует
for service in "${services[@]}"; do
    if service_exists "$service"; then
        check_service "$service"
    else
        echo "Service '$service' does not exist. Skipping..." >&2
    fi
done

# Получаем все контейнеры Docker и их состояние
if command -v docker &> /dev/null; then
    for container in \$(docker ps -aq); do
        status=\$(docker inspect -f '{{.State.Running}}' "\$container")
        if [ "\$status" == "true" ]; then
            state=1
        else
            state=0
        fi
        # Добавляем метрику в файл
        echo "docker_container_running{container_id=\"\$container\",container_name=\"\$(docker inspect -f '{{.Name}}' "\$container" | sed 's/\///')\"} \$state" >> "\$METRICS_FILE"
    done
else
    echo "Docker is not installed or not available." >&2
fi

# Устанавливаем правильные права доступа к файлу метрик
chmod 644 "\$METRICS_FILE"
EOF

# Делаем скрипт исполняемым
sudo chmod +x /root/check_services.sh

# Добавляем cronjob для периодического запуска скрипта каждые 30 секунд
(crontab -l ; echo "*/1 * * * * /root/check_services.sh") | crontab -
echo -e "${GREEN}Cronjob added to run the script every minute.${NC}"

echo -e "${GREEN}Installation and configuration completed successfully!${NC}"