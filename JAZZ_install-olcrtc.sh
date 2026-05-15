#!/bin/bash

# Цветовая палитра для вывода
NC='\e[0m'
GREEN='\e[32m'
YELLOW='\e[33m'
CYAN='\e[36m'
RED='\e[31m'

# Функция парсинга URL для Jazz (Next API v6)
parse_jazz_url() {
    local input_url="$1"
    
    # 1. Извлекаем ЗАШИФРОВАННЫЙ хэш для нового API Сбера
    if [[ "$input_url" == *"?psw="* ]]; then
        S_ROOM_PSW_HASH="${input_url##*?psw=}"
        S_ROOM_PSW_HASH="${S_ROOM_PSW_HASH%%&*}"
        if [ ${#S_ROOM_PSW_HASH} -lt 10 ]; then
            S_ROOM_PSW_HASH=""
        fi
    else
        S_ROOM_PSW_HASH=""
    fi
    
    # 2. Извлекаем обычный пароль (fallback для старых комнат)
    if [[ "$input_url" == *"pwd="* ]]; then
        local pwd_part="${input_url##*pwd=}"
        pwd_part="${pwd_part%%&*}"
        if [ -z "$S_ROOM_PSW_HASH" ] && [ -n "$pwd_part" ]; then
            S_ROOM_PASSWORD="$pwd_part"
        else
            S_ROOM_PASSWORD=""
        fi
    else
        [ -z "$S_ROOM_PSW_HASH" ] && S_ROOM_PASSWORD=""
    fi
    
    # 3. Вырезаем чистый короткий ROOM_ID (например, nlg7d4)
    local temp="${input_url%%\?*}"
    temp="${temp##*/}"
    
    echo "$temp"
}

clear
echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}    OlcRTC Автоустановщик (v2.2.3-stable)        ${NC}"
echo -e "${CYAN}=================================================${NC}"

# Шаг 1: Сбор данных от пользователя
echo -e "\n${YELLOW}Выберите провайдера видеовстреч:${NC}"
echo -e "1) telemost (Yandex)"
echo -e "2) wbstream (Wildberries)"
echo -e "3) jazz (Sber SaluteJazz)"
read -p "Выберите вариант (1-3): " PROVIDER_CHOICE

case $PROVIDER_CHOICE in
    1) PROVIDER="yandex" ;;
    2) PROVIDER="wbstream" ;;
    3) PROVIDER="jazz" ;;
    *) echo -e "${RED}Неверный выбор.${NC}"; exit 1 ;;
esac

echo -e "\n${YELLOW}Выберите тип транспорта:${NC}"
echo -e "1) vp8channel (Рекомендуется)"
echo -e "2) videochannel (Низкий битрейт / FFmpeg)"
read -p "Выберите вариант (1-2): " TRANSPORT_CHOICE

case $TRANSPORT_CHOICE in
    1) TRANSPORT="vp8channel" ;;
    2) TRANSPORT="videochannel" ;;
    *) echo -e "${RED}Неверный выбор.${NC}"; exit 1 ;;
esac

read -p "Введите ID звонка или ПОЛНУЮ ссылку: " ROOM_INPUT
read -p "Введите имя бота в конференции (например, Михаил): " BOT_NAME

# Парсинг ссылки
if [[ "$PROVIDER" == "jazz" ]]; then
    ROOM_ID=$(parse_jazz_url "$ROOM_INPUT")
else
    ROOM_ID=$(echo "$ROOM_INPUT" | sed -E 's/.*(j\/|room\/)//' | cut -d '?' -f 1)
fi

if [ -z "$ROOM_ID" ]; then
    echo -e "${RED}Ошибка: Не удалось распознать ID комнаты!${NC}"
    exit 1
fi

# Шаг 2: Установка Go и системных зависимостей
echo -e "\n${CYAN}[1/5] Очистка системы от старых версий Go...${NC}"
apt-get remove -y golang-go golang > /dev/null 2>&1
rm -rf /usr/local/go

echo -e "${CYAN}[2/5] Установка актуальной версии Go с серверов Google...${NC}"
apt-get update -y > /dev/null 2>&1
apt-get install -y curl wget git tar build-essential ffmpeg > /dev/null 2>&1

LATEST_GO=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
wget -qO go.tar.gz "https://go.dev/dl/${LATEST_GO}.linux-amd64.tar.gz"
tar -C /usr/local -xzf go.tar.gz
rm go.tar.gz

ln -sf /usr/local/go/bin/go /usr/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/bin/gofmt
echo -e "${GREEN}✓ Установлен ${LATEST_GO}${NC}"

# Шаг 3: Скачивание исходников OlcRTC
echo -e "\n${CYAN}[3/5] Скачивание исходного кода OlcRTC...${NC}"
rm -rf /opt/olcrtc
git clone -q https://github.com/alananisimov/olcrtc.git /opt/olcrtc
cd /opt/olcrtc

# Шаг 4: Применение патча (Внешний джаз-патчер v6)
if [[ "$PROVIDER" == "jazz" ]]; then
    echo -e "\n${CYAN}[4/5] Подготовка внешнего патчера Jazz API v6...${NC}"
    if wget -qO jazz_patcher.sh "https://raw.githubusercontent.com/Andreyleluk-GAS/LE-Olcrtc/main/jazz_patcher.sh"; then
        echo -e "${GREEN}✓ Патчер успешно загружен с GitHub${NC}"
        chmod +x jazz_patcher.sh
        ./jazz_patcher.sh "$BOT_NAME" "$S_ROOM_PSW_HASH" "$S_ROOM_PASSWORD"
        rm -f jazz_patcher.sh
    else
        echo -e "${RED}✖ Ошибка: Не удалось скачать файл патчера!${NC}"
        exit 1
    fi
else
    echo -e "\n${CYAN}[4/5] Для данного провайдера патч кода не требуется.${NC}"
fi

# Шаг 5: Сборка проекта
echo -e "\n${CYAN}[5/5] Компиляция бинарного файла (go build)...${NC}"
# Ограничиваем потоки сборки до 2, чтобы не упасть по памяти на слабых VDS
go build -p=2 -o olcrtc main.go

if [ ! -f "olcrtc" ]; then
    echo -e "${RED}✖ Ошибка: Сборка не удалась!${NC}"
    exit 1
fi

# Шаг 6: Создание службы systemd
echo -e "\n${CYAN}Настройка системной службы systemd...${NC}"

# Стандартные ключи авторизации Olc
KEY="698ea7dc7927515c2583075b984cb3bf1134d1e9bd5963f3bf5b4a03fdcd1179"
CLIENT_ID="9cf2464e"

EXEC_COMMAND="/opt/olcrtc/olcrtc -mode srv -carrier ${PROVIDER} -link direct -dns 77.88.8.8:53 -data data -id \"${ROOM_ID}\" -key \"${KEY}\" -client-id \"${CLIENT_ID}\" -transport ${TRANSPORT}"

if [[ "$TRANSPORT" == "videochannel" ]]; then
    EXEC_COMMAND="$EXEC_COMMAND -video-w 640 -video-h 480 -video-fps 30 -video-bitrate 1000000 -video-hw none"
fi

cat << EOF > /etc/systemd/system/olcrtc.service
[Unit]
Description=OlcRTC Proxy Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/olcrtc
ExecStart=${EXEC_COMMAND}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable olcrtc > /dev/null 2>&1
systemctl restart olcrtc

echo -e "\n${GREEN}=================================================${NC}"
echo -e "${GREEN}        УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!             ${NC}"
echo -e "${GREEN}=================================================${NC}"
echo -e "Провайдер:      ${PROVIDER}"
echo -e "Транспорт:      ${TRANSPORT}"
echo -e "ID комнаты:     ${ROOM_ID}"
echo -e "Имя бота:       ${BOT_NAME}"
echo -e "${CYAN}=================================================${NC}"
echo -e "Проверить логи службы можно командой:"
echo -e "${YELLOW}journalctl -u olcrtc -n 50 -f${NC}\n"
