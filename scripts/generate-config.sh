#!/bin/bash

# Xray-core Configuration Generator
# Генерирует конфигурацию сервера и клиентов для VLESS + REALITY

set -Eeuo pipefail
trap 'error "Скрипт прерван на строке $LINENO (код: $?). Проверьте вывод выше."' ERR

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Генерация UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        openssl rand -hex 16 | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/'
    fi
}

# Генерация REALITY ключей (X25519) — через xray x25519 с подробными логами
generate_reality_keys() {
    local private_key=""
    local public_key=""
    local short_id
    local xray_output
    local derive_output
    local python_pub
    local python_exit_code

    info "[ШАГ 1/5] Проверка наличия xray..." >&2
    if ! command -v xray &> /dev/null; then
        error "xray не установлен. Сначала выполните server-setup.sh, затем повторите." >&2
        exit 1
    fi
    info "[ШАГ 1/5] ✓ xray найден" >&2

    info "[ШАГ 2/5] Генерация пары ключей через 'xray x25519'..." >&2
    xray_output=$(xray x25519 2>&1 || true)
    if [ -z "$xray_output" ]; then
        error "Пустой вывод от 'xray x25519'. Проверьте установку Xray." >&2
        exit 1
    fi

    # Парсим приватный ключ (xray использует URL-safe base64 с - и _)
    private_key=$(
        echo "$xray_output" |
            awk 'tolower($0) ~ /private/ {for(i=1;i<=NF;i++) if($i ~ /^[-A-Za-z0-9+\/=\_]{40,44}$/){print $i; exit}}'
    )
    
    if [ -z "$private_key" ]; then
        error "[ШАГ 2/5] ✗ Не удалось извлечь PrivateKey из вывода xray" >&2
        echo "=== Полный вывод xray x25519 ===" >&2
        echo "$xray_output" >&2
        exit 1
    fi
    
    info "[ШАГ 2/5] ✓ PrivateKey получен (длина: ${#private_key}): ${private_key:0:20}..." >&2

    # Пробуем найти PublicKey в выводе (обычно его там нет)
    public_key=$(
        echo "$xray_output" |
            awk 'tolower($0) ~ /public/ {for(i=1;i<=NF;i++) if($i ~ /^[-A-Za-z0-9+\/=\_]{40,44}$/){print $i; exit}}'
    )

    if [ -n "$public_key" ]; then
        info "[ШАГ 3/5] ✓ PublicKey найден в выводе xray (длина: ${#public_key})" >&2
    else
        info "[ШАГ 3/5] PublicKey не найден в выводе xray, пробуем 'xray x25519 -i <private>'..." >&2
        derive_output=$(xray x25519 -i "$private_key" 2>&1 || true)
        public_key=$(
            echo "$derive_output" |
                awk 'tolower($0) ~ /public/ {for(i=1;i<=NF;i++) if($i ~ /^[-A-Za-z0-9+\/=\_]{40,44}$/){print $i; exit}}'
        )
        if [ -n "$public_key" ]; then
            info "[ШАГ 3/5] ✓ PublicKey получен через xray -i (длина: ${#public_key})" >&2
        else
            info "[ШАГ 3/5] PublicKey не найден и через xray -i" >&2
        fi
    fi

    # Вычисляем PublicKey через python3 (cryptography) - ОСНОВНОЙ МЕТОД
    info "[ШАГ 4/5] Вычисление PublicKey через python3 из PrivateKey..." >&2
    if ! command -v python3 &> /dev/null; then
        error "[ШАГ 4/5] ✗ python3 не найден. Установите: sudo apt-get install -y python3 python3-pip" >&2
        exit 1
    fi

    # Проверяем наличие модуля cryptography
    if ! python3 -c "import cryptography.hazmat.primitives.asymmetric.x25519" 2>/dev/null; then
        warn "[ШАГ 4/5] Модуль cryptography не найден. Устанавливаем python3-cryptography..." >&2
        if command -v apt-get &> /dev/null; then
            if [ "$EUID" -eq 0 ]; then
                apt-get install -y python3-cryptography >/dev/null 2>&1 || {
                    error "[ШАГ 4/5] ✗ Не удалось установить python3-cryptography" >&2
                    error "Установите вручную: sudo apt-get install -y python3-cryptography" >&2
                    exit 1
                }
                info "[ШАГ 4/5] ✓ python3-cryptography установлен" >&2
            else
                error "[ШАГ 4/5] ✗ Нужны права root для установки python3-cryptography" >&2
                error "Запустите: sudo apt-get install -y python3-cryptography" >&2
                exit 1
            fi
        else
            error "[ШАГ 4/5] ✗ Не найден apt-get. Установите python3-cryptography вручную" >&2
            exit 1
        fi
    fi

    # Вычисляем PublicKey (xray использует URL-safe base64 без padding)
    python_pub=$(python3 - <<'PY' "$private_key" 2>&1
import base64
import sys
try:
    from cryptography.hazmat.primitives.asymmetric import x25519
    from cryptography.hazmat.primitives import serialization
except ImportError as e:
    print(f"ERROR_IMPORT: {e}", file=sys.stderr)
    sys.exit(2)

pk_b64 = sys.argv[1]
try:
    # Xray использует base64.RawURLEncoding (URL-safe без padding)
    # Пробуем сначала URL-safe, потом обычный base64
    try:
        # Добавляем padding если нужно (может быть 0, 1 или 2 символа =)
        padding = (4 - len(pk_b64) % 4) % 4
        raw = base64.urlsafe_b64decode(pk_b64 + '=' * padding)
    except:
        raw = base64.b64decode(pk_b64)
    
    if len(raw) != 32:
        print(f"ERROR_LENGTH: expected 32 bytes, got {len(raw)}", file=sys.stderr)
        sys.exit(1)
    priv = x25519.X25519PrivateKey.from_private_bytes(raw)
    pub_key = priv.public_key()
    # Используем Raw encoding для получения 32 байт публичного ключа
    pub_bytes = pub_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw
    )
    # Выводим в том же формате, что и xray (URL-safe без padding)
    print(base64.urlsafe_b64encode(pub_bytes).decode('ascii').rstrip('='))
except Exception as e:
    print(f"ERROR_COMPUTE: {e}", file=sys.stderr)
    sys.exit(1)
PY
)
    python_exit_code=$?

    if [ $python_exit_code -eq 0 ] && [ -n "$python_pub" ] && [ ${#python_pub} -ge 40 ]; then
        public_key="$python_pub"
        info "[ШАГ 4/5] ✓ PublicKey вычислен через python3 (длина: ${#public_key}): ${public_key:0:20}..." >&2
    else
        error "[ШАГ 4/5] ✗ Не удалось вычислить PublicKey через python3" >&2
        if [ -n "$python_pub" ]; then
            echo "Вывод python3:" >&2
            echo "$python_pub" >&2
        fi
        exit 1
    fi

    # Валидация ключей (xray использует URL-safe base64 с - и _)
    info "[ШАГ 5/5] Валидация ключей..." >&2
    # Дефис должен быть в начале или конце класса символов, иначе интерпретируется как диапазон
    if ! echo "$private_key" | grep -Eq '^[-A-Za-z0-9+\/=\_]{43}=?$'; then
        error "[ШАГ 5/5] ✗ Некорректный формат PrivateKey (ожидается base64, 43-44 символа)" >&2
        error "PrivateKey: $private_key (длина: ${#private_key})" >&2
        exit 1
    fi
    if ! echo "$public_key" | grep -Eq '^[-A-Za-z0-9+\/=\_]{43}=?$'; then
        error "[ШАГ 5/5] ✗ Некорректный формат PublicKey (ожидается base64, 43-44 символа)" >&2
        error "PublicKey: $public_key (длина: ${#public_key})" >&2
        exit 1
    fi
    info "[ШАГ 5/5] ✓ Ключи валидны" >&2

    # Генерация shortId (8 hex символов)
    short_id=$(openssl rand -hex 8)
    info "✓ ShortID сгенерирован: $short_id" >&2

    echo "${private_key}|${public_key}|${short_id}"
}

# Получение IP адреса сервера
get_server_ip() {
    local server_ip
    
    if command -v curl &> /dev/null; then
        server_ip=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || echo "")
    elif command -v wget &> /dev/null; then
        server_ip=$(wget -qO- https://api.ipify.org 2>/dev/null || wget -qO- https://ifconfig.me 2>/dev/null || echo "")
    fi
    
    if [ -z "$server_ip" ]; then
        warn "Не удалось автоматически определить IP. Введите IP адрес сервера:"
        read -r server_ip
    fi
    
    if [ -z "$server_ip" ]; then
        error "Не удалось определить IP адрес сервера"
        exit 1
    fi
    
    echo "$server_ip"
}

# Выбор целевого сайта для REALITY (российские сайты)
select_target_site() {
    local choice
    local target_site
    
    # Выводим в stderr, чтобы не попало в stdout
    info "Выберите целевой сайт для REALITY маскировки:" >&2
    echo "  1. yandex.ru:443" >&2
    echo "  2. mail.ru:443" >&2
    echo "  3. vk.com:443" >&2
    echo "  4. ok.ru:443" >&2
    echo "  5. rutube.ru:443" >&2
    echo "  6. ria.ru:443" >&2
    echo "  7. lenta.ru:443" >&2
    
    read -p "Введите номер (1-7, по умолчанию 1): " choice >&2
    choice=${choice:-1}
    
    if [ "$choice" = "1" ]; then
        target_site="yandex.ru|443"
    elif [ "$choice" = "2" ]; then
        target_site="mail.ru|443"
    elif [ "$choice" = "3" ]; then
        target_site="vk.com|443"
    elif [ "$choice" = "4" ]; then
        target_site="ok.ru|443"
    elif [ "$choice" = "5" ]; then
        target_site="rutube.ru|443"
    elif [ "$choice" = "6" ]; then
        target_site="ria.ru|443"
    elif [ "$choice" = "7" ]; then
        target_site="lenta.ru|443"
    else
        target_site="yandex.ru|443"
    fi
    
    # Выводим только результат в stdout
    echo "$target_site"
}

# Создание конфигурации сервера
create_server_config() {
    local uuid=$1
    local private_key=$2
    local short_id=$3
    local target_domain=$4
    local target_port=$5
    
    info "Создание конфигурации сервера..."
    
    # Создаем JSON через jq если доступен, иначе через шаблон
    if command -v jq &> /dev/null; then
        jq -n \
            --arg uuid "$uuid" \
            --arg private_key "$private_key" \
            --arg short_id "$short_id" \
            --arg target_domain "$target_domain" \
            --arg target_port "$target_port" \
            '{
                log: { loglevel: "warning" },
                inbounds: [{
                    listen: "0.0.0.0",
                    port: 443,
                    protocol: "vless",
                    settings: {
                        clients: [{
                            id: $uuid,
                            flow: "xtls-rprx-vision"
                        }],
                        decryption: "none",
                        fallbacks: [{ dest: 8080 }]
                    },
                    streamSettings: {
                        network: "tcp",
                        security: "reality",
                        realitySettings: {
                            show: false,
                            dest: ($target_domain + ":" + $target_port),
                            target: ($target_domain + ":" + $target_port),
                            xver: 0,
                            serverNames: [$target_domain],
                            privateKey: $private_key,
                            maxTimeDiff: 0,
                            shortIds: [$short_id]
                        },
                        tcpSettings: {
                            acceptProxyProtocol: false,
                            header: { type: "none" }
                        }
                    },
                    sniffing: {
                        enabled: true,
                        destOverride: ["http", "tls"]
                    }
                }],
                outbounds: [
                    { protocol: "freedom", settings: {} },
                    { protocol: "blackhole", settings: {}, tag: "blocked" }
                ],
                routing: {
                    rules: [{
                        type: "field",
                        ip: ["geoip:private"],
                        outboundTag: "blocked"
                    }]
                }
            }' > config.json
    else
        # Fallback: используем шаблон с безопасной заменой
        local tmp_file=$(mktemp)
        cat > "$tmp_file" <<'TEMPLATE_EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "UUID_PLACEHOLDER",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 8080
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "DOMAIN_PLACEHOLDER:PORT_PLACEHOLDER",
          "target": "DOMAIN_PLACEHOLDER:PORT_PLACEHOLDER",
          "xver": 0,
          "serverNames": [
            "DOMAIN_PLACEHOLDER"
          ],
          "privateKey": "PRIVATE_KEY_PLACEHOLDER",
          "maxTimeDiff": 0,
          "shortIds": [
            "SHORT_ID_PLACEHOLDER"
          ]
        },
        "tcpSettings": {
          "acceptProxyProtocol": false,
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
TEMPLATE_EOF
        
        # Безопасная замена через awk (избегаем проблем с спецсимволами в sed)
        local tmp_replace=$(mktemp)
        awk -v uuid="$uuid" \
            -v private_key="$private_key" \
            -v short_id="$short_id" \
            -v target_domain="$target_domain" \
            -v target_port="$target_port" \
            '{
                gsub("UUID_PLACEHOLDER", uuid);
                gsub("PRIVATE_KEY_PLACEHOLDER", private_key);
                gsub("SHORT_ID_PLACEHOLDER", short_id);
                gsub("DOMAIN_PLACEHOLDER", target_domain);
                gsub("PORT_PLACEHOLDER", target_port);
                print
            }' "$tmp_file" > "$tmp_replace"
        mv "$tmp_replace" config.json
        rm -f "$tmp_file"
    fi
    
    # Валидация JSON
    if command -v jq &> /dev/null; then
        if jq empty config.json 2>/dev/null; then
            info "Конфигурация сервера сохранена в config.json (валидирована)"
        else
            error "Ошибка валидации JSON конфигурации"
            jq empty config.json 2>&1 || true
            exit 1
        fi
    else
        info "Конфигурация сервера сохранена в config.json"
    fi
}

# Создание клиентской конфигурации (JSON)
create_client_json() {
    local uuid=$1
    local public_key=$2
    local short_id=$3
    local server_ip=$4
    local target_domain=$5
    
    info "Создание клиентской конфигурации (JSON)..."
    
    mkdir -p client-configs
    
    if command -v jq &> /dev/null; then
        jq -n \
            --arg uuid "$uuid" \
            --arg public_key "$public_key" \
            --arg short_id "$short_id" \
            --arg server_ip "$server_ip" \
            --arg target_domain "$target_domain" \
            '{
                log: { loglevel: "warning" },
                inbounds: [
                    {
                        port: 10808,
                        protocol: "socks",
                        settings: { auth: "noauth", udp: true }
                    },
                    {
                        port: 10809,
                        protocol: "http",
                        settings: {}
                    }
                ],
                outbounds: [{
                    protocol: "vless",
                    settings: {
                        vnext: [{
                            address: $server_ip,
                            port: 443,
                            users: [{
                                id: $uuid,
                                encryption: "none",
                                flow: "xtls-rprx-vision"
                            }]
                        }]
                    },
                    streamSettings: {
                        network: "tcp",
                        security: "reality",
                        realitySettings: {
                            show: false,
                            fingerprint: "chrome",
                            serverName: $target_domain,
                            publicKey: $public_key,
                            shortId: $short_id,
                            spiderX: "/"
                        }
                    }
                }]
            }' > client-configs/client-vless-reality.json
    else
        # Fallback: шаблон
        cat > client-configs/client-vless-reality.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    },
    {
      "port": 10809,
      "protocol": "http",
      "settings": {}
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${server_ip}",
            "port": 443,
            "users": [
              {
                "id": "${uuid}",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "fingerprint": "chrome",
          "serverName": "${target_domain}",
          "publicKey": "${public_key}",
          "shortId": "${short_id}",
          "spiderX": "/"
        }
      }
    }
  ]
}
EOF
    fi
    
    info "Клиентская конфигурация (JSON) сохранена в client-configs/client-vless-reality.json"
}

# Создание текстовой конфигурации
create_client_text() {
    local uuid=$1
    local public_key=$2
    local short_id=$3
    local server_ip=$4
    local target_domain=$5
    
    info "Создание текстовой конфигурации..."
    
    cat > client-configs/client-vless-reality.txt <<EOF
========================================
VLESS + REALITY Configuration
========================================

Address: ${server_ip}
Port: 443
UUID: ${uuid}
Flow: xtls-rprx-vision
Encryption: none
Network: tcp
Security: reality
Reality Settings:
  Server Name: ${target_domain}
  Public Key: ${public_key}
  Short ID: ${short_id}
  Fingerprint: chrome

========================================
Для v2rayN:
1. Скопируйте client-vless-reality.json
2. Импортируйте в v2rayN через "Import from JSON file"
3. Или создайте вручную с параметрами выше

========================================
EOF
    
    info "Текстовая конфигурация сохранена в client-configs/client-vless-reality.txt"
}

# Создание QR-кода
create_qr_code() {
    local uuid=$1
    local public_key=$2
    local short_id=$3
    local server_ip=$4
    local target_domain=$5
    
    if ! command -v qrencode &> /dev/null; then
        warn "qrencode не установлен. Пропускаем создание QR-кода"
        return
    fi
    
    info "Создание QR-кода..."
    
    local vless_link="vless://${uuid}@${server_ip}:443?encryption=none&flow=xtls-rprx-vision&security=reality&pbk=${public_key}&fp=chrome&sni=${target_domain}&sid=${short_id}&type=tcp#Xray-REALITY"
    
    echo "$vless_link" | qrencode -o client-configs/client-qr.png -s 10 2>/dev/null || warn "Не удалось создать QR-код"
    echo "$vless_link" > client-configs/client-link.txt
    
    info "QR-код сохранен в client-configs/client-qr.png"
    info "Ссылка сохранена в client-configs/client-link.txt"
}

# Основная функция
main() {
    info "Генерация конфигурации Xray-core с REALITY..."
    
    # Генерация параметров
    UUID=$(generate_uuid)
    info "Сгенерирован UUID: $UUID"
    
    info "Генерация REALITY ключей..."
    KEYS=$(generate_reality_keys)
    PRIVATE_KEY=$(echo "$KEYS" | cut -d'|' -f1)
    PUBLIC_KEY=$(echo "$KEYS" | cut -d'|' -f2)
    SHORT_ID=$(echo "$KEYS" | cut -d'|' -f3)
    
    info "REALITY Public Key: $PUBLIC_KEY"
    info "REALITY Short ID: $SHORT_ID"
    
    SERVER_IP=$(get_server_ip)
    info "IP адрес сервера: $SERVER_IP"
    
    TARGET_INFO=$(select_target_site)
    TARGET_DOMAIN=$(echo "$TARGET_INFO" | cut -d'|' -f1)
    TARGET_PORT=$(echo "$TARGET_INFO" | cut -d'|' -f2)
    
    info "Выбран сайт для маскировки: $TARGET_DOMAIN:$TARGET_PORT"
    
    # Создание конфигураций
    create_server_config "$UUID" "$PRIVATE_KEY" "$SHORT_ID" "$TARGET_DOMAIN" "$TARGET_PORT"
    create_client_json "$UUID" "$PUBLIC_KEY" "$SHORT_ID" "$SERVER_IP" "$TARGET_DOMAIN"
    create_client_text "$UUID" "$PUBLIC_KEY" "$SHORT_ID" "$SERVER_IP" "$TARGET_DOMAIN"
    create_qr_code "$UUID" "$PUBLIC_KEY" "$SHORT_ID" "$SERVER_IP" "$TARGET_DOMAIN"
    
    info ""
    info "=========================================="
    info "Конфигурация успешно создана!"
    info "=========================================="
    info ""
    info "Серверная конфигурация: config.json"
    info "Клиентские конфигурации: client-configs/"
    info ""
    info "Следующие шаги:"
    info "1. Проверьте конфигурацию: xray -test -config config.json"
    info "2. Скопируйте config.json в /usr/local/etc/xray/config.json"
    info "3. Установите права: sudo chown nobody:nogroup /usr/local/etc/xray/config.json"
    info "4. Запустите сервис: sudo systemctl start xray"
    info "5. Включите автозапуск: sudo systemctl enable xray"
    info "6. Проверьте статус: sudo systemctl status xray"
    info ""
    
    # Проверка конфигурации, если xray установлен
    if command -v xray &> /dev/null; then
        info "Проверка конфигурации..."
        if xray -test -config config.json &>/dev/null; then
            info "Конфигурация валидна!"
        else
            warn "Обнаружены ошибки в конфигурации. Запустите: xray -test -config config.json"
        fi
    fi
}

# Запуск
main "$@"
