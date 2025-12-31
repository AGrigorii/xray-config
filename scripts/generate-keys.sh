#!/bin/bash

# Скрипт для ручной генерации REALITY ключей
# Используйте этот скрипт если generate-config.sh не может сгенерировать ключи

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info "Генерация REALITY X25519 ключей..."

if command -v xray &> /dev/null; then
    info "Используем xray x25519 для генерации ключей:"
    echo ""
    xray x25519
    echo ""
    info "Скопируйте Private key и Public key из вывода выше"
    info "Используйте их в конфигурации Xray"
else
    warn "xray не найден. Установите xray для правильной генерации ключей."
    warn "Или используйте openssl (менее надежно):"
    echo ""
    
    if openssl genpkey -algorithm x25519 -out /tmp/x25519.pem 2>/dev/null; then
        info "Приватный ключ (base64):"
        openssl pkey -in /tmp/x25519.pem -outform DER 2>/dev/null | tail -c 32 | base64
        echo ""
        info "Публичный ключ (base64):"
        openssl pkey -in /tmp/x25519.pem -pubout -outform DER 2>/dev/null | tail -c 32 | base64
        echo ""
        rm -f /tmp/x25519.pem
    else
        warn "openssl не поддерживает X25519"
        warn "Установите xray для правильной генерации ключей"
    fi
fi

