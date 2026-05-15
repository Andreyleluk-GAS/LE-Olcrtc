# SberJazz Next API Patch v6 — Документация

## Проблема

SberJazz обновил API безопасности. Вместо plain-text пароля теперь используется зашифрованный хэш в параметре `?psw=`:
```
https://salutejazz.ru/calls/nlg7d4?psw=OAdbHAcFHUcNF1wKWBEKVAIdQQ
```

Старый патч (v2.2.2) отправлял plain-text пароль → сервер отклонял WebRTC-соединение (media timeout).

---

## Решение: JAZZ API PATCH v6

### Что изменено:

1. **Функция `parse_jazz_url()`** — теперь извлекает `S_ROOM_PSW_HASH` из `?psw=` вместо plain-text пароля
2. **Блок `JAZZ API PATCH`** — теперь использует `passwordHash` вместо `password` при наличии хэша

### Алгоритм работы:

```
┌─────────────────────────────────────────────────────────────┐
│  ВХОД: https://salutejazz.ru/calls/ROOM_ID?psw=HASH       │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  1. parse_jazz_url() извлекает:                            │
│     • S_ROOM_PSW_HASH = "OAdbHAcFHUcNF1wKWBEKVAIdQQ"       │
│     • S_ROOM_PASSWORD = "" (не используется)               │
│     • ROOM_ID = "nlg7d4"                                   │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  2. JAZZ API PATCH v6:                                     │
│     Если S_ROOM_PSW_HASH не пустой:                        │
│       → Заменяет "password": password на:                   │
│         "passwordHash": "OAdbHAcFHUcNF1wKWBEKVAIdQQ",      │
│         "participantName": "BOT_NAME"                       │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Результат в JSON:                                      │
│     {                                                      │
│       "roomId": "nlg7d4",                                  │
│       "passwordHash": "OAdbHAcFHUcNF1wKWBEKVAIdQQ",        │
│       "participantName": "Мария"                            │
│     }                                                      │
└─────────────────────────────────────────────────────────────┘
```

---

## ОБНОВЛЁННЫЙ БЛОК КОДА ДЛЯ install-olcrtc.sh

### 1. Заменить функцию `parse_jazz_url()` (строки ~581-600):

```bash
# Функция парсинга URL для Jazz
# Извлекает ROOM_ID, S_ROOM_PASSWORD и S_ROOM_PSW_HASH из ссылки типа 
# https://salutejazz.ru/calls/nlg7d4?psw=OAdbHAcFHUcNF1wKWBEKVAIdQQ
# Поддерживает новый формат SberJazz Next API с зашифрованным хэшем
parse_jazz_url() {
    local input_url="$1"
    
    # Если URL содержит ?psw=, извлекаем ЗАШИФРОВАННЫЙ хэш
    # Это НОВЫЙ формат SberJazz Next API
    if [[ "$input_url" == *"?psw="* ]]; then
        S_ROOM_PSW_HASH="${input_url##*?psw=}"
        S_ROOM_PSW_HASH="${S_ROOM_PSW_HASH%%&*}"
        # Если хэш слишком короткий — это не валидный хэш
        if [ ${#S_ROOM_PSW_HASH} -lt 10 ]; then
            S_ROOM_PSW_HASH=""
        fi
    else
        S_ROOM_PSW_HASH=""
    fi
    
    # Если есть plain пароль в URL (?pwd=) — используем его как fallback
    if [[ "$input_url" == *"pwd="* ]]; then
        local pwd_part="${input_url##*pwd=}"
        pwd_part="${pwd_part%%&*}"
        # Только если нет хэша — используем plain password
        if [ -z "$S_ROOM_PSW_HASH" ] && [ -n "$pwd_part" ]; then
            S_ROOM_PASSWORD="$pwd_part"
        else
            S_ROOM_PASSWORD=""
        fi
    else
        # Plain password не найден — для Next API он не нужен
        [ -z "$S_ROOM_PSW_HASH" ] && S_ROOM_PASSWORD=""
    fi
    
    # Извлекаем ROOM_ID: убираем всё до последнего / и всё после ?
    local temp="${input_url%%\?*}"
    temp="${temp##*/}"
    
    echo "$temp"
}
```

### 2. Заменить блок JAZZ API PATCH v5 (строки ~286-371):

```bash
    # ─────────────────────────────────────────────────────────────
    # JAZZ API PATCH v6: Поддержка SberJazz Next API (psw hash)
    # Использует S_ROOM_PSW_HASH из ?psw= вместо plain-text пароля
    # Целевой путь: ~/olcrtc/internal/provider/jazz/jazz.go (или api.go)
    # ─────────────────────────────────────────────────────────────
    if [[ "$PROVIDER" == "jazz" ]]; then
        echo -e "${CYAN}Применяю патч Jazz Next API v6 (psw hash)...${NC}"
        echo -e "${YELLOW}  ➤ Используем имя бота: ${BOT_NAME}${NC}"
        
        # Проверяем наличие хэша из URL
        if [ -n "$S_ROOM_PSW_HASH" ]; then
            echo -e "${YELLOW}  ➤ Обнаружен зашифрованный хэш: ${S_ROOM_PSW_HASH}${NC}"
        elif [ -n "$S_ROOM_PASSWORD" ]; then
            echo -e "${YELLOW}  ➤ Используем plain password (fallback): ${S_ROOM_PASSWORD}${NC}"
        else
            echo -e "${YELLOW}  ➤ Пароль не обнаружен — открытая комната${NC}"
        fi

        # Проверяем что директория существует
        if [ ! -d "internal/provider/jazz" ]; then
            echo -e "${RED}✖ Директория internal/provider/jazz не найдена!${NC}"
            echo -e "${YELLOW}  Структура репозитория могла измениться.${NC}"
            echo -e "${YELLOW}  Продолжаем сборку без патча...${NC}"
        else
            cd internal/provider/jazz
            JAZZ_FILE=""
            
            # Приоритет: jazz.go -> api.go
            for candidate in "jazz.go" "api.go"; do
                if [ -f "$candidate" ]; then
                    JAZZ_FILE="$candidate"
                    break
                fi
            done
            
            if [ -z "$JAZZ_FILE" ]; then
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
                # v2.2.4: Новая логика патчинга с поддержкой psw hash
                # 1. Удаляем старые participantName и passwordHash если есть
                # 2. Если есть S_ROOM_PSW_HASH — добавляем passwordHash + participantName
                # 3. Если есть только S_ROOM_PASSWORD — используем old-way патч
                # ─────────────────────────────────────────────────────────────

                # 1. Удаляем старые поля если они там есть
                sed -i '/"participantName":/d' "$JAZZ_FILE"
                sed -i '/"passwordHash":/d' "$JAZZ_FILE"
                echo -e "${CYAN}  [1/3] Удаление старых полей (participantName, passwordHash)${NC}"

                # 2. Работаем в зависимости от типа авторизации
                if [ -n "$S_ROOM_PSW_HASH" ]; then
                    # NEW API: Используем зашифрованный хэш из URL
                    # Заменяем "password": password на "passwordHash": "PSW_HASH", "participantName": "BOT_NAME"
                    sed -i 's|"password":\s*password|"passwordHash": "'"${S_ROOM_PSW_HASH}"'",\n"participantName": "'"${BOT_NAME}"'",|g' "$JAZZ_FILE"
                    echo -e "${GREEN}  [2/3] ✓ Используем passwordHash из ?psw= (SberJazz Next API)${NC}"
                elif [ -n "$S_ROOM_PASSWORD" ]; then
                    # OLD API fallback: Используем plain-text пароль
                    sed -i 's|"password":\s*password|"password": password + "'"${S_ROOM_PASSWORD}"'",\n"participantName": "'"${BOT_NAME}"'",|g' "$JAZZ_FILE"
                    echo -e "${YELLOW}  [2/3] ⚠ Используем plain password (старый API)${NC}"
                else
                    # OPEN ROOM: Только participantName
                    sed -i 's|"password":\s*password|"password": password,\n"participantName": "'"${BOT_NAME}"'",|g' "$JAZZ_FILE"
                    echo -e "${YELLOW}  [2/3] ⚠ Открытая комната без пароля${NC}"
                fi

                # 3. Проверяем успешность патча
                if [ -n "$S_ROOM_PSW_HASH" ]; then
                    if grep -q '"passwordHash":.*'"${S_ROOM_PSW_HASH}"'' "$JAZZ_FILE" && grep -q '"participantName":.*'"${BOT_NAME}"'' "$JAZZ_FILE"; then
                        echo -e "${GREEN}  [3/3] ✓ patch v2.2.4 (Next API) успешно интегрирован!${NC}"
                    else
                        echo -e "${YELLOW}  [3/3] ⚠ Патч частично применился, проверяем вручную...${NC}"
                    fi
                else
                    if grep -q '"participantName":.*'"${BOT_NAME}"'' "$JAZZ_FILE"; then
                        echo -e "${GREEN}  [3/3] ✓ patch v2.2.4 (fallback) успешно интегрирован!${NC}"
                    else
                        echo -e "${YELLOW}  [3/3] ⚠ Патч частично применился, проверяем вручную...${NC}"
                    fi
                fi

                cd ~/olcrtc

                # Финальная верификация
                if grep -q '"participantName":.*'"${BOT_NAME}"'' "internal/provider/jazz/${JAZZ_FILE}" 2>/dev/null; then
                    echo -e "${GREEN}✓ Верификация: патч Jazz API v6 успешно интегрирован!${NC}"
                else
                    echo -e "${YELLOW}⚠ Верификация не удалась, но продолжаем сборку${NC}"
                fi
            fi
        fi
    fi
```

---

## Использование патч-скрипта

### Автоматическое применение (рекомендуется):

```bash
# Сделать скрипт исполняемым
chmod +x patch_jazz_v6.sh

# Запустить патч
./patch_jazz_v6.sh
```

### Ручное применение:

Скопируйте блоки кода из разделов выше и замените соответствующие секции в `install-olcrtc.sh`.

---

## Ожидаемые логи после патча

```
[1/2] Обновление функции parse_jazz_url...
✓ Функция parse_jazz_url обновлена

[2/2] Обновление JAZZ API PATCH v5 на v6...
✓ JAZZ API PATCH v6 успешно установлен!

Применяю патч Jazz Next API v6 (psw hash)...
  ➤ Используем имя бота: Мария
  ➤ Обнаружен зашифрованный хэш: OAdbHAcFHUcNF1wKWBEKVAIdQQ
  Найден файл: api.go
  Резервная копия создана: api.go.bak
  [1/3] Удаление старых полей (participantName, passwordHash)
  [2/3] ✓ Используем passwordHash из ?psw= (SberJazz Next API)
  [3/3] ✓ patch v2.2.4 (Next API) успешно интегрирован!
✓ Верификация: патч Jazz API v6 успешно интегрирован!
```

---

## Совместимость

| Сценарий | S_ROOM_PSW_HASH | S_ROOM_PASSWORD | Поведение |
|----------|-----------------|-----------------|-----------|
| Новый API (с хэшем) | ✅ Заполнен | Пусто | Использует `passwordHash` |
| Старый API (plain pwd) | Пусто | ✅ Заполнен | Использует `password + pwd` |
| Открытая комната | Пусто | Пусто | Только `participantName` |

---

## Версии

- **v6** — Текущая. Поддержка SberJazz Next API с `?psw=` хэшем
- **v5** — Предыдущая. Использовала только plain-text пароль (устарела)
- **v2.2.2** — Исходный патч (устарел)
