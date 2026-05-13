#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # Нет цвета

# Версия скрипта
SCRIPT_VERSION="v2.0.1"

# Определяет оптимальный флаг параллелизма для сборки Go
# на основе свободного места на диске и числа CPU.
# Возвращает строку вида "-p=N" или пустую строку (все ядра).
calc_build_flags() {
    local FREE_KB
    FREE_KB=$(df / --output=avail 2>/dev/null | tail -1)
    FREE_KB=${FREE_KB:-0}

    local NCPU
    NCPU=$(nproc 2>/dev/null || echo 2)

    if [ "$FREE_KB" -ge 3145728 ]; then
        # >= 3 ГБ свободно — полная скорость, все ядра
        BUILD_PARALLEL_FLAGS=""
        BUILD_SPEED_MSG="${GREEN}полная скорость (${NCPU} ядер, >3 ГБ свободно)${NC}"
    elif [ "$FREE_KB" -ge 1536000 ]; then
        # >= 1.5 ГБ — умеренный параллелизм
        BUILD_PARALLEL_FLAGS="-p=4"
        BUILD_SPEED_MSG="${YELLOW}умеренная скорость (-p=4, 1.5–3 ГБ свободно)${NC}"
    else
        # < 1.5 ГБ — безопасный режим
        BUILD_PARALLEL_FLAGS="-p=2"
        BUILD_SPEED_MSG="${RED}безопасный режим (-p=2, мало места на диске)${NC}"
    fi
}

# ─────────────────────────────────────────────────────────────
# Генерация реалистичного русского имени для маскировки в SFU
# ─────────────────────────────────────────────────────────────
generate_russian_name() {
    local NAMES=(
        "Иван Петров"
        "Сергей Сидоров"
        "Дмитрий Кузнецов"
        "Александр Попов"
        "Алексей Смирнов"
        "Мария Иванова"
        "Анна Козлова"
        "Елена Волкова"
        "Олег Орлов"
        "Наталья Морозова"
        "Михаил Федоров"
        "Владимир Краснов"
        "Андрей Соколов"
        "Екатерина Лебедева"
        "Татьяна Новикова"
    )
    local COUNT=${#NAMES[@]}
    local INDEX=$((RANDOM % COUNT))
    RND_NAME="${NAMES[$INDEX]}"
}

# ─────────────────────────────────────────────────────────────
# Тихая очистка предыдущей установки (без интерактивных вопросов)
# Используется как в install_olcrtc (после подтверждения),
# так и в quick_install (автоматически).
# ─────────────────────────────────────────────────────────────
silent_wipe() {
    systemctl stop olcrtc    2>/dev/null || true
    systemctl disable olcrtc 2>/dev/null || true
    rm -f  /etc/systemd/system/olcrtc.service
    systemctl daemon-reload  2>/dev/null || true
    rm -rf /opt/olcrtc
    rm -rf ~/olcrtc
    rm -rf ~/mage
}

# ─────────────────────────────────────────────────────────────
# Показать текущий статус и реквизиты (Опция 6)
# ─────────────────────────────────────────────────────────────
show_status() {
    print_logo
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "${CYAN}   Статус OlcRTC и реквизиты подключения         ${NC}"
    echo -e "${MAGENTA}=================================================${NC}"

    local CFG="/opt/olcrtc/.env"

    # Проверяем установлен ли сервис
    if [ ! -f /etc/systemd/system/olcrtc.service ]; then
        echo -e "${RED}[✖] OlcRTC не установлен.${NC}"
        echo -e "    Запустите установку через пункт 1, 4 или 5 меню."
        echo
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    # Проверяем активен ли сервис
    if ! systemctl is-active --quiet olcrtc; then
        echo -e "${RED}[✖] Сервис OlcRTC установлен, но НЕ ЗАПУЩЕН.${NC}"
        echo -e "${YELLOW}    Статус: $(systemctl is-active olcrtc)${NC}"
        echo -e "    Для диагностики: journalctl -u olcrtc -n 30"
        echo
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    echo -e "${GREEN}[✔] Сервис OlcRTC активен и работает.${NC}\n"

    # Читаем сохранённые реквизиты
    if [ ! -f "$CFG" ]; then
        echo -e "${YELLOW}⚠ Файл реквизитов не найден: ${CFG}${NC}"
        echo -e "  (Установка выполнена старой версией скрипта без сохранения реквизитов)"
        echo -e "  Перезапустите установку для сохранения реквизитов."
        echo
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    # shellcheck source=/dev/null
    source "$CFG"

    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "${GREEN} РЕКВИЗИТЫ ТЕКУЩЕЙ УСТАНОВКИ${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "Провайдер:\t${YELLOW}${S_PROVIDER}${NC}"
    echo -e "Транспорт:\t${YELLOW}${S_TRANSPORT}${NC}"
    echo -e "ID звонка:\t${YELLOW}${S_ROOM_ID}${NC}"
    echo -e "Ключ:\t\t${YELLOW}${S_ENC_KEY}${NC}"
    echo -e "ID клиента:\t${YELLOW}${S_CLIENT_ID}${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "URI для быстрого импорта в Olcbox:"
    echo -e "${YELLOW}olcrtc://${S_PROVIDER}?${S_TRANSPORT}@${S_ROOM_ID}#${S_ENC_KEY}%${S_CLIENT_ID}\$OlcRTC_Server${NC}"
    echo -e "${MAGENTA}=================================================${NC}"

    # Если Jazz — показываем ссылку на встречу
    if [[ "${S_PROVIDER}" == "jazz" && -n "${S_ROOM_ID}" ]]; then
        echo -e "Ссылка для участников (SaluteJazz):"
        echo -e "  ${YELLOW}https://salutejazz.ru/calls/${S_ROOM_ID}${NC}"
        echo -e "  Код конференции: ${YELLOW}${S_ROOM_ID}@salutejazz.ru${NC}"
    elif [[ "${S_PROVIDER}" == "wbstream" && -n "${S_ROOM_ID}" ]]; then
        echo -e "Ссылка для участников (WB Stream):"
        echo -e "  ${YELLOW}https://stream.wb.ru/room/${S_ROOM_ID}${NC}"
    fi
    echo -e "${MAGENTA}=================================================${NC}"

    read -p "Нажмите Enter для возврата в меню..."
}

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
    echo -e "${YELLOW}                                     Версия: ${SCRIPT_VERSION}${NC}"
    echo -e "${NC}"
}

# Функция установки
install_olcrtc() {
    # ── Проверка предыдущей установки ────────────────
    if [ -f /etc/systemd/system/olcrtc.service ] || [ -d /opt/olcrtc ]; then
        print_logo
        echo -e "${MAGENTA}=================================================${NC}"
        echo -e "${YELLOW}   ⚠  Обнаружена предыдущая установка OlcRTC!   ${NC}"
        echo -e "${MAGENTA}=================================================${NC}"
        echo -e "${RED}Продолжение без очистки может вызвать конфликты файлов и ошибки.${NC}"
        echo
        # Сбрасываем буфер stdin (может содержать Enter от главного меню)
        read -t 0.1 -n 10000 discard_buffer 2>/dev/null || true
        read -p "Удалить существующую установку и начать заново? (y/д/Enter-отмена): " wipe_choice
        if [[ "$wipe_choice" == "y" || "$wipe_choice" == "Y" || "$wipe_choice" == "д" || "$wipe_choice" == "Д" ]]; then
            echo -e "${CYAN}Выполняю очистку...${NC}"
            silent_wipe
            echo -e "${GREEN}Очистка завершена. Начинаем чистую установку.${NC}"
            sleep 1
        else
            echo -e "${YELLOW}Установка отменена. Возврат в меню.${NC}"
            sleep 1
            return
        fi
    fi
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
        # Матрица совместимости: + работает | * работает но нежелательно | - не поддерживается
        echo -e "\n${CYAN}Шаг 2: Выберите тип транспорта:${NC}"

        if [[ "$PROVIDER" == "wbstream" ]]; then
            echo -e " 1) datachannel  ${GREEN}[рекомендуется — максимальная скорость]${NC}"
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

        elif [[ "$PROVIDER" == "jazz" ]]; then
            echo -e "${YELLOW}⚠ Для Jazz провайдера:${NC}"
            echo -e "  ${RED}datachannel — Jazz моментально банит IP за этот паттерн трафика!${NC}"
            echo -e "  ${GREEN}Рекомендуется vp8channel или seichannel.${NC}\n"
            echo -e " 1) vp8channel   ${GREEN}[рекомендуется]${NC} (высокая скорость)"
            echo -e " 2) seichannel   (средняя скорость)"
            echo -e " 3) videochannel (низкая скорость)"
            echo -e " 4) datachannel  ${RED}[⚠ Jazz забанит IP — не рекомендуется]${NC}"
            echo -e " 0) Назад в главное меню"
            read -p "Ваш выбор (0-4) [по умолчанию 1]: " trans_choice
            [[ "$trans_choice" == "0" ]] && return
            case $trans_choice in
                2) TRANSPORT="seichannel" ;;
                3) TRANSPORT="videochannel" ;;
                4) TRANSPORT="datachannel" ;;
                *) TRANSPORT="vp8channel" ;;
            esac

        elif [[ "$PROVIDER" == "telemost" ]]; then
            echo -e "${YELLOW}⚠ Для Telemost провайдера:${NC}"
            echo -e "  ${RED}datachannel и seichannel — не поддерживаются Telemost!${NC}\n"
            echo -e " 1) vp8channel   ${GREEN}[рекомендуется]${NC} (высокая скорость)"
            echo -e " 2) videochannel (низкая скорость)"
            echo -e " 0) Назад в главное меню"
            read -p "Ваш выбор (0-2) [по умолчанию 1]: " trans_choice
            [[ "$trans_choice" == "0" ]] && return
            case $trans_choice in
                2) TRANSPORT="videochannel" ;;
                *) TRANSPORT="vp8channel" ;;
            esac
        fi

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
                read -p "Введите ID звонка или вставьте полную ссылку на комнату: " ROOM_ID
                ROOM_ID="${ROOM_ID##*/}"; ROOM_ID="${ROOM_ID%%\?*}"
                while [ -z "$ROOM_ID" ]; do
                    echo -e "${RED}Ошибка: ID звонка обязателен!${NC}"
                    read -p "Введите ID звонка или вставьте полную ссылку на комнату: " ROOM_ID
                    ROOM_ID="${ROOM_ID##*/}"; ROOM_ID="${ROOM_ID%%\?*}"
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
            read -p "Введите ID звонка или вставьте полную ссылку на комнату: " ROOM_ID
            ROOM_ID="${ROOM_ID##*/}"; ROOM_ID="${ROOM_ID%%\?*}"
            while [ -z "$ROOM_ID" ]; do
                echo -e "${RED}Ошибка: ID звонка обязателен!${NC}"
                read -p "Введите ID звонка или вставьте полную ссылку на комнату: " ROOM_ID
                ROOM_ID="${ROOM_ID##*/}"; ROOM_ID="${ROOM_ID%%\?*}"
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
    echo -e "\n${CYAN}[3/7] Установка последней версии Go...${NC}"
    apt-get install -yq git wget curl build-essential
    LATEST_GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
    wget -qO /tmp/go_download.tar.gz "https://go.dev/dl/${LATEST_GO_VERSION}.linux-amd64.tar.gz"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go_download.tar.gz
    rm -f /tmp/go_download.tar.gz
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

    # --- Освобождаем максимум места перед сборкой ---
    echo -e "${YELLOW}Очистка дискового пространства перед сборкой...${NC}"
    apt-get clean -q 2>/dev/null || true                         # кэш apt (~200-500 MB)
    apt-get autoremove -yq 2>/dev/null || true                   # ненужные пакеты
    /usr/local/go/bin/go clean -cache 2>/dev/null || true        # кэш Go-компилятора
    journalctl --vacuum-size=50M 2>/dev/null || true             # обрезать системный лог
    rm -rf ~/mage                                                # исходники mage (бинарь уже в ~/go/bin)
    rm -rf ~/go/tmp ~/go/cache                                   # tmp/cache Go (пересоздадим ниже)
    rm -f ~/olcrtc_build.log /tmp/olcrtc_build.log 2>/dev/null  # старые логи

    # --- Проверка свободного места ---
    FREE_KB=$(df / --output=avail | tail -1)
    if   [ "$FREE_KB" -ge 1048576 ]; then FREE_DISPLAY="$(( FREE_KB / 1024 / 1024 )) GB"
    elif [ "$FREE_KB" -ge 1024 ];    then FREE_DISPLAY="$(( FREE_KB / 1024 )) MB"
    else                                  FREE_DISPLAY="${FREE_KB} KB"
    fi

    MIN_KB=716800   # ~700 MB — реальный минимум для сборки с GOTMPDIR на диске и -p=2
    if [ "$FREE_KB" -lt "$MIN_KB" ]; then
        echo -e "${RED}[✖] Недостаточно места на диске даже после очистки.${NC}"
        echo -e "${RED}    Свободно: ${FREE_DISPLAY} | Требуется: ~700 MB${NC}"
        echo -e "${YELLOW}Подсказки:${NC}"
        echo -e "  df -h                  — использование дисков"
        echo -e "  du -sh /* 2>/dev/null  — найти большие каталоги"
        echo -e "  docker system prune -af — если используется Docker"
        exit 1
    fi
    echo -e "${GREEN}Свободно: ${FREE_DISPLAY} — достаточно для сборки.${NC}"

    # --- Клонирование исходников ---
    cd ~
    rm -rf olcrtc
    git clone -q https://github.com/openlibrecommunity/olcrtc.git --recurse-submodules
    cd olcrtc

    # Перенаправляем tmp/cache Go с tmpfs(/tmp) на диск — исключает "no space left on device"
    mkdir -p ~/go/tmp ~/go/cache
    export GOTMPDIR=~/go/tmp
    export GOCACHE=~/go/cache

    # Адаптивный параллелизм: зависит от свободного места и числа ядер
    calc_build_flags
    echo -e "${CYAN}Режим сборки: ${BUILD_SPEED_MSG}"
    [ -n "$BUILD_PARALLEL_FLAGS" ] && export GOFLAGS="$BUILD_PARALLEL_FLAGS"

    BUILD_LOG=~/olcrtc_build.log

    # Выключаем прерывание по ошибке, чтобы корректно обработать статус сборки
    set +e

    # Запускаем сборку в фоне, весь вывод — в лог-файл
    ~/go/bin/mage build > "$BUILD_LOG" 2>&1 &
    PID=$!

    # Анимация spinner
    spin='-\|/'
    i=0
    while kill -0 $PID 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r${YELLOW}Компиляция в процессе... %c${NC}" "${spin:$i:1}"
        sleep 0.1
    done

    wait $PID
    BUILD_STATUS=$?

    # Очищаем tmp Go сразу после сборки — освобождаем место для следующих шагов
    rm -rf ~/go/tmp ~/go/cache
    unset GOFLAGS

    if [ $BUILD_STATUS -eq 0 ]; then
        printf "\r${GREEN}Компиляция успешно завершена!                        ${NC}\n"
        rm -f "$BUILD_LOG"
    else
        printf "\r${RED}Ошибка компиляции!                                   ${NC}\n"
        echo -e "${RED}━━━ Последние строки лога ━━━${NC}"
        tail -25 "$BUILD_LOG"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}Полный лог: $BUILD_LOG${NC}"
        exit 1
    fi
    set -e



    # [6/7] Генерация ID комнаты (если выбрано авто)
    if [[ "$AUTO_ROOM" == true ]]; then
        echo -e "\n${CYAN}[6/7] Автоматическая генерация ID звонка...${NC}"
        ROOM_ID=$(./build/olcrtc-linux-amd64 -mode gen -carrier $PROVIDER -dns 1.1.1.1:53 -amount 1 -data data)
        echo -e "${GREEN}Сгенерирован Room ID: $ROOM_ID${NC}"

        # Вывод реквизитов созданной комнаты для приглашения участников
        if [[ "$PROVIDER" == "jazz" ]]; then
            # Для Jazz пароль возвращается вместе с Room ID через пробел или в отдельном поле
            # Формат вывода olcrtc -mode gen -carrier jazz: "roomId password"
            JAZZ_ROOM_PARTS=($ROOM_ID)
            JAZZ_ID="${JAZZ_ROOM_PARTS[0]}"
            JAZZ_PSW="${JAZZ_ROOM_PARTS[1]:-}"
            ROOM_ID="$JAZZ_ID"

            echo -e "\n${MAGENTA}--- Реквизиты встречи SaluteJazz ---${NC}"
            echo -e "Подключиться в браузере по ссылке:"
            if [[ -n "$JAZZ_PSW" ]]; then
                echo -e "  ${YELLOW}https://salutejazz.ru/calls/${JAZZ_ID}?psw=${JAZZ_PSW}${NC}"
            else
                echo -e "  ${YELLOW}https://salutejazz.ru/calls/${JAZZ_ID}${NC}"
            fi
            echo -e "Для подключения по коду видеовстречи:"
            echo -e "  Код конференции: ${YELLOW}${JAZZ_ID}@salutejazz.ru${NC}"
            if [[ -n "$JAZZ_PSW" ]]; then
                echo -e "  Пароль:          ${YELLOW}${JAZZ_PSW}${NC}"
            fi
            echo -e "${MAGENTA}------------------------------------${NC}"
        elif [[ "$PROVIDER" == "wbstream" ]]; then
            echo -e "\n${MAGENTA}--- Реквизиты комнаты WB Stream ---${NC}"
            echo -e "  Ссылка: ${YELLOW}https://stream.wb.ru/room/${ROOM_ID}${NC}"
            echo -e "${MAGENTA}-----------------------------------${NC}"
        fi
    else
        echo -e "\n${CYAN}[6/7] Генерация ID пропущена (используется ручной ввод).${NC}"
    fi

    # [7/7] Настройка Systemd
    echo -e "\n${CYAN}[7/7] Настройка системной службы...${NC}"
    # Останавливаем службу перед заменой бинарника (иначе: "Text file busy")
    systemctl stop olcrtc 2>/dev/null || true
    mkdir -p /opt/olcrtc/data
    cp build/olcrtc-linux-amd64 /opt/olcrtc/olcrtc

    # Генерируем реалистичное русское имя для маскировки в SFU
    generate_russian_name
    echo -e "${YELLOW}Имя бота: $RND_NAME${NC}"

    # Дополнительные флаги транспорта (из документации, рекомендуемые значения)
    case $TRANSPORT in
        vp8channel)
            TRANSPORT_FLAGS="-vp8-fps 60 -vp8-batch 64"
            ;;
        seichannel)
            TRANSPORT_FLAGS="-fps 60 -batch 64 -frag 900 -ack-ms 2000"
            ;;
        videochannel)
            TRANSPORT_FLAGS="-video-codec qrcode -video-w 1080 -video-h 1080 -video-fps 60 -video-bitrate 5000k -video-hw none"
            ;;
        *)
            TRANSPORT_FLAGS=""  # datachannel — дополнительных флагов нет
            ;;
    esac

    cat <<EOF > /etc/systemd/system/olcrtc.service
[Unit]
Description=OlcRTC Proxy Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/olcrtc
ExecStart=/opt/olcrtc/olcrtc -mode srv -carrier $PROVIDER -transport $TRANSPORT -link direct -dns 1.1.1.1:53 -data data -id "$ROOM_ID" -key "$ENC_KEY" -client-id "$CLIENT_ID" $TRANSPORT_FLAGS
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable olcrtc
    systemctl restart olcrtc

    set +e

    # Финальная проверка (jazz требует больше времени на handshake)
    echo -e "\n${YELLOW}Выполняем проверку запуска сервера...${NC}"
    if [[ "$PROVIDER" == "jazz" ]]; then
        sleep 8
    else
        sleep 4
    fi

    if systemctl is-active --quiet olcrtc; then
        # Сохраняем реквизиты для последующего просмотра через пункт 6
        mkdir -p /opt/olcrtc
        cat > /opt/olcrtc/.env <<ENV_EOF
S_PROVIDER="${PROVIDER}"
S_TRANSPORT="${TRANSPORT}"
S_ROOM_ID="${ROOM_ID}"
S_ENC_KEY="${ENC_KEY}"
S_CLIENT_ID="${CLIENT_ID}"
S_USER_NAME="${RND_NAME}"
ENV_EOF
        chmod 600 /opt/olcrtc/.env

        echo -e "${GREEN}[✔] Служба OlcRTC успешно запущена и стабильно работает!${NC}"
        echo -e "\n${MAGENTA}=================================================${NC}"
        echo -e "${GREEN} УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!${NC}"
        echo -e "${MAGENTA}=================================================${NC}"

        # Ссылки на конференцию для участников
        if [[ "$PROVIDER" == "telemost" ]]; then
            echo -e "Ссылка для участников (Yandex Telemost):"
            echo -e "  ${YELLOW}https://telemost.yandex.ru/j/${ROOM_ID}${NC}"
        elif [[ "$PROVIDER" == "wbstream" ]]; then
            echo -e "Ссылка для участников (WB Stream):"
            echo -e "  ${YELLOW}https://stream.wb.ru/room/${ROOM_ID}${NC}"
        elif [[ "$PROVIDER" == "jazz" ]]; then
            echo -e "Ссылка для участников (SaluteJazz):"
            echo -e "  ${YELLOW}https://salutejazz.ru/calls/${ROOM_ID}${NC}"
            echo -e "  Код конференции: ${YELLOW}${ROOM_ID}@salutejazz.ru${NC}"
        fi
        echo -e "${MAGENTA}=================================================${NC}"

        echo -e "Ваши данные для подключения в клиенте (Olcbox):"
        echo -e "Провайдер:\t${YELLOW}$PROVIDER${NC}"
        echo -e "Транспорт:\t${YELLOW}$TRANSPORT${NC}"
        echo -e "ID звонка:\t${YELLOW}$ROOM_ID${NC}"
        echo -e "Ключ:\t\t${YELLOW}$ENC_KEY${NC}"
        echo -e "ID клиента:\t${YELLOW}$CLIENT_ID${NC}"
        echo -e "Имя бота:\t${YELLOW}$RND_NAME${NC}"
        echo -e "${MAGENTA}=================================================${NC}"
        echo -e "URI для быстрого импорта в Olcbox:"
        echo -e "${YELLOW}olcrtc://${PROVIDER}?${TRANSPORT}@${ROOM_ID}#${ENC_KEY}%${CLIENT_ID}\$OlcRTC_Server${NC}"
        echo -e "${MAGENTA}=================================================${NC}"
    else
        echo -e "${RED}[✖] Служба OlcRTC запустилась, но упала!${NC}"
        echo -e "${CYAN}Последние строки лога:${NC}"
        RECENT_LOG=$(journalctl -u olcrtc -n 15 --no-pager 2>/dev/null)
        echo "$RECENT_LOG"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        # --- Автоматический анализ ошибки ---
        echo -e "${YELLOW}⚠ Диагностика:${NC}"

        if echo "$RECENT_LOG" | grep -q "status 400" && [[ "$PROVIDER" == "jazz" ]]; then
            echo -e "${RED}  Причина: Jazz API (salutejazz.ru) отклонил подключение (HTTP 400).${NC}"
            echo -e "${YELLOW}  Это внешняя проблема — IP вашего VPS заблокирован Jazz,${NC}"
            echo -e "${YELLOW}  либо Jazz изменил свой API.${NC}"
            echo -e "${GREEN}  Решение: запустите установку снова и выберите провайдер wbstream.${NC}"
            echo -e "${GREEN}           wbstream — самый стабильный провайдер, без банов.${NC}"

        elif echo "$RECENT_LOG" | grep -q "status 400" && [[ "$PROVIDER" == "telemost" ]]; then
            echo -e "${RED}  Причина: Telemost API отклонил подключение (HTTP 400).${NC}"
            echo -e "${YELLOW}  Возможно, Room ID создан вручную неправильно,${NC}"
            echo -e "${YELLOW}  или Telemost изменил API.${NC}"
            echo -e "${GREEN}  Решение: создайте новую комнату на telemost.yandex.ru и переустановите.${NC}"

        elif echo "$RECENT_LOG" | grep -q "i/o timeout"; then
            echo -e "${RED}  Причина: DNS недоступен или VPS заблокировал исходящие соединения.${NC}"
            echo -e "${GREEN}  Решение 1: переустановите с DNS 8.8.8.8:53 вместо 1.1.1.1:53.${NC}"
            echo -e "${GREEN}  Решение 2: проверьте iptables/ufw на VPS.${NC}"

        elif echo "$RECENT_LOG" | grep -q "vp8 fps required"; then
            echo -e "${RED}  Причина: старая запись из лога (до исправления скрипта).${NC}"
            echo -e "${GREEN}  Решение: перезапустите установку — этот баг уже исправлен.${NC}"

        elif echo "$RECENT_LOG" | grep -q "dial tcp.*refused"; then
            echo -e "${RED}  Причина: VPS не может подключиться к SFU провайдера.${NC}"
            echo -e "${GREEN}  Решение: проверьте исходящий доступ к интернету с VPS.${NC}"

        else
            echo -e "${YELLOW}  Неизвестная ошибка. Полный лог: journalctl -u olcrtc -n 50${NC}"
        fi

        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "\n${YELLOW}Ваши данные (сохраните на случай переустановки):${NC}"
        echo -e "  Провайдер:  ${YELLOW}$PROVIDER${NC}  Транспорт: ${YELLOW}$TRANSPORT${NC}"
        echo -e "  Room ID:    ${YELLOW}$ROOM_ID${NC}"
        echo -e "  Ключ:       ${YELLOW}$ENC_KEY${NC}"
        echo -e "  Client ID:  ${YELLOW}$CLIENT_ID${NC}"
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
    # Сбрасываем буфер stdin (может содержать Enter от главного меню)
    read -t 0.1 -n 10000 discard_buffer 2>/dev/null || true
    read -p "Вы уверены, что хотите продолжить? (y/д/Enter-отмена): " confirm
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

    read -p "Удалить установленный Go? (y/д/Enter-нет): " remove_go
    if [[ "$remove_go" == "y" || "$remove_go" == "Y" || "$remove_go" == "д" || "$remove_go" == "Д" ]]; then
        rm -rf /usr/local/go
        rm -f /etc/profile.d/go.sh
        echo -e "${GREEN}Go успешно удалён.${NC}"
    fi

    read -p "Удалить файл подкачки (/swapfile)? (y/д/Enter-нет): " remove_swap
    if [[ "$remove_swap" == "y" || "$remove_swap" == "Y" || "$remove_swap" == "д" || "$remove_swap" == "Д" ]]; then
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

# ─────────────────────────────────────────────────────────────
# Быстрая установка (без вопросов)
# ─────────────────────────────────────────────────────────────
quick_install() {
    local QP="$1"   # wbstream | jazz

    print_logo
    echo -e "${MAGENTA}=================================================${NC}"
    if [[ "$QP" == "wbstream" ]]; then
        echo -e "${GREEN}   Быстрый старт — Wildberries Stream (WB)       ${NC}"
    else
        echo -e "${GREEN}   Быстрый старт — SaluteJazz                    ${NC}"
    fi
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "${YELLOW}Всё будет настроено автоматически, просто подождите.${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
    echo

    # Лучшие параметры для каждого провайдера
    if [[ "$QP" == "wbstream" ]]; then
        QT="datachannel"
        QTFLAGS=""
    else
        QT="vp8channel"
        QTFLAGS="-vp8-fps 60 -vp8-batch 64"
    fi

    # Автоматическая тихая очистка предыдущей установки (без вопросов)
    silent_wipe

    # Вывод завершённого шага
    qstep() { echo -e "  ${GREEN}✔${NC} $1"; }

    # Спиннер поверх одной строки пока жив QPID
    qwait() {
        local label="$1"
        local spin='-\|/'
        local i=0
        while kill -0 "$QPID" 2>/dev/null; do
            i=$(( (i+1) % 4 ))
            printf "\r  ${CYAN}…${NC} ${label} ${spin:$i:1}   "
            sleep 0.12
        done
        wait "$QPID"
        QSTATUS=$?
        printf "\r\033[2K"   # стереть строку спиннера
    }

    set -e

    # [1] Обновление системы
    ( apt-get update -q && apt-get upgrade -yq ) >/dev/null 2>&1 &
    QPID=$!; qwait "Обновление системы"
    [ $QSTATUS -ne 0 ] && { echo -e "${RED}  ✖ Ошибка обновления${NC}"; exit 1; }
    qstep "Система обновлена"

    # [2] Swap
    (
        if [ ! -f /swapfile ]; then
            fallocate -l 2G /swapfile 2>/dev/null \
                || dd if=/dev/zero of=/swapfile bs=1M count=2048 2>/dev/null
            chmod 600 /swapfile
            mkswap /swapfile >/dev/null
            swapon /swapfile
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
    ) &
    QPID=$!; qwait "Настройка swap"
    qstep "Swap готов"

    # [3] Go + зависимости
    (
        apt-get install -yq git wget curl build-essential >/dev/null 2>&1
        QUICK_GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
        wget -qO /tmp/go_quick.tar.gz "https://go.dev/dl/${QUICK_GO_VERSION}.linux-amd64.tar.gz"
        rm -rf /usr/local/go
        tar -C /usr/local -xzf /tmp/go_quick.tar.gz
        rm -f /tmp/go_quick.tar.gz
        echo "export PATH=\$PATH:/usr/local/go/bin" > /etc/profile.d/go.sh
    ) &
    QPID=$!; qwait "Установка последней версии Go"
    [ $QSTATUS -ne 0 ] && { echo -e "${RED}  ✖ Ошибка установки Go${NC}"; exit 1; }
    export PATH=$PATH:/usr/local/go/bin
    qstep "Go установлен"

    # [4] Mage
    (
        mkdir -p ~/go/bin
        cd ~; rm -rf mage
        git clone -q https://github.com/magefile/mage
        cd mage
        /usr/local/go/bin/go run bootstrap.go >/dev/null 2>&1
    ) &
    QPID=$!; qwait "Установка сборщика Mage"
    export GOPATH=~/go
    export PATH=$PATH:$GOPATH/bin
    qstep "Mage установлен"

    # [5] Сборка OlcRTC
    # Считаем флаги до запуска фонового процесса
    calc_build_flags
    qstep "Режим сборки: ${BUILD_SPEED_MSG}"
    (
        apt-get clean -q 2>/dev/null || true
        apt-get autoremove -yq 2>/dev/null || true
        /usr/local/go/bin/go clean -cache 2>/dev/null || true
        journalctl --vacuum-size=50M 2>/dev/null || true
        rm -rf ~/mage ~/go/tmp ~/go/cache ~/olcrtc_build.log 2>/dev/null || true
        cd ~; rm -rf olcrtc
        git clone -q https://github.com/openlibrecommunity/olcrtc.git --recurse-submodules
        cd olcrtc
        mkdir -p ~/go/tmp ~/go/cache
        GOTMPDIR=~/go/tmp GOCACHE=~/go/cache GOFLAGS="${BUILD_PARALLEL_FLAGS}" \
            ~/go/bin/mage build >~/olcrtc_build.log 2>&1
    ) &
    QPID=$!; qwait "Сборка OlcRTC"
    if [ $QSTATUS -ne 0 ]; then
        echo -e "${RED}  ✖ Ошибка сборки! Лог: ~/olcrtc_build.log${NC}"
        tail -10 ~/olcrtc_build.log 2>/dev/null
        exit 1
    fi
    rm -rf ~/go/tmp ~/go/cache
    qstep "OlcRTC собран"

    # [6] Генерация Room ID и ключей
    QROOM_ID_RAW=$(cd ~/olcrtc && ./build/olcrtc-linux-amd64 \
        -mode gen -carrier "$QP" -dns 1.1.1.1:53 -amount 1 -data data 2>/dev/null)
    QROOM_PARTS=($QROOM_ID_RAW)
    QROOM_ID="${QROOM_PARTS[0]}"
    QROOM_PSW="${QROOM_PARTS[1]:-}"
    qstep "Room ID: ${YELLOW}${QROOM_ID}${NC}"

    QENC_KEY=$(openssl rand -hex 32)
    QCLIENT_ID=$(openssl rand -hex 4)
    qstep "Ключ шифрования создан"

    # [7] Systemd-сервис
    systemctl stop olcrtc 2>/dev/null || true
    mkdir -p /opt/olcrtc/data
    cp ~/olcrtc/build/olcrtc-linux-amd64 /opt/olcrtc/olcrtc

    # Генерируем реалистичное русское имя для маскировки в SFU
    QRND_NAME=""
    generate_russian_name
    QRND_NAME="$RND_NAME"
    qstep "Имя бота: ${YELLOW}${QRND_NAME}${NC}"

    cat <<SVC_EOF > /etc/systemd/system/olcrtc.service
[Unit]
Description=OlcRTC Proxy Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/olcrtc
ExecStart=/opt/olcrtc/olcrtc -mode srv -carrier ${QP} -transport ${QT} -link direct -dns 1.1.1.1:53 -data data -id "${QROOM_ID}" -key "${QENC_KEY}" -client-id "${QCLIENT_ID}" ${QTFLAGS}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC_EOF

    systemctl daemon-reload
    systemctl enable olcrtc >/dev/null 2>&1
    systemctl restart olcrtc
    if [[ "$QP" == "jazz" ]]; then sleep 8; else sleep 4; fi

    if systemctl is-active --quiet olcrtc; then
        # Сохраняем реквизиты для последующего просмотра через пункт 6
        mkdir -p /opt/olcrtc
        cat > /opt/olcrtc/.env <<ENV_EOF
S_PROVIDER="${QP}"
S_TRANSPORT="${QT}"
S_ROOM_ID="${QROOM_ID}"
S_ENC_KEY="${QENC_KEY}"
S_CLIENT_ID="${QCLIENT_ID}"
S_USER_NAME="${QRND_NAME}"
ENV_EOF
        chmod 600 /opt/olcrtc/.env
        qstep "Служба запущена и работает"
        qstep "Реквизиты сохранены в /opt/olcrtc/.env"
    else
        echo -e "${RED}  ✖ Служба запустилась, но упала!${NC}"
        echo -e "${YELLOW}  Лог: journalctl -u olcrtc -n 30${NC}"
    fi

    set +e

    # ── Итоговый экран ────────────────────────────────
    echo
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "${GREEN}            ГОТОВО! ПОДКЛЮЧАЙТЕСЬ:              ${NC}"
    echo -e "${MAGENTA}=================================================${NC}"

    if [[ "$QP" == "wbstream" ]]; then
        echo -e "Ссылка для участников (WB Stream):"
        echo -e "  ${YELLOW}https://stream.wb.ru/room/${QROOM_ID}${NC}"
    elif [[ "$QP" == "jazz" ]]; then
        echo -e "Ссылка для участников (SaluteJazz):"
        if [[ -n "$QROOM_PSW" ]]; then
            echo -e "  ${YELLOW}https://salutejazz.ru/calls/${QROOM_ID}?psw=${QROOM_PSW}${NC}"
            echo -e "  Пароль:          ${YELLOW}${QROOM_PSW}${NC}"
        else
            echo -e "  ${YELLOW}https://salutejazz.ru/calls/${QROOM_ID}${NC}"
        fi
        echo -e "  Код конференции: ${YELLOW}${QROOM_ID}@salutejazz.ru${NC}"
    fi
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "Данные для клиента Olcbox:"
    echo -e "  Провайдер:  ${YELLOW}${QP}${NC}"
    echo -e "  Транспорт:  ${YELLOW}${QT}${NC}"
    echo -e "  ID звонка:  ${YELLOW}${QROOM_ID}${NC}"
    echo -e "  Ключ:       ${YELLOW}${QENC_KEY}${NC}"
    echo -e "  ID клиента: ${YELLOW}${QCLIENT_ID}${NC}"
    echo -e "  Имя бота:   ${YELLOW}${QRND_NAME}${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "URI для быстрого импорта в Olcbox:"
    echo -e "${YELLOW}olcrtc://${QP}?${QT}@${QROOM_ID}#${QENC_KEY}%${QCLIENT_ID}\$OlcRTC_Server${NC}"
    echo -e "${MAGENTA}=================================================${NC}"

    read -p "Нажмите Enter для возврата в меню..."
}

# Главное меню
while true; do
    print_logo
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "${YELLOW}         Установщик OlcRTC Proxy Server          ${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e " ${GREEN}1)${NC} Установить OlcRTC (полная настройка с выбором параметров)"
    echo -e " ${RED}2)${NC} Удалить OlcRTC (возврат к начальным установкам)"
    echo -e " ${CYAN}3)${NC} Посмотреть логи сервера"
    echo -e "${MAGENTA}─────────────────────────────────────────────────${NC}"
    echo -e " ${YELLOW}★ БЫСТРЫЙ СТАРТ — без вопросов, всё само:${NC}"
    echo -e " ${GREEN}4)${NC} Создать всё на ${CYAN}Wildberries Stream${NC} и дать ссылку"
    echo -e " ${GREEN}5)${NC} Создать всё на ${MAGENTA}SaluteJazz${NC} и дать ссылку"
    echo -e "${MAGENTA}─────────────────────────────────────────────────${NC}"
    echo -e " ${CYAN}6)${NC} Проверить статус и реквизиты подключения"
    echo -e "${MAGENTA}─────────────────────────────────────────────────${NC}"
    echo -e " ${YELLOW}0)${NC} Выйти"
    echo -e "${MAGENTA}=================================================${NC}"
    read -p "Выберите действие (0-6): " choice

    case $choice in
        1) install_olcrtc ;;
        2) uninstall_olcrtc ;;
        3)
            echo -e "${CYAN}Последние логи службы OlcRTC (Ctrl+C для выхода):${NC}"
            journalctl -u olcrtc -f -n 20
            ;;
        4) quick_install wbstream ;;
        5) quick_install jazz ;;
        6) show_status ;;
        0)
            echo -e "${GREEN}Выход. Удачи!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный ввод. Пожалуйста, выберите от 0 до 6.${NC}"
            sleep 1
            ;;
    esac
done