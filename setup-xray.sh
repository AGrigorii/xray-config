#!/bin/bash

# Главный скрипт установки Xray-core с REALITY
# Автоматически выполняет все необходимые шаги установки и настройки

set -Eeuo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функции для вывода
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

section() {
    echo -e "\n${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}\n"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Проверка прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        error "Этот скрипт требует прав root (sudo)"
        echo "Запустите: sudo $0"
        exit 1
    fi
}

# Получение IP адреса сервера
get_server_ip() {
    local server_ip
    
    if command -v curl &> /dev/null; then
        server_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
    elif command -v wget &> /dev/null; then
        server_ip=$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || wget -qO- --timeout=5 https://ifconfig.me 2>/dev/null || echo "")
    fi
    
    if [ -z "$server_ip" ]; then
        warn "Не удалось автоматически определить внешний IP"
        echo -n "Введите внешний IP адрес сервера: "
        read -r server_ip
        if [ -z "$server_ip" ]; then
            error "IP адрес не может быть пустым"
            exit 1
        fi
    fi
    
    echo "$server_ip"
}

# Определение пути к скриптам
get_script_dir() {
    local script_path="$0"
    local script_dir
    
    # Если скрипт запущен с полным путем
    if [[ "$script_path" == /* ]]; then
        script_dir=$(dirname "$script_path")
    # Если скрипт запущен относительно текущей директории
    elif [[ "$script_path" == */* ]]; then
        script_dir=$(dirname "$(pwd)/$script_path")
    else
        # Скрипт в PATH или текущей директории
        if [ -f "./$script_path" ]; then
            script_dir=$(pwd)
        else
            # Пробуем найти через which
            local full_path
            full_path=$(which "$script_path" 2>/dev/null || echo "")
            if [ -n "$full_path" ]; then
                script_dir=$(dirname "$full_path")
            else
                script_dir=$(pwd)
            fi
        fi
    fi
    
    # Преобразуем в абсолютный путь
    cd "$script_dir" && pwd
}

# Основная функция
main() {
    section "Xray-core REALITY VPN - Автоматическая установка"
    
    # Проверка прав
    check_root
    
    # Определение директории скриптов
    SCRIPT_DIR="$(get_script_dir)"
    SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
    
    # Если скрипты не найдены в подпапке, пробуем текущую директорию
    if [ ! -d "$SCRIPTS_DIR" ]; then
        if [ -f "${SCRIPT_DIR}/server-setup.sh" ]; then
            SCRIPTS_DIR="$SCRIPT_DIR"
        else
            error "Не найдена папка scripts. Убедитесь, что скрипт находится в корне репозитория."
            exit 1
        fi
    fi
    
    info "Директория скриптов: $SCRIPTS_DIR"
    
    # Шаг 1: Установка Xray-core и зависимостей
    section "Шаг 1: Установка Xray-core"
    
    if [ -f "${SCRIPTS_DIR}/server-setup.sh" ]; then
        info "Запуск server-setup.sh..."
        chmod +x "${SCRIPTS_DIR}/server-setup.sh" 2>/dev/null || true
        "${SCRIPTS_DIR}/server-setup.sh"
        success "Установка Xray-core завершена"
    else
        error "Не найден скрипт server-setup.sh"
        exit 1
    fi
    
    # Проверка установки Xray
    if ! command -v xray &> /dev/null; then
        error "Xray-core не установлен. Проверьте вывод выше."
        exit 1
    fi
    
    XRAY_VERSION="$(xray version | head -n 1)"
    success "Xray-core установлен: $XRAY_VERSION"
    
    # Шаг 2: Генерация конфигурации
    section "Шаг 2: Генерация конфигурации"
    
    if [ -f "${SCRIPTS_DIR}/generate-config.sh" ]; then
        info "Запуск generate-config.sh..."
        chmod +x "${SCRIPTS_DIR}/generate-config.sh" 2>/dev/null || true
        
        # Переходим в домашнюю директорию для генерации конфигов
        HOME_DIR="${HOME:-/root}"
        cd "$HOME_DIR" || exit 1
        info "Рабочая директория: $(pwd)"
        
        # Запускаем генерацию (скрипт может запросить выбор сайта)
        "${SCRIPTS_DIR}/generate-config.sh"
        success "Конфигурация сгенерирована"
    else
        error "Не найден скрипт generate-config.sh"
        exit 1
    fi
    
    # Определяем домашнюю директорию
    HOME_DIR="${HOME:-/root}"
    
    # Проверка наличия config.json
    CONFIG_FILE=""
    if [ -f "${HOME_DIR}/config.json" ]; then
        CONFIG_FILE="${HOME_DIR}/config.json"
    elif [ -f /root/config.json ]; then
        CONFIG_FILE=/root/config.json
    elif [ -f ~/config.json ]; then
        CONFIG_FILE=~/config.json
    else
        error "Конфигурация не была создана. Проверьте вывод выше."
        exit 1
    fi
    
    info "Найден config.json: $CONFIG_FILE"
    
    # Шаг 3: Проверка конфигурации
    section "Шаг 3: Проверка конфигурации"
    
    info "Проверка валидности config.json..."
    if xray -test -config "$CONFIG_FILE" 2>&1 | grep -q "Configuration OK"; then
        success "Конфигурация валидна"
    else
        warn "Обнаружены предупреждения в конфигурации:"
        xray -test -config "$CONFIG_FILE" 2>&1 | tail -n 10 || true
        warn "Продолжаем установку..."
    fi
    
    # Шаг 4: Установка конфигурации
    section "Шаг 4: Установка конфигурации сервера"
    
    info "Копирование конфигурации в /usr/local/etc/xray/config.json..."
    cp "$CONFIG_FILE" /usr/local/etc/xray/config.json
    
    info "Установка прав доступа..."
    chown nobody:nogroup /usr/local/etc/xray/config.json 2>/dev/null || \
    chown nobody:nobody /usr/local/etc/xray/config.json 2>/dev/null || \
    warn "Не удалось установить владельца nobody. Продолжаем..."
    
    chmod 644 /usr/local/etc/xray/config.json
    success "Конфигурация установлена"
    
    # Шаг 5: Настройка и запуск сервиса
    section "Шаг 5: Запуск сервиса Xray"
    
    info "Перезагрузка systemd..."
    systemctl daemon-reload
    
    info "Запуск сервиса xray..."
    systemctl restart xray || {
        error "Не удалось запустить сервис xray"
        echo "Проверьте логи: journalctl -u xray -n 50"
        exit 1
    }
    
    info "Включение автозапуска..."
    systemctl enable xray
    
    # Проверка статуса
    sleep 2
    if systemctl is-active --quiet xray; then
        success "Сервис xray запущен и работает"
    else
        error "Сервис xray не запущен"
        echo "Статус:"
        systemctl status xray --no-pager -l | head -n 15
        echo ""
        echo "Логи:"
        journalctl -u xray -n 20 --no-pager
        exit 1
    fi
    
    # Шаг 6: Получение информации для копирования конфигов
    section "Шаг 6: Информация для копирования конфигов"
    
    SERVER_IP=$(get_server_ip)
    
    # Определяем путь к client-configs (используем абсолютный путь для scp)
    HOME_DIR="${HOME:-/root}"
    CLIENT_CONFIGS_DIR=""
    if [ -d "${HOME_DIR}/client-configs" ]; then
        CLIENT_CONFIGS_DIR="${HOME_DIR}/client-configs"
    elif [ -d /root/client-configs ]; then
        CLIENT_CONFIGS_DIR="/root/client-configs"
    fi
    
    if [ -z "$CLIENT_CONFIGS_DIR" ] || [ ! -d "$CLIENT_CONFIGS_DIR" ]; then
        warn "Папка client-configs не найдена"
        # Используем стандартный путь на основе домашней директории
        CLIENT_CONFIGS_DIR="${HOME_DIR}/client-configs"
    fi
    
    # Определяем пользователя для SSH (обычно root)
    SSH_USER="root"
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        # Если запущено через sudo, используем оригинального пользователя
        SSH_USER="$SUDO_USER"
    fi
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ Установка завершена успешно!${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Клиентские конфигурации находятся в:${NC}"
    echo -e "  ${CLIENT_CONFIGS_DIR}"
    echo ""
    echo -e "${YELLOW}Для копирования конфигов на локальную машину выполните:${NC}"
    echo ""
    echo -e "${CYAN}# Создайте папку для конфигов (если нужно):${NC}"
    echo -e "  mkdir -p ./client-configs"
    echo ""
    echo -e "${CYAN}# Скопируйте все конфиги:${NC}"
    echo -e "  ${GREEN}scp ${SSH_USER}@${SERVER_IP}:${CLIENT_CONFIGS_DIR}/* ./client-configs/${NC}"
    echo ""
    echo -e "${CYAN}# Или скопируйте всю папку:${NC}"
    echo -e "  ${GREEN}scp -r ${SSH_USER}@${SERVER_IP}:${CLIENT_CONFIGS_DIR} ./${NC}"
    echo ""
    echo -e "${YELLOW}Доступные файлы:${NC}"
    if [ -d "$CLIENT_CONFIGS_DIR" ]; then
        ls -lh "$CLIENT_CONFIGS_DIR" 2>/dev/null | tail -n +2 | awk '{print "  - " $9 " (" $5 ")"}' || true
    else
        echo "  - client-vless-reality.json (JSON конфигурация)"
        echo "  - client-vless-reality.txt (Текстовая конфигурация)"
        echo "  - client-qr.png (QR-код для мобильных)"
        echo "  - client-link.txt (VLESS ссылка)"
    fi
    echo ""
    echo -e "${YELLOW}Проверка работы:${NC}"
    echo "  1. Скопируйте конфиги на локальную машину"
    echo "  2. Импортируйте client-vless-reality.json в клиент (v2rayN, v2rayNG и т.д.)"
    echo "  3. Подключитесь к VPN"
    echo "  4. Проверьте IP: https://www.whatismyip.com"
    echo ""
    echo -e "${YELLOW}Управление сервисом:${NC}"
    echo "  sudo systemctl status xray   # Статус"
    echo "  sudo systemctl restart xray  # Перезапуск"
    echo "  sudo journalctl -u xray -f    # Логи в реальном времени"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Обработка ошибок
trap 'error "Скрипт прерван на строке $LINENO. Проверьте вывод выше."' ERR

# Запуск
main "$@"

