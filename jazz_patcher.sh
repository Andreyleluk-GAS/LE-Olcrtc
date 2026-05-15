#!/bin/bash
# =============================================================================
# JAZZ PATCHER v2.2.4: Поддержка SberJazz Next API
# Этот скрипт вызывается из install-olcrtc.sh при сборке для провайдера Jazz
# 
# Аргументы:
#   $1 - BOT_NAME (имя бота, например "Мария")
#   $2 - S_ROOM_PSW_HASH (зашифрованный хэш из ?psw=, для Next API)
#   $3 - S_ROOM_PASSWORD (plain-text пароль, fallback для старого API)
# =============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Аргументы
BOT_NAME="${1:-}"
S_ROOM_PSW_HASH="${2:-}"
S_ROOM_PASSWORD="${3:-}"

echo -e "${CYAN}[Jazz Patcher] Запуск...${NC}"

# Проверяем обязательные параметры
if [ -z "$BOT_NAME" ]; then
    echo -e "${RED}✖ Ошибка: BOT_NAME не указан${NC}"
    echo "Использование: ./jazz_patcher.sh <BOT_NAME> <PSW_HASH> <PASSWORD>"
    exit 1
fi

# Определяем директорию скрипта и корневую директорию проекта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR" && pwd)"

echo -e "${YELLOW}  ➤ BOT_NAME: ${BOT_NAME}${NC}"

# Показываем что используется для авторизации
if [ -n "$S_ROOM_PSW_HASH" ]; then
    echo -e "${YELLOW}  ➤ PSW_HASH: ${S_ROOM_PSW_HASH}${NC}"
    AUTH_TYPE="Next API (passwordHash)"
elif [ -n "$S_ROOM_PASSWORD" ]; then
    echo -e "${YELLOW}  ➤ PASSWORD: ${S_ROOM_PASSWORD}${NC}"
    AUTH_TYPE="Legacy API (plain password)"
else
    echo -e "${YELLOW}  ➤ Открытая комната (без пароля)${NC}"
    AUTH_TYPE="Open room"
fi

# Ищем директорию с исходниками Jazz
JAZZ_DIR=""
if [ -d "$PROJECT_DIR/internal/provider/jazz" ]; then
    JAZZ_DIR="$PROJECT_DIR/internal/provider/jazz"
elif [ -d "$PROJECT_DIR/../internal/provider/jazz" ]; then
    JAZZ_DIR="$PROJECT_DIR/../internal/provider/jazz"
else
    echo -e "${RED}✖ Директория internal/provider/jazz не найдена!${NC}"
    echo "Искали в: $PROJECT_DIR/internal/provider/jazz"
    exit 0
fi

echo -e "${CYAN}  Директория Jazz: ${JAZZ_DIR}${NC}"
cd "$JAZZ_DIR"

# Ищем файл для патчинга
JAZZ_FILE=""
for candidate in "jazz.go" "api.go" "jazz_api.go" "signaling.go"; do
    if [ -f "$candidate" ]; then
        # Проверяем что файл содержит password
        if grep -q '"password":' "$candidate" 2>/dev/null; then
            JAZZ_FILE="$candidate"
            echo -e "${GREEN}  ✓ Найден файл: ${JAZZ_FILE}${NC}"
            break
        fi
    fi
done

if [ -z "$JAZZ_FILE" ]; then
    echo -e "${RED}✖ Файл с JSON payload не найден!${NC}"
    exit 0
fi

# Создаём резервную копию
BACKUP_FILE="${JAZZ_FILE}.bak"
cp "$JAZZ_FILE" "$BACKUP_FILE"
echo -e "${CYAN}  Резервная копия: ${BACKUP_FILE}${NC}"

# =============================================================================
# ПАТЧИНГ: Заменяем структуру JSON для авторизации
# =============================================================================

echo -e "${CYAN}  Применяю патч...${NC}"

# Удаляем старые поля participantName и passwordHash если они есть
sed -i '/"participantName":/d' "$JAZZ_FILE"
sed -i '/"passwordHash":/d' "$JAZZ_FILE"
echo -e "${CYAN}    [1/3] Удаление старых полей (participantName, passwordHash)${NC}"

# Определяем тип авторизации и применяем соответствующий патч
if [ -n "$S_ROOM_PSW_HASH" ]; then
    # =============================================================================
    # NEXT API: Используем passwordHash из ?psw=
    # Заменяем "password": password на passwordHash + participantName
    # =============================================================================
    echo -e "${GREEN}    [2/3] Используем passwordHash (Next API)${NC}"
    
    # Универсальный паттерн для замены
    # Ищем строку вида "password": password ИЛИ "password": "something"
    sed -i "s|\"password\":[[:space:]]*password|\"passwordHash\": \"${S_ROOM_PSW_HASH}\",\n\t\t\"participantName\": \"${BOT_NAME}\"|g" "$JAZZ_FILE"
    
    # Если не сработал первый паттерн, пробуем другой
    if ! grep -q "passwordHash.*${S_ROOM_PSW_HASH}" "$JAZZ_FILE"; then
        sed -i "s|\"password\":[[:space:]]*\"[^\"]*\"|\"passwordHash\": \"${S_ROOM_PSW_HASH}\",\n\t\t\"participantName\": \"${BOT_NAME}\"|g" "$JAZZ_FILE"
    fi
    
    echo -e "${GREEN}    [3/3] ✓ Патч Next API применён${NC}"
    
elif [ -n "$S_ROOM_PASSWORD" ]; then
    # =============================================================================
    # LEGACY API: Используем plain-text пароль (fallback)
    # Добавляем participantName после password
    # =============================================================================
    echo -e "${YELLOW}    [2/3] Используем plain password (Legacy API)${NC}"
    
    sed -i "s|\"password\":[[:space:]]*password|\"password\": password + \"${S_ROOM_PASSWORD}\",\n\t\t\"participantName\": \"${BOT_NAME}\"|g" "$JAZZ_FILE"
    
    # Если не сработал первый паттерн
    if ! grep -q "password + \"${S_ROOM_PASSWORD}\"" "$JAZZ_FILE"; then
        sed -i "s|\"password\":[[:space:]]*\"[^\"]*\"|\"password\": password + \"${S_ROOM_PASSWORD}\",\n\t\t\"participantName\": \"${BOT_NAME}\"|g" "$JAZZ_FILE"
    fi
    
    echo -e "${YELLOW}    [3/3] ✓ Патч Legacy API применён${NC}"
    
else
    # =============================================================================
    # OPEN ROOM: Без пароля, только participantName
    # =============================================================================
    echo -e "${YELLOW}    [2/3] Открытая комната (без пароля)${NC}"
    
    sed -i "s|\"password\":[[:space:]]*password|\"password\": password,\n\t\t\"participantName\": \"${BOT_NAME}\"|g" "$JAZZ_FILE"
    
    echo -e "${YELLOW}    [3/3] ✓ Патч для открытой комнаты применён${NC}"
fi

# =============================================================================
# ВЕРИФИКАЦИЯ
# =============================================================================

echo -e "${CYAN}  Проверка результата...${NC}"

VERIFIED=false

if [ -n "$S_ROOM_PSW_HASH" ]; then
    # Проверяем что passwordHash применился
    if grep -q "passwordHash.*${S_ROOM_PSW_HASH}" "$JAZZ_FILE" && grep -q "participantName.*${BOT_NAME}" "$JAZZ_FILE"; then
        echo -e "${GREEN}  ✓ Верификация успешна! passwordHash + participantName найдены${NC}"
        VERIFIED=true
    fi
elif [ -n "$S_ROOM_PASSWORD" ]; then
    # Проверяем что participantName применился
    if grep -q "participantName.*${BOT_NAME}" "$JAZZ_FILE"; then
        echo -e "${GREEN}  ✓ Верификация успешна! participantName найден${NC}"
        VERIFIED=true
    fi
else
    # Проверяем participantName
    if grep -q "participantName.*${BOT_NAME}" "$JAZZ_FILE"; then
        echo -e "${GREEN}  ✓ Верификация успешна! participantName найден${NC}"
        VERIFIED=true
    fi
fi

if [ "$VERIFIED" = false ]; then
    echo -e "${YELLOW}  ⚠ Верификация не удалась, но продолжаем${NC}"
    echo -e "${YELLOW}    Рекомендуется проверить файл вручную: ${JAZZ_DIR}/${JAZZ_FILE}${NC}"
fi

# Показываем изменения
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}[✓] JAZZ PATCHER v2.2.4 завершён успешно!${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Тип авторизации: ${YELLOW}${AUTH_TYPE}${NC}"
echo -e "Файл изменён: ${YELLOW}${JAZZ_DIR}/${JAZZ_FILE}${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

exit 0