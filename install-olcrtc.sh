#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # Нет цвета

# Проверка на права root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Пожалуйста, запустите скрипт с правами root (sudo ./install.sh)${NC}"
  exit 1
fi

# Отключаем интерактивные окна для apt-get на весь сеанс
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Функция отрисовки логотипа
print_logo() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
   ____  _       _____ _______ _____ 
  / __ \| |     |  __ \__   __/ ____|
 | |  | | | ___ | |__) | | | | |     
 | |  | | |/ __||  _  /  | | | |     
 | |__| | | (__ | | \ \  | | | |____ 
  \____/|_|\___||_|  \_\ |_|  \_____|
EOF
    echo -e "${NC}"
}

# Функция установки
install_olcrtc() {
    while true; do
        print_logo
        echo -e "${MAGENTA}=================================================${NC}"
        echo -e "${GREEN}   Интерактивная установка OlcRTC (Сервер)       ${NC}"
        echo -e "${MAGENTA}=================================================${NC}"

        # --- 1. ВЫБОР ПРОВАЙДЕРА ---
        echo -e "${CYAN}Шаг 1: Выберите провайдера:${NC}"
        echo -e " 1) wbstream (по умолчанию)"
        echo -e " 2) telemost"
        echo -e " 3) jazz"
        echo -e " 0) Назад в главное меню"
        read -p "Ваш выбор (0-3) [по умолчанию 1]: " prov_choice
        
        [[ "$prov_choice" == "0" ]] && return # Возврат в главное меню

        case $prov_choice in
            2) PROVIDER="telemost" ;;
            3) PROVIDER="jazz" ;;
            *) PROVIDER="wbstream" ;;
        esac

        # --- 2. ВЫБОР ТРАНСПОРТА ---
        echo -e "\n${CYAN}Шаг 2: Выберите тип транспорта:${NC}"
        echo -e " 1) datachannel (максимальная скорость) [по умолчанию]"
        echo -e " 2) vp8channel  (высокая скорость)"
        echo -e " 3) seichannel  (средняя скорость)"
        echo -e " 4) videochannel (низкая скорость)"
        echo -e " 0) Назад в главное меню"
        read -p "Ваш выбор (0-4) [по умолчанию 1]: " trans_choice

        [[ "$trans_choice" == "0" ]] && return

        case $trans_choice in
            2) TRANSPORT="vp8channel" ;;
            3) TRANSPORT="seichannel" ;;
            4) TRANSPORT="videochannel" ;;
            *) TRANSPORT="datachannel" ;;
        esac

        # --- 3. ВЫБОР ID ЗВОНКА ---
        echo -e "\n${CYAN}Шаг 3: Настройка ID звонка (комнаты):${NC}"
        echo -e "${YELLOW}💡 Как получить ID звонка?${NC}"
        echo -e "Это ID реальной видеоконференции, внутри которой будет спрятан ваш трафик."
        echo -e "Использование 'живой' комнаты, созданной вручную, дает лучшую маскировку.\n"
        
        echo -e "Создайте комнату и скопируйте ID из адресной строки:"
        echo -e " ▶ ${CYAN}WB Stream:${NC}       https://stream.wb.ru/room/${YELLOW}[ваш_id]${NC}"
        echo -e " ▶ ${CYAN}Yandex Telemost:${NC} https://telemost.yandex.ru/j/${YELLOW}[ваш_id]${NC}"
        echo -e " ▶ ${CYAN}SaluteJazz:${NC}      https://salutejazz.ru/calls/${YELLOW}[ваш_id]${NC}\n"

        if [[ "$PROVIDER" == "wbstream" || "$PROVIDER" == "jazz" ]]; then
            echo -e " 1) Сгенерировать ID автоматически (рекомендуется)"
            echo -e " 2) Ввести ID звонка вручную"
            echo -e " 0) Назад в главное меню"
            read -p "Ваш выбор (0-2) [по умолчанию 1]: " room_choice
            
            [[ "$room_choice" == "0" ]] && return

            if [[ "$room_choice" == "2" ]]; then
                AUTO_ROOM=false
                read -p "Введите ID звонка: " ROOM_ID
                while [ -z "$ROOM_ID" ]; do
                    echo -e "${RED}Ошибка: ID звонка обязателен!${NC}"
                    read -p "Введите ID звонка: " ROOM_ID
                done
            else
                AUTO_ROOM=true
            fi
        else
            echo -e "${YELLOW}Для Telemost доступен только ручной ввод ID звонка.${NC}"
            echo -e " 1) Ввести ID звонка вручную"
            echo -e " 0) Назад в главное меню"
            read -p "Ваш выбор (0-1) [по умолчанию 1]: " room_choice
            
            [[ "$room_choice" == "0" ]] && return
            
            AUTO_ROOM=false
            read -p "Введите ID звонка: " ROOM_ID
            while [ -z "$ROOM_ID" ]; do
                read -p "Введите ID звонка: " ROOM_ID
            done
        fi
        
        # ЕСЛИ ДОШЛИ СЮДА — НАЧИНАЕТСЯ УСТАНОВКА (Точка невозврата)
        break 
    done

    # --- 4. КЛЮЧ И КЛИЕНТ (Автоматически) ---
    ENC_KEY=$(openssl rand -hex 32)
    CLIENT_ID=$(openssl rand -hex 4)

    echo -e "\n${MAGENTA}=================================================${NC}"
    echo -e "${YELLOW}Конфигурация принята. Начинаем установку...${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
    
    set -e # Прерывать при ошибках

    # [1/7] ОС и Обновление
    echo -e "\n${CYAN}[1/7] Обновление пакетов ОС...${NC}"
    apt-get update -q && apt-get upgrade -yq

    # [2/7] Swap
    echo -e "\n${CYAN}[2/7] Настройка Swap (2GB)...${NC}"
    if [ ! -f /swapfile ]; then
        fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
        chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    # [3/7] Go
    echo -e "\n${CYAN}[3/7] Установка Go 1.26.2...${NC}"
    apt-get install -yq git wget curl build-essential
    wget -qO go.tar.gz https://go.dev/dl/go1.26.2.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf go.tar.gz && rm go.tar.gz
    export PATH=$PATH:/usr/local/go/bin

    # [4/7] Mage
    echo -e "\n${CYAN}[4/7] Установка Mage...${NC}"
    mkdir -p ~/go/bin && export GOPATH=~/go && export PATH=$PATH:$GOPATH/bin
    cd ~ && rm -rf mage && git clone -q https://github.com/magefile/mage
    cd mage && /usr/local/go/bin/go run bootstrap.go

    # [5/7] Сборка OlcRTC
    echo -e "\n${CYAN}[5/7] Сборка OlcRTC...${NC}"
    cd ~ && rm -rf olcrtc && git clone -q https://github.com/openlibrecommunity/olcrtc.git --recurse-submodules
    cd olcrtc
    
    set +e
    ~/go/bin/mage build > /tmp/olcrtc_build.log 2>&1 &
    PID=$!
    spin='-\|/'
    i=0
    while kill -0 $PID 2>/dev/null; do
      i=$(( (i+1) %4 ))
      printf "\r${YELLOW}Компиляция (2-5 мин)... %c${NC}" "${spin:$i:1}"
      sleep 0.1
    done
    wait $PID
    [[ $? -ne 0 ]] && echo -e "${RED}Ошибка сборки! Лог: /tmp/olcrtc_build.log${NC}" && exit 1
    set -e

    # [6/7] Room ID
    if [[ "$AUTO_ROOM" == true ]]; then
        echo -e "\n${CYAN}[6/7] Генерация ID...${NC}"
        ROOM_ID=$(./build/olcrtc-linux-amd64 -mode gen -carrier $PROVIDER -dns 1.1.1.1:53 -amount 1 -data data)
    fi

    # [7/7] Service
    echo -e "\n${CYAN}[7/7] Запуск службы...${NC}"
    mkdir -p /opt/olcrtc/data && cp build/olcrtc-linux-amd64 /opt/olcrtc/olcrtc
    cat <<EOF > /etc/systemd/system/olcrtc.service
[Unit]
Description=OlcRTC Proxy
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/olcrtc
ExecStart=/opt/olcrtc/olcrtc -mode srv -carrier $PROVIDER -transport $TRANSPORT -link direct -dns 1.1.1.1:53 -data /opt/olcrtc/data -id "$ROOM_ID" -key "$ENC_KEY" -client-id "$CLIENT_ID"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable olcrtc && systemctl restart olcrtc

    # Health Check
    sleep 3
    if systemctl is-active --quiet olcrtc; then
        echo -e "${GREEN}[✔] Сервер успешно запущен!${NC}"
        echo -e "\n${MAGENTA}=================================================${NC}"
        echo -e "URI для импорта в Olcbox (режим TUN):"
        echo -e "${YELLOW}olcrtc://${PROVIDER}?${TRANSPORT}@${ROOM_ID}#${ENC_KEY}%${CLIENT_ID}\$OlcRTC_Server${NC}"
        echo -e "${MAGENTA}=================================================${NC}"
    else
        echo -e "${RED}[✖] Ошибка запуска! Проверьте логи (пункт 3).${NC}"
    fi
    read -p "Нажмите Enter для возврата..."
}

# Функция удаления (сокращена для краткости, логика та же)
uninstall_olcrtc() {
    print_logo
    echo -e "${RED}Удаление всех компонентов OlcRTC...${NC}"
    systemctl stop olcrtc 2>/dev/null || true
    systemctl disable olcrtc 2>/dev/null || true
    rm -rf /etc/systemd/system/olcrtc.service /opt/olcrtc ~/olcrtc ~/mage
    systemctl daemon-reload
    echo -e "${GREEN}Готово!${NC}"
    read -p "Нажмите Enter..."
}

# Главное меню
while true; do
    print_logo
    echo -e "${YELLOW}            Установщик Proxy Server              ${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e " ${GREEN}1)${NC} Установить OlcRTC"
    echo -e " ${RED}2)${NC} Удалить OlcRTC"
    echo -e " ${CYAN}3)${NC} Логи сервера"
    echo -e " ${YELLOW}0)${NC} Выход"
    echo -e "${MAGENTA}=================================================${NC}"
    read -p "Выберите действие (0-3): " choice

    case $choice in
        1) install_olcrtc ;;
        2) uninstall_olcrtc ;;
        3) journalctl -u olcrtc -f -n 20 ;;
        0) exit 0 ;;
    esac
done
