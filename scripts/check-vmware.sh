#!/bin/bash

# Скрипт диагностики для VMware окружения

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

section "Проверка сетевых интерфейсов"
ip addr show | grep -E "inet |^[0-9]+:"

section "Проверка порта 443"
if sudo lsof -i :443 2>/dev/null | grep -q xray; then
    info "Xray слушает порт 443"
    sudo lsof -i :443
else
    if sudo lsof -i :443 2>/dev/null; then
        warn "Порт 443 занят другим процессом:"
        sudo lsof -i :443
    else
        warn "Порт 443 свободен (Xray может быть не запущен)"
    fi
fi

section "Проверка firewall (UFW)"
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(sudo ufw status | head -n 1)
    if echo "$UFW_STATUS" | grep -q "Status: active"; then
        warn "UFW активен"
        if sudo ufw status | grep -q "443"; then
            info "Порт 443 разрешен в UFW"
            sudo ufw status | grep 443
        else
            error "Порт 443 НЕ разрешен в UFW!"
            echo "Выполните: sudo ufw allow 443/tcp"
        fi
    else
        info "UFW неактивен"
    fi
else
    warn "UFW не установлен"
fi

section "Проверка iptables"
if sudo iptables -L -n 2>/dev/null | grep -q "443"; then
    info "Найдены правила для порта 443 в iptables"
    sudo iptables -L -n | grep 443
else
    warn "Правила для порта 443 не найдены в iptables"
fi

section "Проверка capabilities Xray"
if [ -f /usr/local/bin/xray ]; then
    CAPS=$(sudo getcap /usr/local/bin/xray 2>/dev/null)
    if echo "$CAPS" | grep -q "cap_net_bind_service"; then
        info "Capabilities установлены:"
        echo "$CAPS"
    else
        error "Capabilities НЕ установлены!"
        echo "Выполните: sudo setcap cap_net_bind_service,cap_net_admin+ep /usr/local/bin/xray"
    fi
else
    error "Xray не найден в /usr/local/bin/xray"
fi

section "Проверка статуса Xray service"
if systemctl is-active --quiet xray 2>/dev/null; then
    info "Xray service активен"
    sudo systemctl status xray --no-pager -l | head -n 10
else
    error "Xray service НЕ активен"
    if systemctl is-enabled --quiet xray 2>/dev/null; then
        warn "Service включен, но не запущен. Проверьте логи:"
        sudo journalctl -u xray -n 5 --no-pager
    else
        warn "Service не включен. Выполните: sudo systemctl enable xray"
    fi
fi

section "Проверка конфигурации"
if [ -f /usr/local/etc/xray/config.json ]; then
    info "Конфигурация найдена"
    if command -v xray &> /dev/null; then
        if sudo xray -test -config /usr/local/etc/xray/config.json 2>&1 | grep -q "Configuration OK"; then
            info "Конфигурация валидна"
        else
            error "Ошибки в конфигурации:"
            sudo xray -test -config /usr/local/etc/xray/config.json 2>&1 | tail -n 5
        fi
    fi
    
    # Проверка прав доступа
    CONFIG_OWNER=$(stat -c '%U:%G' /usr/local/etc/xray/config.json 2>/dev/null || stat -f '%Su:%Sg' /usr/local/etc/xray/config.json)
    if echo "$CONFIG_OWNER" | grep -q "nobody"; then
        info "Права доступа корректны: $CONFIG_OWNER"
    else
        warn "Права доступа могут быть неправильными: $CONFIG_OWNER"
        echo "Должно быть: nobody:nogroup или nobody:nobody"
    fi
else
    error "Конфигурация не найдена: /usr/local/etc/xray/config.json"
fi

section "Проверка сетевого подключения"
echo "IP адреса интерфейсов:"
ip -4 addr show | grep "inet " | awk '{print "  " $2}'

echo -e "\nМаршрутизация:"
ip route show | head -n 5

section "Проверка VMware окружения"
# Проверка, что это виртуальная машина
if [ -f /sys/class/dmi/id/product_name ]; then
    PRODUCT=$(cat /sys/class/dmi/id/product_name)
    if echo "$PRODUCT" | grep -qi "vmware\|virtual"; then
        info "Обнаружена VMware виртуальная машина: $PRODUCT"
    else
        info "Система: $PRODUCT"
    fi
fi

# Проверка VMware Tools
if command -v vmware-toolbox-cmd &> /dev/null; then
    info "VMware Tools установлены"
else
    warn "VMware Tools не установлены (рекомендуется для лучшей производительности)"
fi

section "Рекомендации"
echo "Если обнаружены проблемы:"
echo "1. Запустите: sudo ./fix-xray.sh"
echo "2. Проверьте настройки сети в VMware (Bridged/NAT)"
echo "3. Убедитесь, что порт 443 проброшен (если используется NAT)"
echo "4. См. документацию: vmware-setup.md"

