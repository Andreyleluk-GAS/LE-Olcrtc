#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # Нет цвета

# Версия скрипта
SCRIPT_VERSION="v2.2.3"

# Массив русских имён для бота (Jazz)
RU_NAMES=("Александр" "Мария" "Иван" "Елена" "Дмитрий" "Анна" "Сергей" "Ольга" "Михаил" "Екатерина" "Виктор" "Наталья")

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
# Тихая очистка предыдущей установки (без интерактивных вопросов)
# Используется в install_olcrtc (после подтверждения).
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
# Проверка обновлений: сравнение локальной и удалённой версий
# Возвращает: "update" - нужно обновление, "current" - актуально
# ─────────────────────────────────────────────────────────────
check_for_updates() {
    local BINARY="/opt/olcrtc/olcrtc"
    local VERSION_FILE="/opt/olcrtc/.local_version"
    local REPO_URL="https://github.com/openlibrecommunity/olcrtc.git"
    
    # Если бинарника нет - это чистая установка
    if [ ! -f "$BINARY" ]; then
        echo "update"
        return
    fi
    
    # Если файла версии нет - пересобираем (старая установка)
    if [ ! -f "$VERSION_FILE" ]; then
        echo "update"
        return
    fi
    
    # Получаем удалённую версию
    echo -e "${CYAN}Проверяем обновления на GitHub...${NC}"
    local REMOTE_VERSION
    REMOTE_VERSION=$(git ls-remote "$REPO_URL" HEAD 2>/dev/null | awk '{ print $1}')
    
    if [ -z "$REMOTE_VERSION" ]; then
        # Не удалось получить удалённую версию - пропускаем обновление
        echo -e "${YELLOW}⚠ Не удалось проверить обновления. Пропускаем сборку.${NC}"
        echo "current"
        return
    fi
    
    local LOCAL_VERSION
    LOCAL_VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "")
    
    if [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
        echo "update"
    else
        echo "current"
    fi
}

# ─────────────────────────────────────────────────────────────
# Полная сборка бинарника (Сценарий A: обновление или новая установка)
# ─────────────────────────────────────────────────────────────
build_olcrtc_binary() {
    local PROVIDER="$1"
    local S_ROOM_PASSWORD="$2"
    local BOT_NAME="$3"
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}[!] Найдено обновление / чистая установка.${NC}"
    echo -e "${YELLOW}    Начинаем сборку бинарника...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    
    # Останавливаем при ошибках
    set -e
    
    # ─────────────────────────────────────────────────────────────────────────
    # [1/6] Полная очистка системы от старых следов Go
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "\n${CYAN}[1/6] Очистка системы от старых версий Go...${NC}"

    # Удаляем системный пакет golang (если был установлен через apt)
    if command -v apt-get >/dev/null 2>&1; then
        apt-get purge -yq golang-go 2>/dev/null || true
        apt-get purge -yq golang 2>/dev/null || true
        apt-get autoremove -yq 2>/dev/null || true
    fi

    # Удаляем директорию /usr/local/go со всеми файлами
    rm -rf /usr/local/go 2>/dev/null || true

    # Удаляем старые symlinks если есть
    rm -f /usr/bin/go    2>/dev/null || true
    rm -f /usr/bin/gofmt 2>/dev/null || true

    # Удаляем старый профиль для Go
    rm -f /etc/profile.d/go.sh 2>/dev/null || true

    echo -e "${GREEN}Старые следы Go успешно удалены.${NC}"

    # ─────────────────────────────────────────────────────────────────────────
    # [2/6] Динамическое определение актуальной версии Go
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "\n${CYAN}[2/6] Определение актуальной версии Go...${NC}"

    # Получаем latest версию с официального эндпоинта Google
    GO_VERSION_RAW=$(curl -sL --fail https://go.dev/VERSION?m=text)

    if [ -z "$GO_VERSION_RAW" ]; then
        echo -e "${RED}✖ Не удалось получить версию Go с go.dev${NC}"
        echo -e "${RED}  Проверьте подключение к интернету.${NC}"
        exit 1
    fi

    # Извлекаем первую строку (например: go1.25.0)
    GO_VERSION=$(echo "$GO_VERSION_RAW" | head -n 1 | tr -d '[:space:]')

    echo -e "${GREEN}➤ Найдена актуальная версия: ${GO_VERSION}${NC}"

    # ─────────────────────────────────────────────────────────────────────────
    # [3/6] Загрузка и установка Go
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "\n${CYAN}[3/6] Загрузка Go ${GO_VERSION} с серверов Google...${NC}"

    GO_TARBALL="/tmp/go_${GO_VERSION}.linux-amd64.tar.gz"

    # Скачиваем архив
    if ! wget -q --show-progress -O "$GO_TARBALL" "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz"; then
        echo -e "${RED}✖ Ошибка загрузки Go с go.dev${NC}"
        rm -f "$GO_TARBALL" 2>/dev/null || true
        exit 1
    fi

    echo -e "${GREEN}Архив успешно скачан.${NC}"

    # ─────────────────────────────────────────────────────────────────────────
    # [4/6] Распаковка Go в /usr/local/
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "\n${CYAN}[4/6] Распаковка Go в /usr/local/...${NC}"

    # Убеждаемся что целевая директория чистая
    rm -rf /usr/local/go 2>/dev/null || true

    # Распаковываем архив
    tar -C /usr/local -xzf "$GO_TARBALL"

    # Удаляем скачанный архив — он больше не нужен
    rm -f "$GO_TARBALL"

    echo -e "${GREEN}Go успешно распакован в /usr/local/go${NC}"

    # ─────────────────────────────────────────────────────────────────────────
    # [5/6] Создание symlinks для глобальной доступности команд
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "\n${CYAN}[5/6] Создание symlinks для команд go и gofmt...${NC}"

    # Создаём symlinks в /usr/bin/ для глобальной доступности
    ln -sf /usr/local/go/bin/go    /usr/bin/go
    ln -sf /usr/local/go/bin/gofmt /usr/bin/gofmt

    # Добавляем Go в PATH для текущей сессии
    export PATH="/usr/local/go/bin:$PATH"

    # Создаём профиль для автоматического добавления Go в PATH при каждом входе
    echo 'export PATH="/usr/local/go/bin:$PATH"' > /etc/profile.d/go.sh

    # Проверяем что Go доступен
    if command -v go >/dev/null 2>&1; then
        INSTALLED_GO_VERSION=$(go version 2>/dev/null | awk '{print $3}')
        echo -e "${GREEN}✓ Symlinks созданы. Go ${INSTALLED_GO_VERSION} доступен глобально.${NC}"
    else
        echo -e "${YELLOW}⚠ Go установлен, но команда 'go' пока недоступна в PATH.${NC}"
        echo -e "${YELLOW}  Перезайдите в систему или выполните: source /etc/profile.d/go.sh${NC}"
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # [6/6] Установка системных зависимостей (git, build-essential, ffmpeg)
    # ─────────────────────────────────────────────────────────────────────────
    echo -e "\n${CYAN}[6/6] Установка системных зависимостей...${NC}"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            echo -e "${YELLOW}⚠ Ваш дистрибутив ($ID) может не поддерживаться в полной мере.${NC}"
            echo -e "${YELLOW}  Рекомендуется Ubuntu или Debian.${NC}"
            sleep 3
        fi
    fi

    apt-get update -q
    apt-get install -yq git build-essential ffmpeg

    echo -e "${GREEN}Все системные зависимости установлены.${NC}"

    # [7/9] Установка Mage
    echo -e "\n${CYAN}[7/9] Установка системы сборки Mage...${NC}"
    mkdir -p ~/go/bin ~/go/tmp ~/go/cache
    export GOPATH=~/go
    export GOTMPDIR=~/go/tmp
    export GOCACHE=~/go/cache
    export PATH=$PATH:$GOPATH/bin
    cd ~
    rm -rf mage
    git clone -q https://github.com/magefile/mage
    cd mage
    /usr/local/go/bin/go run bootstrap.go

    # [8/9] Сборка OlcRTC
    echo -e "\n${CYAN}[8/9] Сборка исполняемого файла OlcRTC...${NC}"

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

    # ─────────────────────────────────────────────────────────────
    # JAZZ API PATCH v5: Исправление Join-запроса для нового Jazz Next API
    # Использует BOT_NAME и S_ROOM_PASSWORD из конфигурации
    # Целевой путь: ~/olcrtc/internal/provider/jazz/jazz.go (или api.go)
    # ─────────────────────────────────────────────────────────────
    if [[ "$PROVIDER" == "jazz" ]]; then
        echo -e "${CYAN}Применяю патч для Jazz Next API v5...${NC}"
        echo -e "${YELLOW}  ➤ Используем имя бота: ${BOT_NAME}${NC}"
        echo -e "${YELLOW}  ➤ Используем пароль: ${S_ROOM_PASSWORD:-<нет>}${NC}"

        # Проверяем что директория существует
        if [ ! -d "internal/provider/jazz" ]; then
            echo -e "${RED}✖ Директория internal/provider/jazz не найдена!${NC}"
            echo -e "${YELLOW}  Структура репозитория могла измениться.${NC}"
            echo -e "${YELLOW}  Продолжаем сборку без патча...${NC}"
        else
            # Ищем файл jazz.go или api.go в директории internal/provider/jazz
            cd internal/provider/jazz
            JAZZ_FILE=""
            
            # Приоритет: jazz.go -> api.go -> любой файл с password
            for candidate in "jazz.go" "api.go"; do
                if [ -f "$candidate" ]; then
                    JAZZ_FILE="$candidate"
                    break
                fi
            done
            
            if [ -z "$JAZZ_FILE" ]; then
                # Ищем любой файл содержащий "password"
                for f in *.go; do
                    if [ -f "$f" ] && grep -q '"password":' "$f" 2>/dev/null; then
                        JAZZ_FILE="$f"
                        break
                    fi
                done
            fi

            if [ -z "$JAZZ_FILE" ]; then
                echo -e "${RED}✖ Файл с JSON payload не найден в internal/provider/jazz/!${NC}"
                echo -e "${YELLOW}  Продолжаем сборку без патча...${NC}"
                cd ~/olcrtc
            else
                echo -e "${YELLOW}  Найден файл: ${JAZZ_FILE}${NC}"

                # Создаём резервную копию
                cp "$JAZZ_FILE" "${JAZZ_FILE}.bak"
                echo -e "${CYAN}  Резервная копия создана: ${JAZZ_FILE}.bak${NC}"

                # ─────────────────────────────────────────────────────────────
                # v2.2.2: Новая логика патчинга
                # 1. Удаляем participantName, если он уже есть (избегаем дублей)
                # 2. Заменяем строку с паролем и добавляем participantName после неё
                # ─────────────────────────────────────────────────────────────

                # 1. На всякий случай удаляем participantName, если он там есть
                sed -i '/"participantName":/d' "$JAZZ_FILE"
                echo -e "${CYAN}  [1/2] Удаление существующего participantName (если был)${NC}"

                # 2. Заменяем строку с паролем и сразу после неё вставляем participantName
                if [ -n "$S_ROOM_PASSWORD" ]; then
                    sed -i 's|"password":.*|"password": password + "'"${S_ROOM_PASSWORD}"'",\n"participantName": "'"${BOT_NAME}"'",|g' "$JAZZ_FILE"
                    
                    if grep -q "password + \"${S_ROOM_PASSWORD}\"" "$JAZZ_FILE" && grep -q '"participantName":.*'"${BOT_NAME}"'' "$JAZZ_FILE"; then
                        echo -e "${GREEN}  ✓ patch v2.2.2 успешно интегрирован!${NC}"
                    else
                        echo -e "${YELLOW}  ⚠ Патч частично применился, проверяем вручную...${NC}"
                    fi
                else
                    # Если пароля нет — просто добавляем participantName после password
                    sed -i 's|"password":.*|"password": password,\n"participantName": "'"${BOT_NAME}"'",|g' "$JAZZ_FILE"
                    echo -e "${YELLOW}  ⚠ Пароль пустой, participantName добавлен с пустым password${NC}"
                fi

                # Возвращаемся в корень репозитория
                cd ~/olcrtc

                # Проверяем что патч применился
                if grep -q '"participantName":.*'"${BOT_NAME}"'' "internal/provider/jazz/${JAZZ_FILE}" 2>/dev/null; then
                    echo -e "${GREEN}✓ Верификация: патч Jazz API v5 (v2.2.2) успешно интегрирован!${NC}"
                else
                    echo -e "${YELLOW}⚠ Верификация не удалась, но продолжаем сборку${NC}"
                fi
            fi
        fi
    fi

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

    # [9/9] Установка бинарника
    echo -e "\n${CYAN}[9/9] Установка собранного бинарника...${NC}"
    mkdir -p /opt/olcrtc/data
    systemctl stop olcrtc 2>/dev/null || true
    cp build/olcrtc-linux-amd64 /opt/olcrtc/olcrtc
    
    # Сохраняем версию коммита для будущих проверок обновлений
    cd ~/olcrtc
    git rev-parse HEAD > /opt/olcrtc/.local_version
    cd ~
    
    # Очищаем исходники после сборки
    rm -rf ~/olcrtc
    
    echo -e "${GREEN}✓ Бинарник установлен, версия сохранена.${NC}"
    echo -e "${GREEN}✓ Сборка завершена успешно!${NC}"
}

# ─────────────────────────────────────────────────────────────
# Быстрая настройка конфигурации (Сценарий Б: без сборки)
# ─────────────────────────────────────────────────────────────
quick_configure() {
    print_logo
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}[✓] Система установлена и актуальна.${NC}"
    echo -e "${GREEN}    Пропускаем этап компиляции.${NC}"
    echo -e "${GREEN}    Переходим к настройке конфигурации.${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    sleep 2
}

# ─────────────────────────────────────────────────────────────
# Показать текущий статус и реквизиты (Опция 4)
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
        echo -e "    Запустите установку через пункт 1 меню."
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

    # Пытаемся извлечь полную ссылку с паролем из systemd сервиса
    SAVED_LINK=""
    if [ -f /etc/systemd/system/olcrtc.service ]; then
        SAVED_LINK=$(grep -oP '^# FullLink=\K.*' /etc/systemd/system/olcrtc.service 2>/dev/null || echo "")
    fi

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

    # Показываем полную ссылку с паролем (восстановленную из systemd сервиса)
    if [ -n "$SAVED_LINK" ]; then
        if [[ "${S_PROVIDER}" == "jazz" ]]; then
            echo -e "Ссылка для участников (SaluteJazz):"
            echo -e "  ${YELLOW}${SAVED_LINK}${NC}"
            echo -e "  Код конференции: ${YELLOW}${S_ROOM_ID}@salutejazz.ru${NC}"
        elif [[ "${S_PROVIDER}" == "wbstream" ]]; then
            echo -e "Ссылка для участников (WB Stream):"
            echo -e "  ${YELLOW}${SAVED_LINK}${NC}"
        elif [[ "${S_PROVIDER}" == "telemost" ]]; then
            echo -e "Ссылка для участников (Yandex Telemost):"
            echo -e "  ${YELLOW}${SAVED_LINK}${NC}"
        fi
        if [ -n "${S_BOT_NAME}" ]; then
            echo -e "  Имя бота: ${YELLOW}${S_BOT_NAME}${NC}"
        fi
    else
        # Fallback — показываем обрезанную ссылку (для старых установок)
        if [[ "${S_PROVIDER}" == "jazz" && -n "${S_ROOM_ID}" ]]; then
            echo -e "Ссылка для участников (SaluteJazz):"
            echo -e "  ${YELLOW}https://salutejazz.ru/calls/${S_ROOM_ID}${NC}"
            echo -e "  Код конференции: ${YELLOW}${S_ROOM_ID}@salutejazz.ru${NC}"
            if [ -n "${S_BOT_NAME}" ]; then
                echo -e "  Имя бота: ${YELLOW}${S_BOT_NAME}${NC}"
            fi
        elif [[ "${S_PROVIDER}" == "wbstream" && -n "${S_ROOM_ID}" ]]; then
            echo -e "Ссылка для участников (WB Stream):"
            echo -e "  ${YELLOW}https://stream.wb.ru/room/${S_ROOM_ID}${NC}"
        fi
    fi
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "${GREEN}📥 Скачайте приложение Olcbox для вашей системы:${NC}"
    echo -e "  ${CYAN}https://github.com/alananisimov/olcbox/releases${NC}"
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

# Функция парсинга URL для Jazz
# Извлекает ROOM_ID и S_ROOM_PASSWORD из ссылки типа https://salutejazz.ru/calls/nlg7d4?psw=OAdbHAc...
parse_jazz_url() {
    local input_url="$1"
    
    # Если URL содержит ?psw=, извлекаем пароль
    if [[ "$input_url" == *"?psw="* ]]; then
        S_ROOM_PASSWORD="${input_url##*?psw=}"
        # Убираем всё после & или другие query параметры
        S_ROOM_PASSWORD="${S_ROOM_PASSWORD%%&*}"
    else
        S_ROOM_PASSWORD=""
    fi
    
    # Извлекаем ROOM_ID: убираем всё до последнего / и всё после ?
    local temp="${input_url%%\?*}"  # Убираем query параметры
    temp="${temp##*/}"              # Убираем всё до последнего /
    
    echo "$temp"
}

# Функция генерации случайного русского имени
generate_bot_name() {
    local idx=$((RANDOM % ${#RU_NAMES[@]}))
    echo "${RU_NAMES[idx]}"
}

# ─────────────────────────────────────────────────────────────
# Запрос реквизитов у пользователя (единый для обоих сценариев)
# Возвращает набор переменных: PROVIDER, TRANSPORT, ROOM_ID, ENC_KEY, CLIENT_ID, BOT_NAME, S_ROOM_PASSWORD, FULL_INVITE_LINK
# ─────────────────────────────────────────────────────────────
request_credentials() {
    while true; do
        print_logo
        echo -e "${MAGENTA}=================================================${NC}"
        echo -e "${GREEN}   Настройка OlcRTC (Сервер)                     ${NC}"
        echo -e "${MAGENTA}=================================================${NC}"
        echo -e "${YELLOW}ВНИМАНИЕ: Перед продолжением вы должны ВРУЧНУЮ создать комнату на сайте провайдера и скопировать ссылку-приглашение!${NC}\n"

        # --- 1. ВЫБОР ПРОВАЙДЕРА ---
        echo -e "${CYAN}Шаг 1: Выберите провайдера:${NC}"
        echo -e " 1) ${YELLOW}telemost (Yandex)${NC}       - стабильно работает"
        echo -e " 2) ${MAGENTA}wbstream (Wildberries)${NC} - стабильно работает"
        echo -e " 3) ${CYAN}jazz     (Sber SaluteJazz)${NC} - работает нестабильно"
        echo -e " 0) Назад в главное меню"
        read -p "Ваш выбор (0-3) [по умолчанию 1]: " prov_choice

        [[ "$prov_choice" == "0" ]] && return 1

        case $prov_choice in
            1) PROVIDER="telemost" ;;
            2) PROVIDER="wbstream" ;;
            3) PROVIDER="jazz" ;;
            *) PROVIDER="telemost" ;;
        esac

        # --- Генерация случайного русского имени для бота (только для Jazz) ---
        BOT_NAME=""
        if [[ "$PROVIDER" == "jazz" ]]; then
            BOT_NAME=$(generate_bot_name)
            echo -e "${GREEN}  ➤ Имя бота для конференции: ${YELLOW}${BOT_NAME}${NC}"
        fi

        # --- 2. ВЫБОР ТРАНСПОРТА ---
        echo -e "\n${CYAN}Шаг 2: Выберите тип транспорта:${NC}"

        if [[ "$PROVIDER" == "wbstream" ]]; then
            echo -e " 1) datachannel  ${GREEN}[рекомендуется — максимальная скорость]${NC}"
            echo -e " 2) vp8channel   (высокая скорость)"
            echo -e " 3) seichannel   (средняя скорость)"
            echo -e " 4) videochannel (низкая скорость)"
            echo -e " 0) Назад в главное меню"
            read -p "Ваш выбор (0-4) [по умолчанию 1]: " trans_choice
            [[ "$trans_choice" == "0" ]] && return 1
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
            [[ "$trans_choice" == "0" ]] && return 1
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
            [[ "$trans_choice" == "0" ]] && return 1
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

        echo -e "Создайте комнату и скопируйте ID (код в конце ссылки) или вставьте ссылку целиком:"
        echo -e " ▶ ${MAGENTA}WB Stream:${NC}       https://stream.wb.ru/room/ ${YELLOW}[ваш_id]${NC}"
        echo -e " ▶ ${YELLOW}Yandex Telemost:${NC} https://telemost.yandex.ru/j/ ${YELLOW}[ваш_id]${NC}"
        echo -e " ▶ ${CYAN}SaluteJazz:${NC}      https://salutejazz.ru/calls/ ${YELLOW}[ваш_id]${NC}\n"

        read -p "Введите ID звонка или вставьте полную ссылку на комнату: " ROOM_INPUT
        
        # Сохранение оригинальной ссылки с паролем (для вывода пользователю)
        if [[ "$ROOM_INPUT" == *"http"* ]]; then
            FULL_INVITE_LINK="$ROOM_INPUT"
        else
            case $PROVIDER in
                telemost) FULL_INVITE_LINK="https://telemost.yandex.ru/j/${ROOM_INPUT}" ;;
                wbstream) FULL_INVITE_LINK="https://stream.wb.ru/room/${ROOM_INPUT}" ;;
                jazz)     FULL_INVITE_LINK="https://salutejazz.ru/calls/${ROOM_INPUT}" ;;
                *)        FULL_INVITE_LINK="$ROOM_INPUT" ;;
            esac
        fi
        
        # Парсинг чистого ID для запуска бинарника
        if [[ "$PROVIDER" == "jazz" ]]; then
            S_ROOM_PASSWORD=""
            ROOM_ID=$(parse_jazz_url "$ROOM_INPUT")
            
            if [ -z "$S_ROOM_PASSWORD" ]; then
                echo -e "${CYAN}Пароль комнаты (если есть):${NC}"
                read -p "Введите пароль из ?psw=... (оставьте пустым если пароля нет): " S_ROOM_PASSWORD
                if [ -n "$S_ROOM_PASSWORD" ]; then
                    echo -e "${GREEN}Пароль комнаты сохранён: ${S_ROOM_PASSWORD}${NC}"
                else
                    echo -e "${YELLOW}Пароль не указан — комната будет открытой.${NC}"
                fi
            else
                echo -e "${GREEN}Пароль комнаты извлечён из ссылки: ${S_ROOM_PASSWORD}${NC}"
            fi
        else
            ROOM_ID="${ROOM_INPUT##*/}"; ROOM_ID="${ROOM_ID%%\?*}"
        fi
        
        while [ -z "$ROOM_ID" ]; do
            echo -e "${RED}Ошибка: ID звонка обязателен!${NC}"
            read -p "Введите ID звонка или вставьте полную ссылку на комнату: " ROOM_INPUT
            if [[ "$PROVIDER" == "jazz" ]]; then
                S_ROOM_PASSWORD=""
                ROOM_ID=$(parse_jazz_url "$ROOM_INPUT")
                if [ -z "$S_ROOM_PASSWORD" ]; then
                    read -p "Введите пароль из ?psw=...: " S_ROOM_PASSWORD
                fi
            else
                ROOM_ID="${ROOM_INPUT##*/}"; ROOM_ID="${ROOM_ID%%\?*}"
            fi
        done
        
        echo -e "${GREEN}Чистый ID звонка: ${ROOM_ID}${NC}"

        # --- 4. ВЫБОР КЛЮЧА ШИФРОВАНИЯ ---
        echo -e "\n${CYAN}Шаг 4: Настройка ключа шифрования:${NC}"
        echo -e " 1) Сгенерировать надёжный ключ автоматически (рекомендуется)"
        echo -e " 2) Ввести свой ключ вручную"
        echo -e " 0) Назад в главное меню"
        read -p "Ваш выбор (0-2) [по умолчанию 1]: " key_choice

        [[ "$key_choice" == "0" ]] && return 1

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

        [[ "$client_choice" == "0" ]] && return 1

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
    
    return 0
}

# ─────────────────────────────────────────────────────────────
# Применение конфигурации (systemd + .env)
# Вызывается после request_credentials() в обоих сценариях
# ─────────────────────────────────────────────────────────────
apply_configuration() {
    local PROVIDER="$1"
    local TRANSPORT="$2"
    local ROOM_ID="$3"
    local ENC_KEY="$4"
    local CLIENT_ID="$5"
    local BOT_NAME="$6"
    local S_ROOM_PASSWORD="$7"
    local FULL_INVITE_LINK="$8"
    
    echo -e "\n${CYAN}Применяем конфигурацию...${NC}"
    
    # Формирование флагов транспорта
    case $TRANSPORT in
        vp8channel)    TRANSPORT_FLAGS="-vp8-fps 60 -vp8-batch 64" ;;
        seichannel)    TRANSPORT_FLAGS="-fps 60 -batch 64 -frag 900 -ack-ms 2000" ;;
        videochannel)  TRANSPORT_FLAGS="-video-codec qrcode -video-w 1080 -video-h 1080 -video-fps 60 -video-bitrate 5000k -video-hw none" ;;
        *)             TRANSPORT_FLAGS="" ;;
    esac

    cat <<EOF > /etc/systemd/system/olcrtc.service
[Unit]
Description=OlcRTC Proxy Server
After=network.target
# FullLink=$FULL_INVITE_LINK

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
    systemctl restart olcrtc
    
    # Сохраняем реквизиты
    mkdir -p /opt/olcrtc
    cat > /opt/olcrtc/.env <<ENV_EOF
S_PROVIDER="${PROVIDER}"
S_TRANSPORT="${TRANSPORT}"
S_ROOM_ID="${ROOM_ID}"
S_ENC_KEY="${ENC_KEY}"
S_CLIENT_ID="${CLIENT_ID}"
S_ROOM_PASSWORD="${S_ROOM_PASSWORD}"
S_BOT_NAME="${BOT_NAME}"
ENV_EOF
    chmod 600 /opt/olcrtc/.env
}

# ─────────────────────────────────────────────────────────────
# Функция установки (с умной проверкой обновлений)
# ─────────────────────────────────────────────────────────────
install_olcrtc() {
    # Проверяем наличие предыдущей установки
    local EXISTING_INSTALL=false
    if [ -f /etc/systemd/system/olcrtc.service ] || [ -f /opt/olcrtc/olcrtc ]; then
        EXISTING_INSTALL=true
    fi
    
    # Проверяем обновления
    local UPDATE_NEEDED
    UPDATE_NEEDED=$(check_for_updates)
    
    # Обработка опции удаления/переустановки
    if [ "$EXISTING_INSTALL" = true ]; then
        print_logo
        echo -e "${MAGENTA}=================================================${NC}"
        echo -e "${YELLOW}   ⚠  Обнаружена предыдущая установка OlcRTC!   ${NC}"
        echo -e "${MAGENTA}=================================================${NC}"
        
        if [ "$UPDATE_NEEDED" = "update" ]; then
            echo -e "${CYAN}Доступно обновление бинарника.${NC}"
        else
            echo -e "${GREEN}Бинарник уже актуален.${NC}"
        fi
        
        echo -e "${YELLOW}Вы можете:${NC}"
        echo -e "  ${GREEN}1)${NC} Обновить конфигурацию (изменить комнату/транспорт)"
        echo -e "  ${RED}2)${NC} Переустановить с нуля (удалить всё и собрать заново)"
        echo -e "  ${CYAN}3)${NC} Только обновить бинарник (без изменения конфигурации)"
        echo -e "  ${MAGENTA}0)${NC} Назад в главное меню"
        read -p "Ваш выбор (0-3): " reinstall_choice
        
        case $reinstall_choice in
            0) return ;;
            1)
                # Только обновить конфигурацию (быстрый путь)
                if request_credentials; then
                    apply_configuration "$PROVIDER" "$TRANSPORT" "$ROOM_ID" "$ENC_KEY" "$CLIENT_ID" "$BOT_NAME" "$S_ROOM_PASSWORD" "$FULL_INVITE_LINK"
                    show_success_message
                fi
                return
                ;;
            2)
                # Полная переустановка
                echo -e "${CYAN}Выполняем полную очистку...${NC}"
                silent_wipe
                echo -e "${GREEN}Очистка завершена.${NC}"
                sleep 1
                UPDATE_NEEDED="update"
                ;;
            3)
                # Только обновить бинарник
                if [ "$UPDATE_NEEDED" = "update" ]; then
                    build_olcrtc_binary "telemost" "" ""  # Параметры Jazz будут взяты из текущей конфигурации если есть
                    # После сборки перечитаем старую конфигурацию если она была
                    if [ -f /opt/olcrtc/.env ]; then
                        source /opt/olcrtc/.env
                    fi
                    echo -e "${GREEN}✓ Бинарник обновлён!${NC}"
                    read -p "Нажмите Enter для возврата в меню..."
                else
                    echo -e "${GREEN}✓ Бинарник уже актуален. Обновление не требуется.${NC}"
                    read -p "Нажмите Enter для возврата в меню..."
                fi
                return
                ;;
            *)
                echo -e "${RED}Неверный выбор.${NC}"
                sleep 1
                return
                ;;
        esac
    fi
    
    # Сценарий А: Новая установка или обновление с пересборкой
    if [ "$UPDATE_NEEDED" = "update" ]; then
        # Запрашиваем реквизиты
        if ! request_credentials; then
            return
        fi
        
        # Собираем бинарник
        build_olcrtc_binary "$PROVIDER" "$S_ROOM_PASSWORD" "$BOT_NAME"
        
        # Применяем конфигурацию
        apply_configuration "$PROVIDER" "$TRANSPORT" "$ROOM_ID" "$ENC_KEY" "$CLIENT_ID" "$BOT_NAME" "$S_ROOM_PASSWORD" "$FULL_INVITE_LINK"
        
        show_success_message
    else
        # Сценарий Б: Актуальная система - только быстрая настройка
        quick_configure
        
        if ! request_credentials; then
            return
        fi
        
        apply_configuration "$PROVIDER" "$TRANSPORT" "$ROOM_ID" "$ENC_KEY" "$CLIENT_ID" "$BOT_NAME" "$S_ROOM_PASSWORD" "$FULL_INVITE_LINK"
        
        show_success_message
    fi
    
    read -p "Нажмите Enter для возврата в меню..."
}

# ─────────────────────────────────────────────────────────────
# Показать сообщение об успешной установке
# ─────────────────────────────────────────────────────────────
show_success_message() {
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}[✔] Конфигурация применена успешно!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "${GREEN} УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!${NC}"
    echo -e "${MAGENTA}=================================================${NC}"

    # Ссылки на конференцию для участников (с полной ссылкой включая пароль)
    if [[ "$PROVIDER" == "telemost" ]]; then
        echo -e "Ссылка для участников (Yandex Telemost):"
        echo -e "  ${YELLOW}${FULL_INVITE_LINK}${NC}"
    elif [[ "$PROVIDER" == "wbstream" ]]; then
        echo -e "Ссылка для участников (WB Stream):"
        echo -e "  ${YELLOW}${FULL_INVITE_LINK}${NC}"
    elif [[ "$PROVIDER" == "jazz" ]]; then
        echo -e "Ссылка для участников (SaluteJazz):"
        echo -e "  ${YELLOW}${FULL_INVITE_LINK}${NC}"
        echo -e "  Код конференции: ${YELLOW}${ROOM_ID}@salutejazz.ru${NC}"
        echo -e "${GREEN}[+] Имя бота в конференции: ${YELLOW}${BOT_NAME}${NC}"
    fi
    echo -e "${MAGENTA}=================================================${NC}"

    echo -e "Ваши данные для подключения в клиенте (Olcbox):"
    echo -e "Провайдер:\t${YELLOW}$PROVIDER${NC}"
    echo -e "Транспорт:\t${YELLOW}$TRANSPORT${NC}"
    echo -e "ID звонка:\t${YELLOW}$ROOM_ID${NC}"
    echo -e "Ключ:\t\t${YELLOW}$ENC_KEY${NC}"
    echo -e "ID клиента:\t${YELLOW}$CLIENT_ID${NC}"
    if [[ "$PROVIDER" == "jazz" ]]; then
        echo -e "Имя бота:\t${YELLOW}$BOT_NAME${NC}"
    fi
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "URI для быстрого импорта в Olcbox:"
    echo -e "${YELLOW}olcrtc://${PROVIDER}?${TRANSPORT}@${ROOM_ID}#${ENC_KEY}%${CLIENT_ID}\$OlcRTC_Server${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
    echo -e "${GREEN}📥 Скачайте приложение Olcbox для вашей системы:${NC}"
    echo -e "  ${CYAN}https://github.com/alananisimov/olcbox/releases${NC}"
    echo -e "${MAGENTA}=================================================${NC}"
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
    read -p "Вы уверены, что хотите продолжить? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" && "$confirm" != "н" && "$confirm" != "Н" && "$confirm" != "д" && "$confirm" != "Д" ]]; then
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
    if [[ "$remove_go" == "y" || "$remove_go" == "Y" || "$remove_go" == "н" || "$remove_go" == "Н" || "$remove_go" == "д" || "$remove_go" == "Д" ]]; then
        rm -rf /usr/local/go
        rm -f /etc/profile.d/go.sh
        echo -e "${GREEN}Go успешно удалён.${NC}"
    fi

    read -p "Удалить файл подкачки (/swapfile)? (y/n): " remove_swap
    if [[ "$remove_swap" == "y" || "$remove_swap" == "Y" || "$remove_swap" == "н" || "$remove_swap" == "Н" || "$remove_swap" == "д" || "$remove_swap" == "Д" ]]; then
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
    echo -e " ${GREEN}1)${NC} Установить OlcRTC (полная настройка)"
    echo -e " ${RED}2)${NC} Удалить OlcRTC"
    echo -e " ${CYAN}3)${NC} Посмотреть логи сервера"
    echo -e " ${YELLOW}4)${NC} Проверить статус и реквизиты"
    echo -e "${MAGENTA}─────────────────────────────────────────────────${NC}"
    echo -e " ${YELLOW}0)${NC} Выйти"
    echo -e "${MAGENTA}=================================================${NC}"
    read -p "Выберите действие (0-4): " choice

    case $choice in
        1) install_olcrtc ;;
        2) uninstall_olcrtc ;;
        3)
            # ── Подменю логов ─────────────────────────────────
            while true; do
                print_logo
                echo -e "${MAGENTA}=================================================${NC}"
                echo -e "${CYAN}         Просмотр логов службы OlcRTC            ${NC}"
                echo -e "${MAGENTA}=================================================${NC}"
                echo -e " ${GREEN}1)${NC} Показать последние 50 строк (статический)"
                echo -e " ${YELLOW}2)${NC} Живой онлайн-лог (обновления в реальном времени)"
                echo -e "${MAGENTA}─────────────────────────────────────────────────${NC}"
                echo -e " ${RED}0)${NC} Назад в главное меню"
                echo -e "${MAGENTA}=================================================${NC}"
                echo -e "${YELLOW}⚠ Для выхода из живого лога нажмите ${RED}Ctrl+C${YELLOW}.${NC}"
                echo -e "${YELLOW}   Это полностью завершит работу скрипта.${NC}"
                echo -e "${MAGENTA}=================================================${NC}"
                read -p "Ваш выбор (0-2) [по умолчанию 1]: " log_choice

                case $log_choice in
                    0)
                        # Назад в главное меню
                        break
                        ;;
                    1|"")
                        # Статический лог (по умолчанию)
                        echo -e "${CYAN}Загружаю последние 50 строк лога...${NC}"
                        echo
                        journalctl -u olcrtc -n 50 --no-pager
                        echo
                        read -p "Нажмите Enter для возврата в меню логов..."
                        # Показываем подменю снова
                        continue
                        ;;
                    2)
                        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                        echo -e "${YELLOW}Запуск живого лога. Нажмите ${RED}Ctrl+C${YELLOW} для выхода.${NC}"
                        echo -e "${YELLOW}Скрипт будет полностью завершён.${NC}"
                        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                        journalctl -u olcrtc -f -n 50
                        # Ctrl+C здесь — exit из скрипта целиком
                        exit 0
                        ;;
                    *)
                        echo -e "${RED}Неверный ввод. Попробуйте снова.${NC}"
                        sleep 1
                        continue
                        ;;
                esac
            done
            ;;
        4) show_status ;;
        0)
            echo -e "${GREEN}Выход. Удачи!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный ввод. Пожалуйста, выберите от 0 до 4.${NC}"
            sleep 1
            ;;
    esac
done
