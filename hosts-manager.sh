#!/usr/bin/env bash

set -euo pipefail

HOSTS_FILE="/etc/hosts"
BACKUP_DIR="${HOME}/.hosts_backups"
COLOR_RESET=$'\033[0m'
COLOR_BOLD=$'\033[1m'
COLOR_RED=$'\033[31m'
COLOR_GREEN=$'\033[32m'
COLOR_YELLOW=$'\033[33m'
COLOR_CYAN=$'\033[36m'
COLOR_DIM=$'\033[2m'

die()  { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2; exit 1; }
info() { echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET}  $*"; }
ok()   { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}    $*"; }
warn() { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET}  $*"; }

require_root() {
    [[ $EUID -eq 0 ]] || command -v sudo &>/dev/null || \
        die "Нужен root или sudo"
}

write_hosts() {
    local tmp
    tmp=$(mktemp)
    cat > "$tmp"
    if [[ $EUID -eq 0 ]]; then
        cp "$tmp" "$HOSTS_FILE"
    else
        sudo cp "$tmp" "$HOSTS_FILE"
    fi
    rm -f "$tmp"
}

backup() {
    mkdir -p "$BACKUP_DIR"
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local dest="${BACKUP_DIR}/hosts_${ts}.bak"
    cp "$HOSTS_FILE" "$dest"
    ok "Резервная копия: $dest"
}

cmd_list() {
    echo -e "\n${COLOR_BOLD}=== ${HOSTS_FILE} ===${COLOR_RESET}\n"
    local n=0
    while IFS= read -r line; do
        ((n++)) || true
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
            echo -e "${COLOR_DIM}${line}${COLOR_RESET}"
        else
            local ip host rest
            read -r ip host rest <<< "$line"
            printf "${COLOR_GREEN}%-20s${COLOR_RESET}  ${COLOR_BOLD}%-30s${COLOR_RESET}  ${COLOR_DIM}%s${COLOR_RESET}\n" \
                "$ip" "$host" "$rest"
        fi
    done < "$HOSTS_FILE"
    echo ""
}

cmd_add() {
    local ip="${1:-}" host="${2:-}"
    [[ -n "$ip" && -n "$host" ]] || die "Использование: add <IP> <hostname> [hostname2 ...]"

    if grep -qP "^${ip}\s.*\b${host}\b" "$HOSTS_FILE" 2>/dev/null; then
        warn "Запись ${ip} → ${host} уже существует"
        return
    fi

    require_root
    backup
    local entry="$*"
    if [[ $EUID -eq 0 ]]; then
        echo "$entry" >> "$HOSTS_FILE"
    else
        echo "$entry" | sudo tee -a "$HOSTS_FILE" >/dev/null
    fi
    ok "Добавлено: $entry"
}

cmd_remove() {
    local pattern="${1:-}"
    [[ -n "$pattern" ]] || die "Использование: remove <hostname|IP>"

    local matches
    matches=$(grep -nP "(?<![#])\b${pattern}\b" "$HOSTS_FILE" || true)
    if [[ -z "$matches" ]]; then
        warn "Совпадений для '${pattern}' не найдено"
        return
    fi

    echo -e "\n${COLOR_YELLOW}Будут удалены строки:${COLOR_RESET}"
    echo "$matches"
    echo ""
    read -rp "Продолжить? [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || { info "Отмена"; return; }

    require_root
    backup
    local new_content
    new_content=$(grep -vP "(?<![#])\b${pattern}\b" "$HOSTS_FILE")
    echo "$new_content" | write_hosts
    ok "Удалено: $pattern"
}

cmd_block() {
    local host="${1:-}"
    [[ -n "$host" ]] || die "Использование: block <hostname>"
    require_root
    backup
    local entry="0.0.0.0 ${host}"
    if grep -qP "^0\.0\.0\.0\s+${host}" "$HOSTS_FILE"; then
        warn "${host} уже заблокирован"
        return
    fi
    if [[ $EUID -eq 0 ]]; then
        echo "$entry" >> "$HOSTS_FILE"
    else
        echo "$entry" | sudo tee -a "$HOSTS_FILE" >/dev/null
    fi
    ok "Заблокирован: $host → 0.0.0.0"
}

cmd_unblock() {
    cmd_remove "^0\\.0\\.0\\.0\\s+${1:-}"
    cmd_remove "${1:-}"
}

cmd_search() {
    local pattern="${1:-}"
    [[ -n "$pattern" ]] || die "Использование: search <паттерн>"
    echo -e "\n${COLOR_BOLD}Поиск: ${pattern}${COLOR_RESET}\n"
    grep --color=always -iP "$pattern" "$HOSTS_FILE" || warn "Ничего не найдено"
    echo ""
}

cmd_disable() {
    local pattern="${1:-}"
    [[ -n "$pattern" ]] || die "Использование: disable <hostname|IP>"
    require_root
    backup
    local new_content
    new_content=$(sed -E "s|^([^#].*\b${pattern}\b.*)|#\1|g" "$HOSTS_FILE")
    echo "$new_content" | write_hosts
    ok "Закомментировано: $pattern"
}

cmd_enable() {
    local pattern="${1:-}"
    [[ -n "$pattern" ]] || die "Использование: enable <hostname|IP>"
    require_root
    backup
    local new_content
    new_content=$(sed -E "s|^#(.*\b${pattern}\b.*)|\1|g" "$HOSTS_FILE")
    echo "$new_content" | write_hosts
    ok "Раскомментировано: $pattern"
}

cmd_backup() {
    backup
}

cmd_restore() {
    mkdir -p "$BACKUP_DIR"
    local backups=("$BACKUP_DIR"/hosts_*.bak)
    if [[ ! -e "${backups[0]}" ]]; then
        warn "Резервных копий не найдено в $BACKUP_DIR"
        return
    fi

    echo -e "\n${COLOR_BOLD}Доступные резервные копии:${COLOR_RESET}\n"
    local i=0
    for f in "${backups[@]}"; do
        echo "  [$i] $(basename "$f")  ($(wc -l < "$f") строк)"
        ((i++)) || true
    done
    echo ""
    read -rp "Выберите номер [0-$((i-1))]: " choice
    local selected="${backups[$choice]:-}"
    [[ -f "$selected" ]] || die "Неверный выбор"

    require_root
    backup
    cat "$selected" | write_hosts
    ok "Восстановлено из: $(basename "$selected")"
}

cmd_edit() {
    require_root
    backup
    local editor="${EDITOR:-nano}"
    if [[ $EUID -eq 0 ]]; then
        "$editor" "$HOSTS_FILE"
    else
        sudo "$editor" "$HOSTS_FILE"
    fi
}

cmd_flush() {
    if command -v resolvectl &>/dev/null; then
        sudo resolvectl flush-caches && ok "DNS кэш сброшен (systemd-resolved)"
    elif command -v nscd &>/dev/null; then
        sudo nscd -i hosts && ok "DNS кэш сброшен (nscd)"
    else
        warn "Не найден resolvectl или nscd — перезапустите сеть вручную"
    fi
}

cmd_import() {
    local file="${1:-}"
    [[ -n "$file" ]] || die "Использование: import <file.txt>"
    [[ -f "$file" ]] || die "Файл не найден: $file"

    local added=0 skipped=0 invalid=0
    local -a new_entries=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line// }" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        local ip
        ip=$(awk '{print $1}' <<< "$line")
        if ! [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$|^::1$|^::$ ]]; then
            warn "Пропущена невалидная строка: $line"
            ((invalid++)) || true
            continue
        fi

        if grep -qF "$line" "$HOSTS_FILE" 2>/dev/null; then
            ((skipped++)) || true
            continue
        fi

        new_entries+=("$line")
        ((added++)) || true
    done < "$file"

    if [[ ${#new_entries[@]} -eq 0 ]]; then
        warn "Нечего импортировать (все строки уже есть или невалидны)"
        info "Пропущено дублей: $skipped  |  Невалидных: $invalid"
        return
    fi

    echo -e "\n${COLOR_BOLD}Будет добавлено ${added} записей:${COLOR_RESET}\n"
    for e in "${new_entries[@]}"; do
        echo -e "  ${COLOR_GREEN}+${COLOR_RESET} $e"
    done
    echo ""
    read -rp "Продолжить? [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || { info "Отмена"; return; }

    require_root
    backup

    for e in "${new_entries[@]}"; do
        if [[ $EUID -eq 0 ]]; then
            echo "$e" >> "$HOSTS_FILE"
        else
            echo "$e" | sudo tee -a "$HOSTS_FILE" >/dev/null
        fi
    done

    ok "Импортировано: $added  |  Пропущено дублей: $skipped  |  Невалидных: $invalid"
}

cmd_help() {
    cat <<EOF

${COLOR_BOLD}hosts-manager${COLOR_RESET} — управление /etc/hosts

${COLOR_CYAN}ИСПОЛЬЗОВАНИЕ:${COLOR_RESET}
  $(basename "$0") <команда> [аргументы]

${COLOR_CYAN}КОМАНДЫ:${COLOR_RESET}
  ${COLOR_GREEN}list${COLOR_RESET}                        Показать содержимое файла
  ${COLOR_GREEN}add${COLOR_RESET}    <IP> <host> [...]    Добавить запись
  ${COLOR_GREEN}remove${COLOR_RESET} <hostname|IP>        Удалить строки по паттерну
  ${COLOR_GREEN}block${COLOR_RESET}  <hostname>           Заблокировать хост (→ 0.0.0.0)
  ${COLOR_GREEN}disable${COLOR_RESET} <hostname|IP>       Закомментировать строки
  ${COLOR_GREEN}enable${COLOR_RESET}  <hostname|IP>       Раскомментировать строки
  ${COLOR_GREEN}search${COLOR_RESET} <паттерн>            Поиск по содержимому
  ${COLOR_GREEN}import${COLOR_RESET} <file.txt>           Импортировать записи из файла
  ${COLOR_GREEN}backup${COLOR_RESET}                      Создать резервную копию
  ${COLOR_GREEN}restore${COLOR_RESET}                     Восстановить из резервной копии
  ${COLOR_GREEN}edit${COLOR_RESET}                        Открыть в \$EDITOR (${EDITOR:-nano})
  ${COLOR_GREEN}flush${COLOR_RESET}                       Сбросить DNS кэш
  ${COLOR_GREEN}help${COLOR_RESET}                        Эта справка

${COLOR_CYAN}ПРИМЕРЫ:${COLOR_RESET}
  $(basename "$0") import /path/to/entries.txt
  $(basename "$0") add 127.0.0.1 myapp.local
  $(basename "$0") block ads.example.com
  $(basename "$0") remove 45.155.204.190
  $(basename "$0") disable claude.ai
  $(basename "$0") search openai
  $(basename "$0") restore

${COLOR_DIM}Бэкапы хранятся в: ${BACKUP_DIR}${COLOR_RESET}

EOF
}

main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        list|ls)       cmd_list ;;
        add)           cmd_add "$@" ;;
        remove|rm|del) cmd_remove "$@" ;;
        block)         cmd_block "$@" ;;
        unblock)       cmd_unblock "$@" ;;
        disable|off)   cmd_disable "$@" ;;
        enable|on)     cmd_enable "$@" ;;
        search|grep|s) cmd_search "$@" ;;
        import)        cmd_import "$@" ;;
        backup|bak)    cmd_backup ;;
        restore)       cmd_restore ;;
        edit)          cmd_edit ;;
        flush|flush-dns) cmd_flush ;;
        help|-h|--help) cmd_help ;;
        *)             die "Неизвестная команда: $cmd  (запустите '$(basename "$0") help')" ;;
    esac
}

main "$@"
