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
  echo -e "${RED}Ошибка: Пожалуйста, запустите скрипт с правами root (sudo ./install-olcrtc.sh)${NC}"
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
   ____  _       _____  _______ _____ 
  / __ \| |     |  __ \|__   __/ ____|
 | |  | | | ___ | |__) |  | | | |    
 | |  | | |/ __||  _  /   | | | |    
 | |__| | | (__ | | \ \   | | | |____
  \____/|_|\___||_|  \_\  |_|  \_____|
                                      
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
        echo -e " 1) wbstream (Wildberries - рекомендуется)"
        echo -e " 2) telemost (Yandex)"
        echo -e " 3) jazz     (Sber SaluteJazz)"
        echo -e " 0) Назад в главное меню"
        read -p "Ваш выбор (0-3) [по умолчанию 1]: " prov_choice

        [[ "$prov_choice" == "0" ]] && return

        case $prov_choice in
            2) PROVIDER="telemost" ;;
            3) PROVIDER="jazz" ;;
            *) PROVIDER="wbstream" ;;
        esac

        # --- 2. ВЫБОР ТРАНСПОРТА ---
        echo -e "\n${CYAN}Шаг 2: Выберите тип транспорта:${NC}"
        echo -e " 1) datachannel  (максимальная скорость) [по умолчанию]"
        echo -e " 2) vp8channel   (высокая скорость)"
        echo -e " 3) seichannel   (средняя скорость)"
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
        echo -e "ID звонка — это идентификатор конференции, внутри которой прячется трафик."
        echo -e "Используйте реальную комнату для лучшей маскировки.\n"

        echo -e "Создайте комнату и скопируйте ID (код в конце ссылки):"
        echo -e " ▶ ${CYAN}WB Stream:${NC}       https://stream.wb.ru/room/${YELLOW}[ваш_id]${NC}"
        echo -e " ▶ ${CYAN}Yandex Telemost:${NC} https://telemost.yandex.ru/j/${YELLOW}[ваш_id]${NC}"
        echo -e " ▶ ${CYAN}SaluteJazz:${NC}      https://salutejazz.ru/calls/${YELLOW}[ваш_id]${NC}\n"

        echo -e "${MAGENTA}-------------------------------------------------${NC}"
        echo -e "${GREEN}✔ Для WB Stream и SaluteJazz доступна автогенерация ID.${NC}"
        echo -e "${RED}✘ Для Yandex Telemost ID нужно создать и ввести вручную.${NC}"
        echo -e "${MAGENTA}-------------------------------------------------${NC}\n"

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
                echo -e "${YELLOW}ID звонка будет сгенерирован автоматически после компиляции сервера.${NC}"
            fi
        else
            echo -e "${YELLOW}Выбран Telemost: автогенерация недоступна.${NC}"
            echo -e " 1) Ввести ID звонка вручную"
            echo -e " 0) Назад в главное меню"
            read -p "Ваш выбор (0-1) [по умолчанию 1]: " room_choice

            [[ "$room_choice" == "0" ]] && return

            AUTO_ROOM=false
            read -p "Введите ID звонка: " ROOM_ID
            while [ -z "$ROOM_ID" ]; do
                echo -e "${RED}Ошибка: ID звонка обязателен!${NC}"
                read -p "Введите ID звонка: " ROOM_ID
            done
        fi

        # --- 4. ВЫБОР КЛЮЧА ШИФРОВАНИЯ ---
        echo -e "\n${CYAN}Шаг 4: Настройка ключа шифрования:${NC}"
        echo -e " 1) Сгенерировать надёжный ключ автоматически (рекомендуется)"
        echo -e " 2) Ввести свой ключ вручную"
        echo -e " 0) Назад в главное меню"
        read -p "Ваш выбор (0-2) [по умолчанию 1]: " key_choice

        [[ "$key_choice" == "0" ]] && return

        if [[ "$key_choice" == "2" ]]; then
            read -p "Введите ключ шифрования (hex, 64 символа): " ENC_KEY
            while [ -z "$ENC_KEY" ]; do
                echo -e "${RED}Ошибка: Ключ не может быть пустым!${NC}"
                read -p "Введите ключ шифрования: " ENC_KEY
            done
        else
            ENC_KEY=$(openssl rand -hex 32)
            echo -e "${YELLOW}Сгенерирован ключ: $ENC_KEY${NC}"
        fi

        # --- 5. ВЫБОР ID КЛИЕНТА ---
        echo -e "\n${CYAN}Шаг 5: Настройка ID клиента:${NC}"
        echo -e " 1) Сгенерировать автоматически (рекомендуется)"
        echo -e " 2) Ввести вручную"
        echo -e " 0) Назад в главное меню"
        read -p "Ваш выбор (0-2) [по умолчанию 1]: " client_choice

        [[ "$client_choice" == "0" ]] && return

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

        # После всех шагов — возврат в цикл невозможен
        break
    done

    echo -e "\n${MAGENTA}=================================================${NC}"
    echo -e "${YELLOW}Конфигурация завершена. Начинаем установку...${NC}"
    echo -e "${MAGENTA}=================================================${NC}"

    # Останавливаем при ошибках
    set -e

    # [1/7] Проверка ОС и обновление пакетов
    echo -e "\n${CYAN}[1/7] Проверка системы и обновление пакетов ОС...${NC}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            echo -e "${YELLOW}Предупреждение: Ваш дистрибутив ($ID) может не поддерживаться в полной мере.${NC}"
            echo -e "${YELLOW}Рекомендуется Ubuntu или Debian.${NC}"
            sleep 3
        fi
    fi
    apt-get update -q && apt-get upgrade -yq

    # [2/7] Настройка Swap
    echo -e "\n${CYAN}[2/7] Настройка файла подкачки (Swap 2GB)...${NC}"
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

    # [3/7] Зависимости и Go
    echo -e "\n${CYAN}[3/7] Установка Go 1.24.3 и зависимостей...${NC}"
    apt-get install -yq git wget curl build-essential
    wget -qO go.tar.gz https://go.dev/dl/go1.24.3.linux-amd64.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go.tar.gz
    rm go.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo "export PATH=\$PATH:/usr/local/go/bin" > /etc/profile.d/go.sh

    # [4/7] Установка Mage
    echo -e "\n${CYAN}[4/7] Установка системы сборки Mage...${NC}"
    mkdir -p ~/go/bin
    export GOPATH=~/go
    export PATH=$PATH:$GOPATH/bin
    cd ~
    rm -rf mage
    git clone -q https://github.com/magefile/mage
    cd mage
    /usr/local/go/bin/go run bootstrap.go

    # [5/7] Сборка OlcRTC
    echo -e "\n${CYAN}[5/7] Сборка исполняемого файла OlcRTC...${NC}"
    cd ~
    rm -rf olcrtc
    git clone -q https://github.com/openlibrecommunity/olcrtc.git --recurse-submodules
    cd olcrtc

    # Выключаем прерывание по ошибке, чтобы корректно обработать статус сборки
    set +e

    # Запускаем сборку в фоне, весь вывод — в лог-файл
    ~/go/bin/mage build > /tmp/olcrtc_build.log 2>&1 &
    PID=$!

    # Анимация spinner
    spin='-\|/'
    i=0
    while kill -0 $PID 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r${YELLOW}Компиляция в процессе (2-5 минут)... %c${NC}" "${spin:$i:1}"
        sleep 0.1
    done

    wait $PID
    if [ $? -eq 0 ]; then
        printf "\r${GREEN}Компиляция успешно завершена!                        ${NC}\n"
    else
        printf "\r${RED}Ошибка компиляции!                                   ${NC}\n"
        echo -e "${RED}Подробности: /tmp/olcrtc_build.log${NC}"
        exit 1
    fi
    set -e

    # [6/7] Генерация ID комнаты (если выбрано авто)
    if [[ "$AUTO_ROOM" == true ]]; then
        echo -e "\n${CYAN}[6/7] Автоматическая генерация ID звонка...${NC}"
        ROOM_ID=$(./build/olcrtc-linux-amd64 -mode gen -carrier $PROVIDER -dns 1.1.1.1:53 -amount 1 -data data)
        echo -e "${GREEN}Сгенерирован Room ID: $ROOM_ID${NC}"
    else
        echo -e "\n${CYAN}[6/7] Генерация ID пропущена (используется ручной ввод).${NC}"
    fi

    # [7/7] Настройка Systemd
    echo -e "\n${CYAN}[7/7] Настройка системной службы...${NC}"
    # Останавливаем службу перед заменой бинарника (иначе: "Text file busy")
    systemctl stop olcrtc 2>/dev/null || true
    mkdir -p /opt/olcrtc/data
    cp build/olcrtc-linux-amd64 /opt/olcrtc/olcrtc

    cat <<EOF > /etc/systemd/system/olcrtc.service
[Unit]
Description=OlcRTC Proxy Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/olcrtc
ExecStart=/opt/olcrtc/olcrtc -mode srv -carrier $PROVIDER -transport $TRANSPORT -link direct -dns 1.1.1.1:53 -data data -id "$ROOM_ID" -key "$ENC_KEY" -client-id "$CLIENT_ID"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable olcrtc
    systemctl restart olcrtc

    set +e

    # Финальная проверка
    echo -e "\n${YELLOW}Выполняем проверку запуска сервера...${NC}"
    sleep 3

    if systemctl is-active --quiet olcrtc; then
        echo -e "${GREEN}[✔] Служба OlcRTC успешно запущена и стабильно работает!${NC}"
        echo -e "\n${MAGENTA}=================================================${NC}"
        echo -e "${GREEN} УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!${NC}"
        echo -e "${MAGENTA}=================================================${NC}"
        echo -e "Ваши данные для подключения в клиенте (Olcbox):"
        echo -e "Провайдер:\t${YELLOW}$PROVIDER${NC}"
        echo -e "Транспорт:\t${YELLOW}$TRANSPORT${NC}"
        echo -e "ID звонка:\t${YELLOW}$ROOM_ID${NC}"
        echo -e "Ключ:\t\t${YELLOW}$ENC_KEY${NC}"
        echo -e "ID клиента:\t${YELLOW}$CLIENT_ID${NC}"
        echo -e "${MAGENTA}=================================================${NC}"
        echo -e "URI для быстрого импорта в Olcbox:"
        echo -e "${YELLOW}olcrtc://${PROVIDER}?${TRANSPORT}@${ROOM_ID}#${ENC_KEY}%${CLIENT_ID}\$OlcRTC_Server${NC}"
        echo -e "${MAGENTA}=================================================${NC}"
    else
        echo -e "${RED}[✖] Служба OlcRTC запустилась, но упала!${NC}"
        echo -e "${CYAN}Последние строки лога:${NC}"
        journalctl -u olcrtc -n 10 --no-pager
        echo -e "${RED}Проверьте ошибку выше.${NC}"
    fi

    read -p "Нажмите Enter для возврата в меню..."
}

# Функция удаления
uninstall_olcrtc() {
    print_logo
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "${RED}   Полное удаление OlcRTC и всех компонентов    ${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "${RED}ВНИМАНИЕ: Это действие удалит службу OlcRTC, все её файлы и настройки.${NC}"
    read -p "Вы уверены, что хотите продолжить? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" && "$confirm" != "д" && "$confirm" != "Д" ]]; then
        echo -e "${YELLOW}Удаление отменено.${NC}"
        sleep 1
        return
    fi

    echo -e "\n${CYAN}Остановка и удаление службы...${NC}"
    systemctl stop olcrtc 2>/dev/null || true
    systemctl disable olcrtc 2>/dev/null || true
    rm -f /etc/systemd/system/olcrtc.service
    systemctl daemon-reload

    echo -e "${CYAN}Удаление рабочих директорий и исходников...${NC}"
    rm -rf /opt/olcrtc
    rm -rf ~/olcrtc
    rm -rf ~/mage

    read -p "Удалить установленный Go? (y/n): " remove_go
    if [[ "$remove_go" == "y" || "$remove_go" == "Y" ]]; then
        rm -rf /usr/local/go
        rm -f /etc/profile.d/go.sh
        echo -e "${GREEN}Go успешно удалён.${NC}"
    fi

    read -p "Удалить файл подкачки (/swapfile)? (y/n): " remove_swap
    if [[ "$remove_swap" == "y" || "$remove_swap" == "Y" ]]; then
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
        sed -i '/\/swapfile/d' /etc/fstab
        echo -e "${GREEN}Файл подкачки удалён.${NC}"
    fi

    echo -e "\n${MAGENTA}=================================================${NC}"
    echo -e "${GREEN} OlcRTC и связанные компоненты успешно удалены! ${NC}"
    echo -e "${GREEN} Система возвращена к исходному состоянию.      ${NC}"
    echo -e "${MAGENTA}=================================================${NC}"

    read -p "Нажмите Enter для возврата в меню..."
}

# Главное меню
while true; do
    print_logo
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "${YELLOW}         Установщик OlcRTC Proxy Server          ${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e " ${GREEN}1)${NC} Установить OlcRTC (полная автоматическая настройка)"
    echo -e " ${RED}2)${NC} Удалить OlcRTC (возврат к начальным установкам)"
    echo -e " ${CYAN}3)${NC} Посмотреть логи сервера"
    echo -e " ${YELLOW}0)${NC} Выйти"
    echo -e "${MAGENTA}=================================================${NC}"
    read -p "Выберите действие (0-3): " choice

    case $choice in
        1) install_olcrtc ;;
        2) uninstall_olcrtc ;;
        3)
            echo -e "${CYAN}Последние логи службы OlcRTC (Ctrl+C для выхода):${NC}"
            journalctl -u olcrtc -f -n 20
            ;;
        0)
            echo -e "${GREEN}Выход. Удачи!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный ввод. Пожалуйста, выберите от 0 до 3.${NC}"
            sleep 1
            ;;
    esac
done
