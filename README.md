# Xray-core REALITY VPN Setup

Полное руководство по настройке VPN сервера на базе Xray-core с протоколом VLESS + REALITY.

## Что такое Xray-core?

Xray-core - это мощный инструмент для создания VPN/прокси сервисов, форк v2ray-core с улучшениями. Поддерживает современные протоколы обхода блокировок, включая:

- **VLESS** - легковесный протокол без шифрования (шифрование на уровне TLS)
- **REALITY** - технология маскировки трафика под обычный HTTPS-сайт
- **XTLS** - улучшенный TLS для лучшей производительности

## Преимущества REALITY

- ✅ Трафик выглядит как обычный HTTPS-запрос
- ✅ Нет необходимости в собственном домене и SSL-сертификате
- ✅ Высокая производительность
- ✅ Сложность обнаружения для DPI (Deep Packet Inspection) систем
- ✅ Маскировка под реальные популярные сайты (Microsoft, Apple, GitHub и др.)

## Требования

- Виртуальная машина с Linux:
  - ✅ **Ubuntu 24.04 LTS** (рекомендуется, полностью протестировано)
  - ✅ Ubuntu 22.04 LTS
  - ✅ Ubuntu 20.04 LTS
  - ✅ Debian 11+
  - ✅ CentOS 8+
- Права root/sudo
- Минимум 512MB RAM (рекомендуется 1GB+)
- Порт 443 должен быть свободен
- Доступ в интернет

> **Примечания**: 
> - Для Ubuntu 24 см. [UBUNTU24.md](UBUNTU24.md)
> - **Для VMware** см. [vmware-setup.md](vmware-setup.md) - важные особенности виртуализации

## Быстрая установка

### 🚀 Автоматическая установка (рекомендуется)

Самый простой способ - использовать главный скрипт, который выполнит все шаги автоматически:

**Шаг 1: Копирование скриптов на сервер**

С локальной машины скопируйте скрипты на виртуальную машину:

```bash
# Вариант 1: Копирование всего репозитория (если клонирован локально)
scp -r /path/to/xray-config root@<VM-IP>:~/

# Вариант 2: Копирование только необходимых файлов
scp setup-xray.sh root@<VM-IP>:~/
scp -r scripts/ root@<VM-IP>:~/
```

Замените `<VM-IP>` на IP адрес вашей виртуальной машины, например:
```bash
scp setup-xray.sh root@127.0.0.1:~/
scp -r scripts/ root@127.0.0.1:~/
```

**Шаг 2: Запуск установки на сервере**

```bash
# Подключитесь к серверу
ssh root@<VM-IP>

# Перейдите в директорию со скриптами
cd ~/xray-config  # если скопировали весь репозиторий
# или оставайтесь в ~/ если скопировали только файлы

# Сделайте скрипт исполняемым
chmod +x setup-xray.sh

# Запустите автоматическую установку (требуются права root)
sudo ./setup-xray.sh
```

Скрипт автоматически:
- ✅ Установит Xray-core и все зависимости
- ✅ Настроит firewall
- ✅ Сгенерирует UUID и REALITY ключи
- ✅ Создаст конфигурации сервера и клиентов
- ✅ Установит и запустит сервис
- ✅ Выведет готовую команду для копирования конфигов на локальную машину

После завершения скрипт выведет команду вида:
```bash
scp root@127.0.0.1:~/client-configs/* ./client-configs
```

---

### Ручная установка (пошагово)

Если вы предпочитаете выполнять шаги вручную:

### Шаг 1: Подготовка сервера

Подключитесь к вашей виртуальной машине по SSH:

```bash
ssh root@your-server-ip
```

### Шаг 2: Установка Xray-core

Скачайте и запустите скрипт установки:

```bash
# Скачайте скрипт установки
wget https://raw.githubusercontent.com/your-repo/ovpn/main/server-setup.sh

# Сделайте его исполняемым
chmod +x server-setup.sh

# Запустите установку (требуются права root)
sudo ./server-setup.sh
```

Скрипт автоматически:
- Определит вашу ОС
- Установит необходимые зависимости
- Установит Xray-core через официальный репозиторий
- Настроит firewall
- Создаст необходимые директории

### Шаг 3: Генерация конфигурации

Скачайте и запустите скрипт генерации конфигурации:

```bash
# Скачайте скрипт генерации
wget https://raw.githubusercontent.com/your-repo/ovpn/main/generate-config.sh

# Сделайте его исполняемым
chmod +x generate-config.sh

# Запустите генерацию
./generate-config.sh
```

Скрипт:
- Сгенерирует UUID для аутентификации
- Создаст REALITY ключи (приватный и публичный)
- Определит IP адрес сервера
- Предложит выбрать целевой сайт для маскировки
- Создаст конфигурацию сервера (`config.json`)
- Создаст клиентские конфигурации в папке `client-configs/`

### Шаг 4: Установка конфигурации

Скопируйте сгенерированную конфигурацию:

```bash
# Проверьте конфигурацию перед установкой
xray -test -config config.json

# Скопируйте конфигурацию сервера
sudo cp config.json /usr/local/etc/xray/config.json

# Установите правильные права доступа
sudo chown nobody:nogroup /usr/local/etc/xray/config.json
sudo chmod 644 /usr/local/etc/xray/config.json

# Скопируйте systemd service файл (если его нет)
sudo cp xray.service /etc/systemd/system/xray.service

# Перезагрузите systemd
sudo systemctl daemon-reload
```

### Шаг 5: Запуск сервиса

```bash
# Запустите Xray
sudo systemctl start xray

# Включите автозапуск
sudo systemctl enable xray

# Проверьте статус
sudo systemctl status xray
```

Если все настроено правильно, вы увидите `active (running)`.

### Шаг 6: Получение клиентских конфигураций

Клиентские конфигурации находятся в папке `client-configs/`:

- `client-vless-reality.json` - JSON конфигурация для v2rayN, v2rayA и других клиентов
- `client-vless-reality.txt` - Текстовая конфигурация с параметрами
- `client-qr.png` - QR-код для мобильных клиентов
- `client-link.txt` - VLESS ссылка для импорта

Скачайте эти файлы на ваш локальный компьютер:

```bash
# С помощью SCP (с вашего локального компьютера)
scp root@your-server-ip:/root/client-configs/* ./
```

## Настройка клиентов

### Windows

1. Скачайте [v2rayN](https://github.com/2dust/v2rayN/releases)
2. Запустите v2rayN
3. Импортируйте конфигурацию:
   - Нажмите на иконку сервера в трее
   - Выберите "Import from JSON file"
   - Выберите файл `client-vless-reality.json`
4. Выберите сервер и нажмите "Activate system proxy"

### macOS

1. Скачайте [v2rayU](https://github.com/yanue/V2rayU/releases) или [OneXray](https://github.com/xyuanmu/OneXray)
2. Импортируйте `client-vless-reality.json`
3. Включите прокси

### Android

1. Установите [v2rayNG](https://github.com/2dust/v2rayNG/releases) из Google Play или GitHub
2. Откройте приложение
3. Нажмите на "+" для добавления сервера
4. Выберите "Scan QR code" и отсканируйте `client-qr.png`
5. Или импортируйте JSON файл
6. Нажмите на сервер для подключения

### iOS

1. Установите [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) или [Loon](https://apps.apple.com/app/loon/id1373562727) из App Store
2. Откройте приложение
3. Добавьте сервер через QR-код или импорт конфигурации
4. Включите VPN

### Linux

1. Установите [v2rayA](https://github.com/v2rayA/v2rayA):
```bash
# Ubuntu/Debian
wget -qO - https://apt.v2raya.mzz.pub/key/public-key.asc | sudo apt-key add -
echo "deb https://apt.v2raya.mzz.pub/ v2raya main" | sudo tee /etc/apt/sources.list.d/v2raya.list
sudo apt update
sudo apt install v2raya
sudo systemctl start v2raya
sudo systemctl enable v2raya
```

2. Откройте веб-интерфейс: http://localhost:2017
3. Импортируйте `client-vless-reality.json`

## Управление сервисом

```bash
# Запуск
sudo systemctl start xray

# Остановка
sudo systemctl stop xray

# Перезапуск
sudo systemctl restart xray

# Статус
sudo systemctl status xray

# Просмотр логов
sudo journalctl -u xray -f

# Просмотр последних логов
sudo journalctl -u xray -n 50
```

## Проверка работоспособности

### На сервере

```bash
# Проверка, что Xray слушает порт 443
sudo netstat -tlnp | grep 443
# или
sudo ss -tlnp | grep 443

# Проверка логов
sudo journalctl -u xray -n 20
```

### На клиенте

1. Подключитесь к VPN
2. Откройте браузер и перейдите на https://www.google.com
3. Проверьте ваш IP: https://www.whatismyip.com
4. Должен отображаться IP адрес вашего сервера

## Безопасность

### Рекомендации

1. **Firewall**: Убедитесь, что открыт только порт 443
   ```bash
   # UFW
   sudo ufw allow 443/tcp
   sudo ufw deny 22  # Закройте SSH, если не нужен
   
   # Firewalld
   sudo firewall-cmd --permanent --add-port=443/tcp
   sudo firewall-cmd --reload
   ```

2. **SSH**: Используйте ключи вместо паролей
   ```bash
   # Отключите вход по паролю
   sudo nano /etc/ssh/sshd_config
   # Установите: PasswordAuthentication no
   sudo systemctl restart sshd
   ```

3. **Обновления**: Регулярно обновляйте систему
   ```bash
   # Ubuntu/Debian
   sudo apt update && sudo apt upgrade -y
   
   # CentOS/RHEL
   sudo yum update -y
   ```

4. **Fail2ban**: Установите для защиты от брутфорса
   ```bash
   sudo apt install fail2ban  # Ubuntu/Debian
   sudo yum install fail2ban   # CentOS/RHEL
   ```

5. **UUID**: Храните UUID в безопасности, не публикуйте его

## Устранение неполадок

### Потеря SSH доступа после установки

Если после запуска `server-setup.sh` вы потеряли доступ по SSH:

**Вариант 1: Через консоль виртуальной машины (VMware)**
1. Подключитесь к VM через консоль VMware
2. Запустите скрипт восстановления:
   ```bash
   sudo ./fix-ssh.sh
   ```

**Вариант 2: Вручную через консоль VM**
```bash
# Для UFW
sudo ufw allow 22/tcp
sudo ufw reload

# Или временно отключите firewall
sudo ufw disable
```

**Вариант 3: Используйте обновленный скрипт**
Новая версия `server-setup.sh` автоматически разрешает SSH порт перед включением firewall.

### Ошибка: invalid character '\x1b' in string literal

Эта ошибка означает, что в config.json попали ANSI escape-последовательности (цвета). Исправьте:

```bash
# Используйте скрипт для исправления
./fix-config.sh config.json

# Или вручную удалите escape-последовательности
sed -i 's/\x1b\[[0-9;]*m//g' config.json
```

### Сервис не запускается

Если вы видите ошибку `Failed to start: main: failed to load config files`, выполните:

```bash
# Используйте автоматический скрипт исправления
sudo ./fix-xray.sh
```

Скрипт автоматически:
- Проверит конфигурацию на ошибки
- Исправит права доступа к файлам
- Обновит systemd service файл
- Перезапустит сервис

### Ручное исправление

Если автоматический скрипт не помог:

```bash
# 1. Проверьте конфигурацию на ошибки
sudo /usr/local/bin/xray -test -config /usr/local/etc/xray/config.json

# 2. Исправьте права доступа
sudo chown nobody:nogroup /usr/local/etc/xray/config.json
sudo chmod 644 /usr/local/etc/xray/config.json

# 3. Проверьте логи
sudo journalctl -u xray -n 50

# 4. Перезапустите сервис
sudo systemctl daemon-reload
sudo systemctl restart xray
```

### Порт 443 занят

```bash
# Проверьте, что использует порт 443
sudo lsof -i :443
# или
sudo netstat -tlnp | grep 443

# Остановите конфликтующий сервис (например, nginx, apache)
sudo systemctl stop nginx
```

### Ошибка: invalid "privateKey"

Эта ошибка означает, что приватный ключ REALITY невалиден. Для REALITY нужны правильные X25519 ключи.

**Решение:**

1. **Используйте скрипт для генерации ключей:**
   ```bash
   ./generate-keys.sh
   ```

2. **Или сгенерируйте вручную через xray:**
   ```bash
   xray x25519
   ```
   Скопируйте `Private key` и `Public key` из вывода.

3. **Отредактируйте config.json:**
   ```bash
   sudo nano /usr/local/etc/xray/config.json
   ```
   Замените значения `privateKey` и `publicKey` в секции `realitySettings`.

4. **Перезапустите сервис:**
   ```bash
   sudo systemctl restart xray
   sudo systemctl status xray
   ```

### Клиент не может подключиться

1. Проверьте, что firewall разрешает соединения на порт 443
2. Убедитесь, что UUID совпадает в серверной и клиентской конфигурациях
3. Проверьте, что REALITY ключи совпадают
4. Убедитесь, что серверное имя (serverName) совпадает
5. Проверьте логи на сервере: `sudo journalctl -u xray -f`

### Медленное соединение

1. Выберите сервер ближе к вашему местоположению
2. Попробуйте другой целевой сайт для REALITY
3. Проверьте нагрузку на сервер: `htop` или `top`

## Добавление дополнительных клиентов

Для добавления новых клиентов отредактируйте `/usr/local/etc/xray/config.json`:

```json
"clients": [
  {
    "id": "existing-uuid",
    "flow": "xtls-rprx-vision"
  },
  {
    "id": "new-uuid-here",
    "flow": "xtls-rprx-vision"
  }
]
```

Затем перезапустите сервис:
```bash
sudo systemctl restart xray
```

## Обновление Xray-core

```bash
# Обновление через официальный скрипт
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Перезапуск
sudo systemctl restart xray
```

## Полезные ссылки

- [Xray-core GitHub](https://github.com/XTLS/Xray-core)
- [Xray Documentation](https://xtls.github.io/)
- [REALITY Tutorial](https://github.com/XTLS/Xray-core/discussions/1295)
- [v2rayN](https://github.com/2dust/v2rayN)
- [v2rayNG](https://github.com/2dust/v2rayNG)

## Лицензия

Этот проект использует инструменты с лицензией MPL-2.0 (Xray-core).

## Поддержка

Если у вас возникли проблемы:
1. Проверьте раздел "Устранение неполадок"
2. Изучите логи: `sudo journalctl -u xray -n 100`
3. Проверьте документацию Xray-core
4. Создайте issue в репозитории проекта

---

**Важно**: Храните ваши конфигурационные файлы в безопасности. Не публикуйте UUID, REALITY ключи и IP адреса серверов в публичных местах.
