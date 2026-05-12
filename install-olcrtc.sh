#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # Нет цвета

# Проверка на права root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Пожалуйста, запустите скрипт с правами root (sudo ./install-olcrtc.sh)${NC}"
  exit 1
fi

# Функция установки
install_olcrtc() {
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${GREEN}   Интерактивная установка OlcRTC (Сервер)       ${NC}"
    echo -e "${CYAN}=================================================${NC}"

    # 1. Запрос конфигурации
    echo -e "Выберите провайдера:"
    echo -e " 1) wbstream (по умолчанию)"
    echo -e " 2) telemost"
    echo -e " 3) jazz"
    read -p "Ваш выбор (1-3) [по умолчанию 1]: " prov_choice

    case $prov_choice in
        2) PROVIDER="telemost" ;;
        3) PROVIDER="jazz" ;;
        *) PROVIDER="wbstream" ;;
    esac

    read -p "Транспорт (datachannel, vp8channel) [по умолчанию datachannel]: " TRANSPORT
    TRANSPORT=${TRANSPORT:-datachannel}

    read -p "ID звонка (обязательно, например id_вашей_комнаты): " ROOM_ID
    while [ -z "$ROOM_ID" ]; do
        echo -e "${RED}Ошибка: ID звонка обязателен!${NC}"
        read -p "ID звонка: " ROOM_ID
    done

    read -p "Ключ шифрования (нажмите Enter для автогенерации 32 байт): " ENC_KEY
    if [ -z "$ENC_KEY" ]; then
        ENC_KEY=$(openssl rand -hex 32)
        echo -e "${YELLOW}Сгенерирован ключ: $ENC_KEY${NC}"
    fi

    read -p "ID Клиента (нажмите Enter для автогенерации): " CLIENT_ID
    if [ -z "$CLIENT_ID" ]; then
        CLIENT_ID=$(openssl rand -hex 4)
        echo -e "${YELLOW}Сгенерирован ID клиента: $CLIENT_ID${NC}"
    fi

    # Останавливаем при ошибках
    set -e

    # 2. Настройка Swap
    echo -e "\n${CYAN}[1/5] Настройка Swap (файла подкачки)...${NC}"
    if [ ! -f /swapfile ]; then
        fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap файл успешно создан.${NC}"
    else
        echo -e "${YELLOW}Swap файл уже существует, пропускаем.${NC}"
    fi

    # 3. Зависимости и Go
    echo -e "\n${CYAN}[2/5] Установка зависимостей и Go 1.26.2...${NC}"
    apt-get update && apt-get install -y git wget curl build-essential
    wget -qO go.tar.gz https://go.dev/dl/go1.26.2.linux-amd64.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go.tar.gz
    rm go.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo "export PATH=\$PATH:/usr/local/go/bin" > /etc/profile.d/go.sh

    # 4. Сборка
    echo -e "\n${CYAN}[3/5] Установка Mage и сборка OlcRTC...${NC}"
    cd ~
    rm -rf mage
    git clone https://github.com/magefile/mage
    cd mage
    /usr/local/go/bin/go run bootstrap.go
    
    cd ~
    rm -rf olcrtc
    git clone https://github.com/openlibrecommunity/olcrtc.git --recurse-submodules
    cd olcrtc
    ~/go/bin/mage build

    # 5. Настройка Systemd
    echo -e "\n${CYAN}[4/5] Настройка системной службы...${NC}"
    mkdir -p /opt/olcrtc
    cp build/olcrtc-linux-amd64 /opt/olcrtc/olcrtc

    cat <<EOF > /etc/systemd/system/olcrtc.service
[Unit]
Description=OlcRTC Proxy Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/olcrtc
ExecStart=/opt/olcrtc/olcrtc -mode srv -carrier $PROVIDER -transport $TRANSPORT -room "$ROOM_ID" -key "$ENC_KEY" -client-id "$CLIENT_ID"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable olcrtc
    systemctl restart olcrtc

    set +e # Отключаем прерывание при ошибках

    echo -e "\n${GREEN}=================================================${NC}"
    echo -e "${GREEN} УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e "Ваши данные для подключения в клиенте (Olcbox):"
    echo -e "Провайдер:\t${YELLOW}$PROVIDER${NC}"
    echo -e "Транспорт:\t${YELLOW}$TRANSPORT${NC}"
    echo -e "ID звонка:\t${YELLOW}$ROOM_ID${NC}"
    echo -e "Ключ:\t\t${YELLOW}$ENC_KEY${NC}"
    echo -e "ID клиента:\t${YELLOW}$CLIENT_ID${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo -e "URI для быстрого импорта:"
    echo -e "${YELLOW}olcrtc://$PROVIDER:$TRANSPORT@?room=$ROOM_ID&key=$ENC_KEY&client-id=$CLIENT_ID${NC}"
    echo -e "${CYAN}=================================================${NC}"
    
    read -p "Нажмите Enter, чтобы вернуться в меню..."
}

# Функция удаления
uninstall_olcrtc() {
    echo -e "\n${RED}ВНИМАНИЕ: Это действие удалит службу OlcRTC, все ее файлы и настройки.${NC}"
    read -p "Вы уверены, что хотите продолжить? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" && "$confirm" != "д" && "$confirm" != "Д" ]]; then
        echo -e "${YELLOW}Удаление отменено.${NC}"
        sleep 1
        return
    fi

    echo -e "${CYAN}Остановка и удаление службы...${NC}"
    systemctl stop olcrtc 2>/dev/null || true
    systemctl disable olcrtc 2>/dev/null || true
    rm -f /etc/systemd/system/olcrtc.service
    systemctl daemon-reload

    echo -e "${CYAN}Удаление рабочих директорий и исходников...${NC}"
    rm -rf /opt/olcrtc
    rm -rf ~/olcrtc
    rm -rf ~/mage

    read -p "Удалить установленный язык программирования Go? (y/n): " remove_go
    if [[ "$remove_go" == "y" || "$remove_go" == "Y" ]]; then
        rm -rf /usr/local/go
        rm -f /etc/profile.d/go.sh
        echo -e "${GREEN}Go успешно удален.${NC}"
    fi

    read -p "Удалить файл подкачки (/swapfile)? (Если на сервере мало ОЗУ, лучше оставить) (y/n): " remove_swap
    if [[ "$remove_swap" == "y" || "$remove_swap" == "Y" ]]; then
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
        sed -i '/\/swapfile/d' /etc/fstab
        echo -e "${GREEN}Файл подкачки удален.${NC}"
    fi

    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN} OlcRTC и связанные компоненты успешно удалены!  ${NC}"
    echo -e "${GREEN} Система возвращена к исходному состоянию.       ${NC}"
    echo -e "${GREEN}=================================================${NC}"
    
    read -p "Нажмите Enter, чтобы вернуться в меню..."
}

# Главное меню
while true; do
    clear
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${YELLOW}         Установщик OlcRTC Proxy Server          ${NC}"
    echo -e "${CYAN}=================================================${NC}"
    echo -e " 1) Установить OlcRTC (полная автоматическая настройка)"
    echo -e " 2) Удалить OlcRTC (возврат к начальным установкам)"
    echo -e " 3) Проверить статус работы (логи сервера)"
    echo -e " 0) Выход"
    echo -e "${CYAN}=================================================${NC}"
    read -p "Выберите действие (0-3): " choice

    case $choice in
        1)
            install_olcrtc
            ;;
        2)
            uninstall_olcrtc
            ;;
        3)
            echo -e "${CYAN}Последние логи службы OlcRTC (Ctrl+C для выхода):${NC}"
            journalctl -u olcrtc -f -n 20
            ;;
        0)
            echo -e "${GREEN}Выход из скрипта. Удачи!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный ввод. Пожалуйста, выберите от 0 до 3.${NC}"
            sleep 1
            ;;
    esac
done
