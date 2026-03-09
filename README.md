# hosts-manager

Bash-скрипт для удобного управления `/etc/hosts` из командной строки. Цветной вывод, автоматические бэкапы перед каждым изменением, импорт из файла.

Протестирован на Arch Linux, работает на любом дистрибутиве с `bash` и `sudo`.

---

## Установка

```bash
curl -O https://raw.githubusercontent.com/0xcds4r/hosts-manager/main/hosts-manager.sh
chmod +x hosts-manager.sh
sudo mv hosts-manager.sh /usr/local/bin/hosts
```

или клонировать репозиторий:

```bash
git clone https://github.com/0xcds4r/hosts-manager.git
cd hosts-manager
sudo install -m 755 hosts-manager.sh /usr/local/bin/hosts
```

---

## Использование

```
hosts <команда> [аргументы]
```

### Команды

| Команда | Описание |
|---|---|
| `list` | Показать содержимое `/etc/hosts` с подсветкой |
| `add <IP> <host> [...]` | Добавить запись |
| `remove <hostname\|IP>` | Удалить строки по паттерну (с подтверждением) |
| `block <hostname>` | Заблокировать хост, перенаправив на `0.0.0.0` |
| `disable <hostname\|IP>` | Закомментировать строки (без удаления) |
| `enable <hostname\|IP>` | Раскомментировать строки |
| `search <паттерн>` | Поиск по содержимому файла |
| `import <file.txt>` | Импортировать записи из текстового файла |
| `backup` | Создать резервную копию вручную |
| `restore` | Восстановить из одной из резервных копий |
| `edit` | Открыть файл в `$EDITOR` |
| `flush` | Сбросить DNS-кэш (`resolvectl` или `nscd`) |
| `help` | Справка |

Алиасы: `ls` → `list`, `rm`/`del` → `remove`, `off` → `disable`, `on` → `enable`, `s`/`grep` → `search`, `bak` → `backup`.

---

## Примеры

```bash
# Просмотр
hosts list

# Добавление записей
hosts add 127.0.0.1 myapp.local
hosts add 192.168.1.10 dev.local api.local

# Блокировка рекламы/трекеров
hosts block ads.example.com

# Удаление всех строк с конкретным IP
hosts remove 45.155.204.190

# Временно отключить запись (закомментировать)
hosts disable claude.ai

# Включить обратно
hosts enable claude.ai

# Поиск
hosts search openai

# Импорт из файла
hosts import ~/my-hosts.txt

# DNS кэш
hosts flush

# Восстановление из бэкапа
hosts restore
```

---

## Импорт из файла

Файл должен быть в стандартном формате `/etc/hosts` - по одной записи на строку:

```
# Это комментарий — будет пропущен
45.155.204.190 somesite.com
127.0.0.1      myapp.local dev.local api.local

0.0.0.0 ads.tracker.net
```

Скрипт автоматически:
- пропускает комментарии и пустые строки
- валидирует формат IP-адреса
- пропускает дубли (строки, уже существующие в файле)
- показывает превью перед записью и запрашивает подтверждение

---

## Безопасность

Перед **каждым** изменением файла автоматически создаётся резервная копия в `~/.hosts_backups/` с временной меткой:

```
~/.hosts_backups/
  hosts_20250309_142301.bak
  hosts_20250309_143512.bak
  ...
```

Команды `remove`, `block`, `disable`, `enable`, `import` запрашивают подтверждение или показывают превью перед применением изменений.


