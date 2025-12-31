# Быстрый старт (Ubuntu 24 на VMware)

Минимальный порядок действий: сперва сервер (ВМ), затем клиент.

## Сервер (внутри ВМ)

### 🚀 Автоматическая установка (рекомендуется)

**0) Копирование скриптов на ВМ (с локальной машины)**

```bash
# Вариант 1: Копирование всего репозитория
scp -r /path/to/xray-config root@<VM-IP>:~/

# Вариант 2: Копирование только необходимых файлов
scp setup-xray.sh root@<VM-IP>:~/
scp -r scripts/ root@<VM-IP>:~/
```

Замените `<VM-IP>` на IP адрес вашей ВМ, например:
```bash
scp setup-xray.sh root@127.0.0.1:~/
scp -r scripts/ root@127.0.0.1:~/
```

**1) Запуск установки (внутри ВМ)**

```bash
# Подключитесь к ВМ
ssh root@<VM-IP>

# Если скопировали весь репозиторий
cd ~/xray-config

# Сделайте скрипт исполняемым
chmod +x setup-xray.sh

# Запустите автоматическую установку
sudo ./setup-xray.sh
# Скрипт выполнит все шаги и выведет команду для копирования конфигов
```

После завершения скрипт выведет готовую команду для копирования конфигов, например:
```bash
scp root@127.0.0.1:~/client-configs/* ./client-configs
```

---

### Ручная установка (пошагово)

Если вы предпочитаете выполнять шаги вручную:

```bash
# 0) Подготовка
cd /Users/nikitaershov/ovpn/scripts
chmod +x server-setup.sh generate-config.sh

# 1) Установка Xray + зависимостей
sudo ./server-setup.sh

# 2) Генерация конфигов (UUID, ключи REALITY, client configs)
./generate-config.sh
# Скрипт спросит домен для маскировки (например, www.microsoft.com)

# 3) Проверить и установить серверный конфиг
xray -test -config config.json
sudo cp config.json /usr/local/etc/xray/config.json
sudo chown nobody:nogroup /usr/local/etc/xray/config.json
sudo chmod 644 /usr/local/etc/xray/config.json

# 4) Запуск и автозапуск сервиса
sudo systemctl daemon-reload
sudo systemctl restart xray
sudo systemctl enable xray
sudo systemctl status xray
```

### Забрать клиентские файлы
После успешной установки скрипт выведет готовую команду для копирования конфигов. Или выполните вручную:

```bash
# Создайте папку для конфигов (если нужно)
mkdir -p ./client-configs

# Скопируйте конфиги с ВМ
scp root@<VM-IP>:/root/client-configs/* ./client-configs/
```

`<VM-IP>` — внешний IP ВМ (при NAT убедитесь, что порт 443 проброшен).

## Клиент

Используйте любой из вариантов:

- Windows: поставить [v2rayN](https://github.com/2dust/v2rayN/releases), импортировать `client-vless-reality.json`, включить системный прокси.
- Android: [v2rayNG](https://github.com/2dust/v2rayNG/releases), отсканировать `client-qr.png`, подключиться.
- iOS: Shadowrocket или Loon, импорт через QR, включить VPN.
- macOS: [v2rayU](https://github.com/yanue/V2rayU/releases) или OneXray, импорт `client-vless-reality.json`, включить прокси.

## Проверка

Откройте https://www.whatismyip.com — должен быть IP сервера.

## Если что-то пошло не так

- Быстрое исправление: `sudo ./fix-xray.sh`
- Ошибка `invalid character '\x1b' in string literal`: `./fix-config.sh config.json` → заново скопировать в `/usr/local/etc/xray/config.json` → `sudo systemctl restart xray`
- Диагностика VMware/сети: `sudo ./check-vmware.sh`

Дополнительно: раздел “Устранение неполадок” в `README.md`, `vmware-setup.md` (для VMware), `UBUNTU24.md` (если нужна 24.x). 