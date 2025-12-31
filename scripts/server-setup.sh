#!/bin/bash

# Xray-core Server Setup Script
# Устанавливает Xray-core на Linux сервер

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        error "Пожалуйста, запустите скрипт с правами root (sudo)"
        exit 1
    fi
}

# Определение ОС
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        error "Не удалось определить операционную систему"
        exit 1
    fi
    
    info "Обнаружена ОС: $OS $VERSION"
}

# Установка зависимостей
install_dependencies() {
    info "Установка зависимостей..."
    
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update
        # libcap2-bin нужен для setcap (важно для VMware и работы с портом 443)
        apt-get install -y curl wget unzip jq qrencode libcap2-bin
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
        if command -v dnf &> /dev/null; then
            dnf install -y curl wget unzip jq qrencode libcap
        else
            yum install -y curl wget unzip jq qrencode libcap
        fi
    else
        warn "Неизвестная ОС. Убедитесь, что установлены: curl, wget, unzip, jq, qrencode, libcap2-bin (для setcap)"
    fi
}

# Установка Xray-core
install_xray() {
    info "Установка Xray-core..."
    
    # Скачивание и установка через официальный скрипт
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    
    # Проверка установки
    if command -v xray &> /dev/null; then
        XRAY_VERSION=$(xray version | head -n 1)
        info "Xray-core успешно установлен: $XRAY_VERSION"
        
        # Установка capabilities для работы с портом 443 без root (важно для VMware)
        info "Установка capabilities для работы с привилегированными портами..."
        if command -v setcap &> /dev/null; then
            setcap cap_net_bind_service,cap_net_admin+ep /usr/local/bin/xray
            if getcap /usr/local/bin/xray | grep -q "cap_net_bind_service"; then
                info "Capabilities успешно установлены"
            else
                warn "Не удалось установить capabilities. Xray может не работать с портом 443"
            fi
        else
            warn "setcap не найден. Убедитесь, что установлен пакет libcap2-bin"
        fi
    else
        error "Ошибка установки Xray-core"
        exit 1
    fi
}

# Настройка firewall
setup_firewall() {
    info "Настройка firewall..."
    
    # Проверка наличия ufw (Ubuntu/Debian)
    if command -v ufw &> /dev/null; then
        info "Настройка UFW..."
        # ВАЖНО: Сначала разрешаем SSH, чтобы не потерять доступ
        ufw allow 22/tcp comment 'SSH'
        ufw allow 443/tcp comment 'Xray HTTPS'
        ufw allow 443/udp comment 'Xray HTTPS UDP'
        # Включаем firewall только если он еще не включен
        if ! ufw status | grep -q "Status: active"; then
            info "Включение UFW (SSH порт 22 уже разрешен)..."
            ufw --force enable
        else
            info "UFW уже активен"
        fi
    # Проверка наличия firewalld (CentOS/RHEL)
    elif command -v firewall-cmd &> /dev/null; then
        info "Настройка firewalld..."
        # ВАЖНО: Сначала разрешаем SSH
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --permanent --add-port=443/udp
        firewall-cmd --reload
    # Проверка наличия iptables
    elif command -v iptables &> /dev/null; then
        warn "Настройте iptables вручную для порта 443"
    else
        warn "Firewall не обнаружен. Настройте правила вручную для порта 443"
    fi
}

# Создание директорий
create_directories() {
    info "Создание необходимых директорий..."
    mkdir -p /usr/local/etc/xray
    mkdir -p /var/log/xray
    mkdir -p /usr/local/share/xray
}

# Настройка systemd service
setup_service() {
    info "Настройка systemd service..."
    
    # Проверка существования сервиса
    if [ -f /etc/systemd/system/xray.service ]; then
        info "Сервис xray.service уже существует"
    else
        warn "Сервис xray.service не найден. Он будет создан при установке Xray-core"
    fi
    
    # Перезагрузка systemd
    systemctl daemon-reload
}

# Основная функция
main() {
    info "Начало установки Xray-core..."
    
    check_root
    detect_os
    install_dependencies
    create_directories
    install_xray
    setup_firewall
    setup_service
    
    info "Установка завершена!"
    info "Следующий шаг: запустите generate-config.sh для создания конфигурации"
}

# Запуск
main "$@"

