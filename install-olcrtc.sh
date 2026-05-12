#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # Нет цвета

# Проверка на права root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Пожалуйста, запустите скрипт с правами root (sudo ./install.sh)${NC}"
  exit 1
fi

# Отключаем интерактивные окна для apt-get на весь сеанс
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Функция установки
install_olcrtc() {
    echo -e "${CYAN}=================================================${NC}"
    echo -e "${GREEN}   Интерактивная установка OlcRTC (Сервер)       ${NC}"
    echo -e "${CYAN}=================================================${NC}"

    # --- 1. ВЫБОР ПРОВАЙДЕРА ---
    echo -e "${CYAN}Выберите провайдера:${NC}"
    echo -e " 1) wbstream (по умолчанию)"
    echo -e " 2) telemost"
    echo -e " 3) jazz"
    read -p "Ваш выбор (1-3) [по умолчанию 1]: " prov_choice

    case $prov_choice in
        2) PROVIDER="telemost" ;;
        3) PROVIDER="jazz" ;;
        *) PROVIDER="wbstream" ;;
    esac

    # --- 2. ВЫБОР ТРАНСПОРТА ---
    echo -e "\n${CYAN}Выберите тип транспорта:${NC}"
    echo -e " 1) datachannel (максимальная скорость) [по умолчанию]"
    echo -e " 2) vp8channel  (высокая скорость)"
    echo -e " 3) seichannel  (средняя скорость)"
    echo -e " 4) videochannel (низкая скорость)"
    read -p "Ваш выбор (1-4) [по умолчанию 1]: " trans_choice

    case $trans_choice in
        2) TRANSPORT="vp8channel" ;;
        3) TRANSPORT="seichannel" ;;
        4) TRANSPORT="videochannel" ;;
        *) TRANSPORT="datachannel" ;;
    esac

    # --- 3. ВЫБОР ID ЗВОНКА ---
    echo -e "\n${CYAN}Настройка ID звонка (комнаты):${NC}"
    if [[ "$PROVIDER" == "wbstream" || "$PROVIDER" == "jazz" ]]; then
        echo -e " 1) Сгенерировать ID автоматически (рекомендуется)"
        echo -e " 2) Ввести ID звонка вручную"
        read -p "Ваш выбор (1-2) [по умолчанию 1]: " room_choice
        
        if [[ "$room_choice" == "2" ]]; then
            AUTO_ROOM=false
            read -p "Введите ID звонка: " ROOM_ID
            while [ -z "$ROOM_ID" ]; do
                echo -e "${RED}Ошибка: ID звонка обязателен!${NC}"
                read -p "Введите ID звонка: " ROOM_ID
            done
        else
            AUTO_ROOM=true
            echo -e "${YELLOW}ID звонка будет сгенерирован автоматически после компиляции сервера.${NC}"
        fi
    else
        # Для telemost автогенерация не поддерживается
        echo -e "${YELLOW}Для провайдера telemost доступен только ручной ввод ID звонка.${NC}"
        AUTO_ROOM=false
        read -p "Введите ID звонка: " ROOM_ID
        while [ -z "$ROOM_ID" ]; do
            echo -e "${RED}Ошибка: ID звонка обязателен!${NC}"
            read -p "Введите ID звонка: " ROOM_ID
        done
    fi

    # --- 4. ВЫБОР КЛЮЧА ШИФРОВАНИЯ ---
    echo -e "\n${CYAN}Настройка ключа шифрования:${NC}"
    echo -e " 1) Сгенерировать надежный ключ автоматически (рекомендуется)"
    echo -e " 2) Ввести свой ключ вручную"
    read -p "Ваш выбор (1-2) [по умолчанию 1]: " key_choice
    
    if [[ "$key_choice" == "2" ]]; then
        read -p "Введите ключ шифрования: " ENC_KEY
        while [ -z "$ENC_KEY" ]; do
             echo -e "${RED}Ошибка: Ключ не может быть пустым!${NC}"
             read -p "Введите ключ шифрования: " ENC_KEY
        done
    else
        ENC_KEY=$(openssl rand -hex 32)
        echo -e "${YELLOW}Сгенерирован ключ: $ENC_KEY${NC}"
    fi

    # --- 5. ВЫБОР ID КЛИЕНТА ---
    echo -e "\n${CYAN}Настройка ID клиента:${NC}"
    echo -e " 1) Сгенерировать автоматически (рекомендуется)"
    echo -e " 2) Ввести вручную"
    read -p "Ваш выбор (1-2) [по умолчанию 1]: " client_choice
    
    if [[ "$client_choice" == "2" ]]; then
        read -p "Введите ID клиента: " CLIENT_ID
        while [ -z "$CLIENT_ID" ]; do
             echo -e "${RED}Ошибка: ID клиента не может быть пустым!${NC}"
             read -p "Введите ID клиента: " CLIENT_ID
        done
    else
        CLIENT_ID=$(openssl rand -hex 4)
        echo -e "${YELLOW}Сгенерирован ID клиента: $CLIENT_ID${NC}"
    fi

    echo -e "${CYAN}=================================================${NC}"
    echo -e "${YELLOW}Начинаем установку. Пожалуйста, подождите...${NC}"
    
    # Останавливаем при ошибках
    set -e

    # ПРОВЕРКА ОС И ОБНОВЛЕНИЕ ПАКЕТОВ
    echo -e "\n${CYAN}[1/7] Проверка системы и обновление пакетов ОС...${NC}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            echo -e "${YELLOW}Предупреждение: Ваш дистрибутив ($ID) может не поддерживаться в полной мере. Рекомендуется Ubuntu или Debian.${NC}"
            sleep 3
        fi
    fi
    apt-get update -q && apt-get upgrade -yq

    # Настройка Swap
    echo -e "\n${CYAN}[2/7] Настройка Swap (файла подкачки)...${NC}"
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

    # Зависимости и Go
    echo -e "\n${CYAN}[3/7] Установка зависимостей и Go 1.26.2...${NC}"
    apt-get install -yq git wget curl build-essential
    wget -qO go.tar.gz https://go.dev/dl/go1.26.2.linux-amd64.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go.tar.gz
    rm go.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo "export PATH=\$PATH:/usr/local/go/bin" > /etc/profile.d/go.sh

    # Установка Mage (с исправлением ошибки создания директории)
    echo -e "\n${CYAN}[4/7] Установка системы сборки Mage...${NC}"
    mkdir -p ~/go/bin # <-- ИСПРАВЛЕНИЕ ТУТ
    export GOPATH=~/go
    export PATH=$PATH:$GOPATH/bin
    
    cd ~
    rm -rf mage
    git clone https://github.com/magefile/mage
    cd mage
    /usr/local/go/bin/go run bootstrap.go
    
    # Сборка OlcRTC
    echo -e "\n${CYAN}[5/7] Скачивание и сборка OlcRTC (может занять время)...${NC}"
    cd ~
    rm -rf olcrtc
    git clone https://github.com/openlibrecommunity/olcrtc.git --recurse-submodules
    cd olcrtc
    ~/go/bin/mage build

    # Автоматическая генерация комнаты (если выбрано)
    if [[ "$AUTO_ROOM" == true ]]; then
        echo -e "\n${CYAN}[6/7] Автоматическая генерация ID звонка...${NC}"
        ROOM_ID=$(./build/olcrtc-linux-amd64 -mode gen -carrier $PROVIDER -dns 1.1.1.1:53 -amount 1 -data data)
        echo -e "${GREEN}Сгенерирован Room ID: $ROOM_ID${NC}"
    else
        echo -e "\n${CYAN}[6/7] Генерация ID звонка пропущена (используется ручной ввод).${NC}"
    fi

    # Настройка Systemd
    echo -e "\n${CYAN}[7/7] Настройка системной службы...${NC}"
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
