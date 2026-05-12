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

    # Настройка Swap
    echo -e "\n${CYAN}[1/6] Настройка Swap (файла подкачки)...${NC}"
    if [ ! -f /swapfile ]; then
        fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/f
