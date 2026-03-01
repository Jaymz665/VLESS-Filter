#!/bin/sh

# ============================================
# VLESS Filter LuCI Installer for OpenWrt (APK)
# ФИНАЛЬНАЯ ВЕРСИЯ: Русский интерфейс + кнопка STOP
# ============================================

echo "======================================================"
echo "  VLESS Filter LuCI Service Installer"
echo "  OpenWrt APK Edition - Made by Jartz (aka Jaymz665)"
echo "======================================================"
echo ""

LOG_FILE="/tmp/vlessfilter_install.log"
exec 1> >(tee -a "$LOG_FILE") 2>&1

# Функции для вывода
print_step() {
    echo -e "\033[1;34m[$(date '+%H:%M:%S')]\033[0m \033[1;32m>>>\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARN]\033[0m $1"
}

print_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

# Проверка OpenWrt
check_openwrt() {
    print_step "Проверка системы OpenWrt..."
    
    if [ -f /etc/openwrt_version ] || [ -f /etc/openwrt_release ]; then
        print_step "OpenWrt обнаружен ✓"
    else
        print_warning "Не уверены что это OpenWrt, но продолжаем..."
    fi
    
    if command -v apk >/dev/null 2>&1; then
        print_step "Менеджер пакетов APK найден ✓"
    else
        print_error "Менеджер пакетов APK не найден!"
        exit 1
    fi
}

# Создание необходимых директорий
create_directories() {
    print_step "Создание директорий..."
    
    mkdir -p /usr/lib/lua/luci/controller
    mkdir -p /usr/lib/lua/luci/model/cbi/vlessfilter
    mkdir -p /usr/lib/lua/luci/view/vlessfilter
    mkdir -p /usr/bin
    mkdir -p /etc/config
    
    print_step "Директории созданы"
}

# Установка зависимостей
install_dependencies() {
    print_step "Обновление репозиториев APK..."
    apk update
    
    print_step "Установка зависимостей..."
    
    apk add \
        curl \
        bash \
        luci \
        luci-compat \
        luci-lib-jsonc \
        uhttpd \
        uhttpd-lua \
        jq \
        coreutils-timeout \
        coreutils-sort \
        sing-box 2>/dev/null
    
    print_step "Зависимости установлены"
}

# Создание UCI конфигурации
create_uci_config() {
    print_step "Создание UCI конфигурации..."
    
    cat > /etc/config/vlessfilter << 'EOF'
config settings 'settings'
    option enabled '0'
    option take_count '30'
    option update_cron '0 */6 * * *'
    option auto_update '0'
    option last_update ''
    option show_details '1'
    
config source 'source1'
    option name 'Список 1'
    option url 'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS.txt'
    option enabled '1'

config source 'source2'
    option name 'Список 2'
    option url 'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile.txt'
    option enabled '1'
    
config source 'source3'
    option name 'Список 3'
    option url ''
    option enabled '0'
    
config source 'source4'
    option name 'Список 4'
    option url ''
    option enabled '0'
    
config source 'source5'
    option name 'Список 5'
    option url ''
    option enabled '0'
EOF

    print_step "UCI конфигурация создана"
}

# Создание основного скрипта (только sing-box, без ping)
create_main_script() {
    print_step "Создание основного скрипта (только sing-box)..."
    
    cat > /usr/bin/vlessfilter.sh << 'EOF'
#!/bin/sh

# ============================================
# VLESS FILTER - Только sing-box проверка
# ============================================

CONFIG_FILE="/etc/config/vlessfilter"
LOG_FILE="/tmp/vlessfilter.log"
LOCK_FILE="/tmp/vlessfilter.lock"
TEMP_DIR="/tmp/vlessfilter_$$"
RESULTS_FILE="/tmp/vlessfilter_results.txt"
WORKING_LINKS_FILE="/tmp/vlessfilter_working.txt"
STOP_FLAG="/tmp/vlessfilter_stop.flag"

mkdir -p "$TEMP_DIR"
> "$RESULTS_FILE"
> "$WORKING_LINKS_FILE"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Функции вывода
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Проверка флага остановки
check_stop() {
    if [ -f "$STOP_FLAG" ]; then
        echo ""
        warning "⛔ Получен сигнал остановки! Прерываем работу..."
        rm -f "$STOP_FLAG"
        rm -rf "$TEMP_DIR" 2>/dev/null
        exit 1
    fi
}

# Функция извлечения информации из ссылки
parse_vless_url() {
    local url="$1"
    
    # Извлекаем UUID
    UUID=$(echo "$url" | sed -n 's/vless:\/\/\([^@]*\)@.*/\1/p')
    
    # Извлекаем сервер и порт
    SERVER=$(echo "$url" | sed -n 's/.*@\([^:]*\).*/\1/p')
    PORT=$(echo "$url" | sed -n 's/.*:\([0-9]*\)?.*/\1/p')
    
    # Извлекаем параметры
    TYPE=$(echo "$url" | grep -o 'type=[^&]*' | cut -d= -f2)
    SECURITY=$(echo "$url" | grep -o 'security=[^&]*' | cut -d= -f2)
    SNI=$(echo "$url" | grep -o 'sni=[^&]*' | cut -d= -f2)
    FP=$(echo "$url" | grep -o 'fp=[^&]*' | cut -d= -f2)
    PBK=$(echo "$url" | grep -o 'pbk=[^&]*' | cut -d= -f2)
    SID=$(echo "$url" | grep -o 'sid=[^&]*' | cut -d= -f2)
    
    # Извлекаем название/тег из URL (если есть)
    TAG=$(echo "$url" | grep -o 'main-[0-9]*-out' || echo "unknown")
    
    # Если нет тега, пробуем извлечь из комментария
    if [ "$TAG" = "unknown" ]; then
        TAG=$(echo "$url" | grep -o '#[^#]*$' | sed 's/#//' | cut -c1-20)
    fi
    
    [ -z "$TAG" ] && TAG="link-$RANDOM"
}

# Извлечение хоста из vless ссылки
get_vless_host() {
    local link="$1"
    echo "$link" | sed -n 's/^vless:\/\/[^@]*@\([^:/?#]\+\).*/\1/p'
}

# Функция проверки ссылки через sing-box
test_link() {
    local url="$1"
    local num="$2"
    
    check_stop
    
    parse_vless_url "$url"
    
    # Создаем тестовый конфиг
    local test_config="$TEMP_DIR/test_$num.json"
    
    # Формируем JSON в зависимости от параметров
    cat > "$test_config" << INNEREOF
{
  "log": { "level": "error", "output": "/dev/null" },
  "inbounds": [ { "type": "direct", "tag": "in" } ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "test-$num",
      "server": "$SERVER",
      "server_port": ${PORT:-443},
      "uuid": "$UUID"
INNEREOF

    # Добавляем flow если есть
    if echo "$url" | grep -q 'flow='; then
        FLOW=$(echo "$url" | grep -o 'flow=[^&]*' | cut -d= -f2)
        echo "      ,\"flow\": \"$FLOW\"" >> "$test_config"
    fi
    
    # Добавляем TLS секцию если есть
    if [ "$SECURITY" = "reality" ] || [ -n "$SNI" ]; then
        cat >> "$test_config" << INNEREOF
      ,
      "tls": {
        "enabled": true,
        "server_name": "${SNI:-$SERVER}"
INNEREOF
        
        # Добавляем utls если есть fingerprint
        if [ -n "$FP" ]; then
            cat >> "$test_config" << INNEREOF
        ,
        "utls": {
          "enabled": true,
          "fingerprint": "$FP"
        }
INNEREOF
        fi
        
        # Добавляем reality если есть
        if [ "$SECURITY" = "reality" ] && [ -n "$PBK" ]; then
            cat >> "$test_config" << INNEREOF
        ,
        "reality": {
          "enabled": true,
          "public_key": "$PBK"$( [ -n "$SID" ] && echo ",\n          \"short_id\": \"$SID\"" )
        }
INNEREOF
        fi
        
        echo "      }" >> "$test_config"
    else
        echo "" >> "$test_config"
    fi
    
    # Закрываем JSON
    echo "    }" >> "$test_config"
    echo "  ]" >> "$test_config"
    echo "}" >> "$test_config"
    
    # Проверяем через sing-box
    if sing-box check -c "$test_config" > "$TEMP_DIR/check_$num.log" 2>&1; then
        return 0
    else
        return 1
    fi
}

# Функция принудительной остановки
stop_vlessfilter() {
    echo ""
    log "🛑 Принудительная остановка всех процессов..."
    
    # Создаем флаг остановки
    touch "$STOP_FLAG"
    
    # Находим и убиваем все процессы vlessfilter
    local pids=$(pgrep -f "vlessfilter.sh")
    if [ -n "$pids" ]; then
        for pid in $pids; do
            if [ "$pid" != "$$" ]; then
                kill -9 "$pid" 2>/dev/null
                log "  Убит процесс PID: $pid"
            fi
        done
    fi
    
    # Убиваем дочерние процессы (sing-box)
    pkill -9 -f "sing-box" 2>/dev/null
    
    # Очистка
    rm -f "$LOCK_FILE" "$STOP_FLAG"
    rm -rf /tmp/vlessfilter_* 2>/dev/null
    
    log "✅ Все процессы остановлены"
    exit 0
}

# Загрузка настроек
ENABLED=$(uci -q get vlessfilter.settings.enabled || echo "0")
TAKE_COUNT=$(uci -q get vlessfilter.settings.take_count || echo "30")
SHOW_DETAILS=$(uci -q get vlessfilter.settings.show_details || echo "1")

# Проверка на принудительную остановку
if [ "$1" = "stop" ]; then
    stop_vlessfilter
fi

if [ "$ENABLED" != "1" ] && [ "$1" != "force" ]; then
    exit 0
fi

# Проверка блокировки
if [ -f "$LOCK_FILE" ]; then
    local pid=$(cat "$LOCK_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        error "Скрипт уже запущен (PID: $pid)"
        error "Используйте кнопку STOP в интерфейсе или команду: $0 stop"
        exit 1
    else
        rm -f "$LOCK_FILE"
    fi
fi
echo $$ > "$LOCK_FILE"

# Красивый заголовок
clear
echo ""
echo -e "${PURPLE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${WHITE}         VLESS FILTER - ПРОВЕРКА ССЫЛОК                ${PURPLE}║${NC}"
echo -e "${PURPLE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

log "Запуск проверки ссылок..."
info "Будет отобрано по $TAKE_COUNT рабочих ссылок ИЗ КАЖДОГО ИСТОЧНИКА"
echo ""

# Вместо массивов используем временные файлы для хранения информации об источниках
SOURCE_LIST="$TEMP_DIR/sources.list"
> "$SOURCE_LIST"

source_index=0
TOTAL_SOURCES=0

# Сначала загружаем все источники
i=1
while [ $i -le 5 ]; do
    check_stop
    SOURCE_ENABLED=$(uci -q get vlessfilter.@source[$((i-1))].enabled || echo "0")
    if [ "$SOURCE_ENABLED" = "1" ]; then
        
        SOURCE_URL=$(uci -q get vlessfilter.@source[$((i-1))].url)
        SOURCE_NAME=$(uci -q get vlessfilter.@source[$((i-1))].name || echo "Источник $i")
        
        TOTAL_SOURCES=$((TOTAL_SOURCES + 1))
        
        # Сохраняем информацию об источнике в файл
        echo "$source_index|$SOURCE_NAME|$SOURCE_URL" >> "$SOURCE_LIST"
        
        printf "  ${CYAN}[%d/5]${NC} Загрузка %-25s" "$source_index" "$SOURCE_NAME"
        
        SOURCE_FILE="$TEMP_DIR/source_${source_index}.txt"
        SOURCE_LINKS="$TEMP_DIR/source_${source_index}_links.txt"
        
        if curl -s -L --connect-timeout 10 "$SOURCE_URL" -o "$SOURCE_FILE" 2>/dev/null; then
            TOTAL=$(grep -c "vless://" "$SOURCE_FILE")
            grep "vless://" "$SOURCE_FILE" > "$SOURCE_LINKS"
            
            echo -e "${GREEN} ✓${NC} (найдено: $TOTAL)"
            
            source_index=$((source_index + 1))
        else
            echo -e "${RED} ✗ Ошибка загрузки${NC}"
        fi
    fi
    i=$((i + 1))
done

echo ""
info "Загружено источников: $TOTAL_SOURCES"
echo ""

# ============= ЭТАП: SING-BOX ПРОВЕРКА КАЖДОГО ИСТОЧНИКА =============
info "Этап: Проверка всех ссылок через sing-box..."
echo ""

# Заголовок таблицы
printf "${WHITE}%-4s | %-20s | %-25s | %-15s | %-8s | %s${NC}\n" "№" "Источник" "Тег/Название" "Сервер" "Порт" "Статус"
printf "%s\n" "---------------------------------------------------------------------------------------------------"

TOTAL_CHECKED=0
TOTAL_WORKING=0
GLOBAL_COUNT=0

> "$TEMP_DIR/all_working.txt"
WORKING_COUNTS_FILE="$TEMP_DIR/working_counts.txt"
> "$WORKING_COUNTS_FILE"

# Для каждого источника создаем файл с рабочими ссылками
idx=0
while [ $idx -lt $source_index ]; do
    check_stop
    
    # Получаем имя источника
    SOURCE_NAME=$(grep "^$idx|" "$SOURCE_LIST" | cut -d'|' -f2)
    
    SOURCE_LINKS="$TEMP_DIR/source_${idx}_links.txt"
    SOURCE_WORKING_FILE="$TEMP_DIR/source_${idx}_working.txt"
    > "$SOURCE_WORKING_FILE"
    
    if [ ! -f "$SOURCE_LINKS" ] || [ ! -s "$SOURCE_LINKS" ]; then
        echo "$idx|0" >> "$WORKING_COUNTS_FILE"
        idx=$((idx + 1))
        continue
    fi
    
    # Считаем общее количество ссылок в источнике
    TOTAL_IN_SOURCE=$(wc -l < "$SOURCE_LINKS")
    
    # Счетчик для этого источника
    SOURCE_COUNT=0
    SOURCE_WORKING_COUNT=0
    
    # Читаем все ссылки источника
    while read -r link; do
        check_stop
        [ -z "$link" ] && continue
        GLOBAL_COUNT=$((GLOBAL_COUNT + 1))
        SOURCE_COUNT=$((SOURCE_COUNT + 1))
        
        # Отображаем прогресс
        printf "\r${CYAN}▶${NC} %s: %d/%d" "$SOURCE_NAME" "$SOURCE_COUNT" "$TOTAL_IN_SOURCE"
        
        # Извлекаем информацию для отображения
        parse_vless_url "$link"
        
        # Проверяем ссылку через sing-box
        if test_link "$link" "$GLOBAL_COUNT"; then
            SOURCE_WORKING_COUNT=$((SOURCE_WORKING_COUNT + 1))
            echo "$link" >> "$SOURCE_WORKING_FILE"
            
            # Очищаем строку и выводим результат
            printf "\r\033[K"
            printf "${GREEN}%-4s${NC} | ${CYAN}%-20s${NC} | ${CYAN}%-25s${NC} | ${YELLOW}%-15s${NC} | ${WHITE}%-8s${NC} | ${GREEN}✅${NC}\n" \
                "$GLOBAL_COUNT" "${SOURCE_NAME:0:20}" "${TAG:0:25}" "$SERVER" "$PORT"
        else
            # Очищаем строку и выводим результат
            printf "\r\033[K"
            ERROR_MSG=$(head -1 "$TEMP_DIR/check_$GLOBAL_COUNT.log" 2>/dev/null | cut -c1-40)
            [ -z "$ERROR_MSG" ] && ERROR_MSG="Ошибка"
            
            printf "${YELLOW}%-4s${NC} | ${CYAN}%-20s${NC} | ${CYAN}%-25s${NC} | ${YELLOW}%-15s${NC} | ${WHITE}%-8s${NC} | ${RED}❌${NC}\n" \
                "$GLOBAL_COUNT" "${SOURCE_NAME:0:20}" "${TAG:0:25}" "$SERVER" "$PORT"
        fi
        
    done < "$SOURCE_LINKS"
    
    TOTAL_WORKING=$((TOTAL_WORKING + SOURCE_WORKING_COUNT))
    echo "$idx|$SOURCE_WORKING_COUNT" >> "$WORKING_COUNTS_FILE"
    
    echo ""
    idx=$((idx + 1))
done

echo ""
echo ""

# ============= ЭТАП: ОТБОР ЛУЧШИХ ИЗ КАЖДОГО ИСТОЧНИКА =============
info "Этап: Отбор $TAKE_COUNT рабочих ссылок из каждого источника..."
echo ""

> "$WORKING_LINKS_FILE"

# Заголовок таблицы для лучших ссылок
printf "${WHITE}%-4s | %-20s | %-25s | %-15s | %-8s${NC}\n" "#" "Источник" "Тег/Название" "Сервер" "Порт"
printf "%s\n" "---------------------------------------------------------------------------"

TOTAL_SELECTED=0
POS=1

idx=0
while [ $idx -lt $source_index ]; do
    check_stop
    
    # Получаем имя источника
    SOURCE_NAME=$(grep "^$idx|" "$SOURCE_LIST" | cut -d'|' -f2)
    
    SOURCE_WORKING_FILE="$TEMP_DIR/source_${idx}_working.txt"
    
    if [ ! -f "$SOURCE_WORKING_FILE" ] || [ ! -s "$SOURCE_WORKING_FILE" ]; then
        idx=$((idx + 1))
        continue
    fi
    
    # Берем первые TAKE_COUNT рабочих ссылок
    SOURCE_BEST="$TEMP_DIR/source_${idx}_best.txt"
    head -n "$TAKE_COUNT" "$SOURCE_WORKING_FILE" > "$SOURCE_BEST"
    
    # Счетчик для этого источника
    SOURCE_ADDED=0
    
    while read -r link; do
        [ -z "$link" ] && continue
        
        parse_vless_url "$link"
        echo "$link" >> "$WORKING_LINKS_FILE"
        
        printf "${GREEN}%-4s${NC} | ${CYAN}%-20s${NC} | ${CYAN}%-25s${NC} | ${YELLOW}%-15s${NC} | ${WHITE}%-8s${NC}\n" \
            "$POS" "${SOURCE_NAME:0:20}" "${TAG:0:25}" "$SERVER" "$PORT"
        
        POS=$((POS + 1))
        SOURCE_ADDED=$((SOURCE_ADDED + 1))
        TOTAL_SELECTED=$((TOTAL_SELECTED + 1))
        
    done < "$SOURCE_BEST"
    
    log "  $SOURCE_NAME: добавлено $SOURCE_ADDED рабочих ссылок"
    idx=$((idx + 1))
done

echo ""
info "Всего отобрано: $TOTAL_SELECTED рабочих ссылок (по $TAKE_COUNT из каждого источника)"
echo ""

# Сохраняем детальные результаты
{
    echo "=== VLESS FILTER РЕЗУЛЬТАТЫ ==="
    echo "Дата проверки: $(date)"
    echo "Всего источников: $TOTAL_SOURCES"
    echo "Всего проверено ссылок: $GLOBAL_COUNT"
    echo "Рабочих ссылок: $TOTAL_WORKING"
    echo "Отобрано лучших (по $TAKE_COUNT из каждого): $TOTAL_SELECTED"
    echo ""
    echo "=== СТАТИСТИКА ПО ИСТОЧНИКАМ ==="
    
    idx=0
    while [ $idx -lt $source_index ]; do
        SOURCE_NAME=$(grep "^$idx|" "$SOURCE_LIST" | cut -d'|' -f2)
        WORKING_COUNT=$(grep "^$idx|" "$WORKING_COUNTS_FILE" | cut -d'|' -f2)
        
        [ -z "$WORKING_COUNT" ] && WORKING_COUNT=0
        
        echo "$SOURCE_NAME: рабочих: $WORKING_COUNT, отобрано: $TAKE_COUNT"
        idx=$((idx + 1))
    done
    
    echo ""
    echo "=== ВСЕ ОТОБРАННЫЕ ССЫЛКИ (ПО ИСТОЧНИКАМ) ==="
    idx=0
    while [ $idx -lt $source_index ]; do
        SOURCE_NAME=$(grep "^$idx|" "$SOURCE_LIST" | cut -d'|' -f2)
        SOURCE_BEST="$TEMP_DIR/source_${idx}_best.txt"
        
        if [ ! -f "$SOURCE_BEST" ] || [ ! -s "$SOURCE_BEST" ]; then
            idx=$((idx + 1))
            continue
        fi
        
        echo ""
        echo "--- $SOURCE_NAME ---"
        cat "$SOURCE_BEST"
        idx=$((idx + 1))
    done
} > "$RESULTS_FILE"

echo ""

# Выводим статистику
echo -e "${PURPLE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║${WHITE}                     РЕЗУЛЬТАТЫ                       ${PURPLE}║${NC}"
echo -e "${PURPLE}╠════════════════════════════════════════════════════════╣${NC}"
printf "${PURPLE}║${NC} ${GREEN}📥 Источников:${NC} %-36s ${PURPLE}║${NC}\n" "$TOTAL_SOURCES"
printf "${PURPLE}║${NC} ${GREEN}✅ Проверено ссылок:${NC} %-29s ${PURPLE}║${NC}\n" "$GLOBAL_COUNT"
printf "${PURPLE}║${NC} ${GREEN}✅ Рабочих ссылок:${NC} %-30s ${PURPLE}║${NC}\n" "$TOTAL_WORKING"
printf "${PURPLE}║${NC} ${GREEN}🏆 Отобрано лучших:${NC} %-28s ${PURPLE}║${NC}\n" "$TOTAL_SELECTED"
echo -e "${PURPLE}╠════════════════════════════════════════════════════════╣${NC}"

# Статистика по источникам
idx=0
while [ $idx -lt $source_index ]; do
    SOURCE_NAME=$(grep "^$idx|" "$SOURCE_LIST" | cut -d'|' -f2)
    WORKING_COUNT=$(grep "^$idx|" "$WORKING_COUNTS_FILE" | cut -d'|' -f2)
    [ -z "$WORKING_COUNT" ] && WORKING_COUNT=0
    
    printf "${PURPLE}║${NC} ${CYAN}%-15s${NC}: рабочих: %-4d | отобрано: %-4d ${PURPLE}║${NC}\n" \
        "${SOURCE_NAME:0:15}" "$WORKING_COUNT" "$TAKE_COUNT"
    idx=$((idx + 1))
done

echo -e "${PURPLE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

info "Детальные результаты сохранены в: $RESULTS_FILE"
echo ""

# Обновляем конфиг podkop
if [ -f /etc/init.d/podkop ] && [ -s "$WORKING_LINKS_FILE" ]; then
    echo -e "${BLUE}🔄 Обновление podkop конфигурации...${NC}"
    
    # Создаем бэкап
    BACKUP_FILE="/etc/config/podkop.backup.$(date +%Y%m%d_%H%M%S)"
    cp /etc/config/podkop "$BACKUP_FILE" 2>/dev/null
    echo -e "  ${CYAN}✓${NC} Бэкап создан: $(basename "$BACKUP_FILE")"
    
    # Очищаем старые ссылки
    uci delete podkop.main.urltest_proxy_links 2>/dev/null
    
    # Добавляем новые
    ADDED=0
    while read -r link; do
        if [ -n "$link" ]; then
            escaped=$(echo "$link" | sed "s/'/'\\\\''/g")
            uci add_list podkop.main.urltest_proxy_links="$escaped"
            ADDED=$((ADDED + 1))
        fi
    done < "$WORKING_LINKS_FILE"
    
    uci commit podkop
    echo -e "  ${GREEN}✓${NC} Добавлено $ADDED рабочих ссылок в podkop"
    
    # Перезапускаем podkop
    echo -e "  ${YELLOW}⟲${NC} Перезапуск podkop..."
    /etc/init.d/podkop restart
    sleep 3
    
    # Проверяем статус
    if /etc/init.d/podkop status | grep -q "running"; then
        echo -e "  ${GREEN}✓${NC} Podkop успешно запущен"
    else
        echo -e "  ${RED}✗${NC} Ошибка при запуске podkop"
    fi
fi

# Обновляем время последнего обновления
uci set vlessfilter.settings.last_update="$(date '+%Y-%m-%d %H:%M:%S')"
uci commit vlessfilter

# Очистка
rm -f "$LOCK_FILE" "$STOP_FLAG" 2>/dev/null
rm -rf "$TEMP_DIR" 2>/dev/null

echo ""
log "✅ Проверка завершена! В podkop добавлено $TOTAL_SELECTED рабочих ссылок"
echo ""
EOF

    chmod +x /usr/bin/vlessfilter.sh
    print_step "Основной скрипт создан"
}

# Создание LuCI контроллера (русская версия)
create_luci_controller() {
    print_step "Создание LuCI контроллера..."
    
    cat > /usr/lib/lua/luci/controller/vlessfilter.lua << 'EOF'
module("luci.controller.vlessfilter", package.seeall)

function index()
    entry({"admin", "services", "vlessfilter"}, firstchild(), _("VLESS Filter"), 91).dependent = false
    
    entry({"admin", "services", "vlessfilter", "general"}, cbi("vlessfilter/general"), _("Общие настройки"), 10)
    entry({"admin", "services", "vlessfilter", "sources"}, cbi("vlessfilter/sources"), _("Источники"), 20)
    entry({"admin", "services", "vlessfilter", "status"}, template("vlessfilter/status"), _("Статус и результаты"), 30)
    entry({"admin", "services", "vlessfilter", "logs"}, template("vlessfilter/logs"), _("Логи"), 40)
    
    entry({"admin", "services", "vlessfilter", "api"}, call("api_handler")).leaf = true
end

function api_handler()
    local http = require("luci.http")
    local sys = require("luci.sys")
    local uci = require("luci.model.uci").cursor()
    local fs = require("nixio.fs")
    local action = http.formvalue("action")
    
    local LOG_FILE = "/tmp/vlessfilter.log"
    local RESULTS_FILE = "/tmp/vlessfilter_results.txt"
    
    if action == "status" then
        local running = sys.call("pgrep -f 'vlessfilter.sh' >/dev/null 2>&1") == 0
        local last_update = uci:get("vlessfilter", "settings", "last_update") or "Никогда"
        local enabled = uci:get("vlessfilter", "settings", "enabled") or "0"
        
        http.prepare_content("application/json")
        http.write_json({
            running = running,
            last_update = last_update,
            enabled = enabled
        })
        
    elseif action == "run_now" then
        local script_path = "/usr/bin/vlessfilter.sh"
        if fs.access(script_path) then
            sys.call("sh " .. script_path .. " force > " .. LOG_FILE .. " 2>&1 &")
            http.prepare_content("application/json")
            http.write_json({success = true})
        else
            http.prepare_content("application/json")
            http.write_json({success = false, error = "Script not found"})
        end
        
    elseif action == "stop_now" then
        local script_path = "/usr/bin/vlessfilter.sh"
        if fs.access(script_path) then
            sys.call("sh " .. script_path .. " stop > /dev/null 2>&1 &")
            http.prepare_content("application/json")
            http.write_json({success = true})
        else
            http.prepare_content("application/json")
            http.write_json({success = false, error = "Script not found"})
        end
        
    elseif action == "get_log" then
        local content = ""
        if fs.access(LOG_FILE) then
            local f = io.open(LOG_FILE, "r")
            if f then
                content = f:read("*all")
                f:close()
            end
        end
        http.prepare_content("application/json")
        http.write_json({log = content})
        
    elseif action == "get_results" then
        local content = ""
        if fs.access(RESULTS_FILE) then
            local f = io.open(RESULTS_FILE, "r")
            if f then
                content = f:read("*all")
                f:close()
            end
        end
        http.prepare_content("application/json")
        http.write_json({results = content})
        
    elseif action == "clear_log" then
        sys.exec("> " .. LOG_FILE)
        http.prepare_content("application/json")
        http.write_json({success = true})
    elseif action == "check_running" then
        local running = sys.call("pgrep -f 'vlessfilter.sh' >/dev/null 2>&1") == 0
        http.prepare_content("application/json")
        http.write_json({running = running})
    end
end
EOF

    print_step "LuCI контроллер создан"
}

# Создание General CBI (русская версия)
create_general_cbi() {
    print_step "Создание общих настроек..."
    
    cat > /usr/lib/lua/luci/model/cbi/vlessfilter/general.lua << 'EOF'
local sys = require("luci.sys")

m = Map("vlessfilter", translate("VLESS Filter - Общие настройки"))

s = m:section(NamedSection, "settings", "settings", translate("Основная конфигурация"))

enabled = s:option(Flag, "enabled", translate("Включить авто-обновление"))
enabled.default = 0
enabled.description = translate("Автоматически проверять и отбирать лучшие ссылки")

take_count = s:option(Value, "take_count", translate("Количество ссылок из каждого источника"))
take_count.datatype = "range(1,200)"
take_count.default = 30
take_count.description = translate("Сколько лучших ссылок отбирать из каждого источника")

show_details = s:option(Flag, "show_details", translate("Показывать детальный вывод"))
show_details.default = 1

cron = s:option(Value, "update_cron", translate("Расписание cron"))
cron.default = "0 */6 * * *"
cron:value("*/30 * * * *", "Каждые 30 минут")
cron:value("0 * * * *", "Каждый час")
cron:value("0 */3 * * *", "Каждые 3 часа")
cron:value("0 */6 * * *", "Каждые 6 часов")
cron:value("0 0 * * *", "Раз в день")

-- Кнопки ручного управления
local run_btn = s:option(Button, "_run_now")
run_btn.title = translate("Ручной запуск")
run_btn.inputtitle = translate("Запустить проверку")
run_btn.inputstyle = "apply"
run_btn.template = "vlessfilter/run_button"

return m
EOF

    print_step "Общие настройки созданы"
}

# Создание Sources CBI (русская версия)
create_sources_cbi() {
    print_step "Создание настроек источников..."
    
    cat > /usr/lib/lua/luci/model/cbi/vlessfilter/sources.lua << 'EOF'
m = Map("vlessfilter", translate("VLESS Filter - Источники"))

for i = 1, 5 do
    s = m:section(NamedSection, "source" .. i, "source" .. i, translatef("Источник %d", i))
    
    enabled = s:option(Flag, "enabled", translate("Включен"))
    enabled.default = (i <= 2) and 1 or 0
    
    name = s:option(Value, "name", translate("Название"))
    name.default = translatef("Список %d", i)
    
    url = s:option(Value, "url", translate("URL"))
    if i == 1 then
        url.default = "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS.txt"
    elseif i == 2 then
        url.default = "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile.txt"
    end
end

return m
EOF

    print_step "Настройки источников созданы"
}

# Создание шаблона для кнопки с русским интерфейсом и кнопкой STOP
create_run_button_template() {
    print_step "Создание шаблона кнопок управления..."
    
    cat > /usr/lib/lua/luci/view/vlessfilter/run_button.htm << 'EOF'
<%+cbi/valueheader%>

<style>
.control-panel {
    margin-top: 10px;
    padding: 15px;
    background: #2d2d2d;
    border-radius: 6px;
    border-left: 4px solid #007bff;
}
.progress-indicator {
    margin-top: 15px;
    padding: 15px;
    background: #1e1e1e;
    border-radius: 4px;
    display: none;
    border-left: 4px solid #28a745;
}
.progress-bar {
    width: 100%;
    height: 20px;
    background: #444;
    border-radius: 10px;
    overflow: hidden;
    margin: 10px 0;
}
.progress-fill {
    height: 100%;
    background: linear-gradient(90deg, #007bff, #00ff88);
    width: 0%;
    transition: width 0.3s ease;
}
.status-text {
    color: #00ff00;
    font-family: monospace;
    font-size: 12px;
    margin-top: 5px;
}
.button-group {
    display: flex;
    gap: 10px;
    margin-bottom: 10px;
}
.run-btn {
    padding: 10px 20px;
    background: #007bff;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-size: 14px;
    font-weight: bold;
}
.stop-btn {
    padding: 10px 20px;
    background: #dc3545;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-size: 14px;
    font-weight: bold;
}
.run-btn:hover:not(:disabled) {
    background: #0056b3;
}
.stop-btn:hover:not(:disabled) {
    background: #c82333;
}
.run-btn:disabled, .stop-btn:disabled {
    background: #666;
    cursor: not-allowed;
    opacity: 0.5;
}
.status-badge {
    display: inline-block;
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 12px;
    font-weight: bold;
    margin-left: 10px;
}
.badge-running {
    background: #28a745;
    color: white;
}
.badge-stopped {
    background: #6c757d;
    color: white;
}
</style>

<div class="control-panel">
    <div class="button-group">
        <input type="button" class="run-btn" id="runBtn" value="▶ <%=self.inputtitle%>" onclick="runNow()" />
        <input type="button" class="stop-btn" id="stopBtn" value="⛔ Принудительная остановка" onclick="stopNow()" />
        <span id="statusBadge" class="status-badge badge-stopped">Остановлен</span>
    </div>
</div>

<div id="progressIndicator" class="progress-indicator">
    <div class="progress-bar">
        <div id="progressFill" class="progress-fill"></div>
    </div>
    <div id="progressStatus" class="status-text">Запуск...</div>
    <div id="progressDetails" class="status-text" style="color: #aaa; font-size: 11px;"></div>
</div>

<script type="text/javascript">
function updateStatus() {
    XHR.get('<%=luci.dispatcher.build_url("admin/services/vlessfilter/api")%>?action=check_running', null, function(x, status) {
        const badge = document.getElementById('statusBadge');
        const runBtn = document.getElementById('runBtn');
        const stopBtn = document.getElementById('stopBtn');
        
        if (status && status.running) {
            badge.textContent = 'Выполняется';
            badge.className = 'status-badge badge-running';
            runBtn.disabled = true;
            stopBtn.disabled = false;
        } else {
            badge.textContent = 'Остановлен';
            badge.className = 'status-badge badge-stopped';
            runBtn.disabled = false;
            stopBtn.disabled = true;
            
            // Скрываем прогресс если он был виден
            const progress = document.getElementById('progressIndicator');
            if (progress.style.display === 'block') {
                setTimeout(function() {
                    progress.style.display = 'none';
                }, 2000);
            }
        }
    });
}

function runNow() {
    const runBtn = document.getElementById('runBtn');
    const stopBtn = document.getElementById('stopBtn');
    const progress = document.getElementById('progressIndicator');
    const progressFill = document.getElementById('progressFill');
    const progressStatus = document.getElementById('progressStatus');
    const progressDetails = document.getElementById('progressDetails');
    
    runBtn.disabled = true;
    stopBtn.disabled = false;
    progress.style.display = 'block';
    progressFill.style.width = '10%';
    progressStatus.textContent = 'Запуск проверки...';
    
    XHR.get('<%=luci.dispatcher.build_url("admin/services/vlessfilter/api")%>?action=run_now', null, function(x, data) {
        if (data && data.success) {
            progressStatus.textContent = '✅ Проверка запущена';
            progressFill.style.width = '30%';
            updateStatus();
            
            let checkInterval = setInterval(function() {
                XHR.get('<%=luci.dispatcher.build_url("admin/services/vlessfilter/api")%>?action=check_running', null, function(x, status) {
                    if (status && !status.running) {
                        clearInterval(checkInterval);
                        progressFill.style.width = '100%';
                        progressStatus.textContent = '✅ Проверка завершена!';
                        updateStatus();
                        
                        // Обновляем результаты
                        if (window.parent && window.parent.frames && window.parent.frames[2]) {
                            window.parent.frames[2].location.reload();
                        }
                    } else {
                        progressFill.style.width = '60%';
                        progressStatus.textContent = '🔄 Проверка ссылок...';
                        
                        XHR.get('<%=luci.dispatcher.build_url("admin/services/vlessfilter/api")%>?action=get_log&lines=5', null, function(x, logData) {
                            if (logData && logData.log) {
                                let lines = logData.log.split('\n').filter(l => l.includes('Проверка') || l.includes('✅')).slice(-1);
                                if (lines.length > 0) {
                                    progressDetails.textContent = lines[0];
                                }
                            }
                        });
                    }
                });
            }, 2000);
        }
    });
}

function stopNow() {
    const stopBtn = document.getElementById('stopBtn');
    const progress = document.getElementById('progressIndicator');
    const progressStatus = document.getElementById('progressStatus');
    
    if (!confirm('Принудительно остановить проверку? Процесс будет прерван.')) {
        return;
    }
    
    stopBtn.disabled = true;
    progress.style.display = 'block';
    progressStatus.textContent = '⛔ Остановка...';
    
    XHR.get('<%=luci.dispatcher.build_url("admin/services/vlessfilter/api")%>?action=stop_now', null, function(x, data) {
        if (data && data.success) {
            progressStatus.textContent = '✅ Процесс остановлен';
            setTimeout(function() {
                progress.style.display = 'none';
                updateStatus();
            }, 2000);
        }
    });
}

// Обновляем статус каждые 2 секунды
setInterval(updateStatus, 2000);
updateStatus();
</script>

<%+cbi/valuefooter%>
EOF

    print_step "Шаблон кнопок создан"
}

# Создание Status view (русская версия)
create_status_view() {
    print_step "Создание страницы статуса..."
    
    cat > /usr/lib/lua/luci/view/vlessfilter/status.htm << 'EOF'
<%+header%>
<style>
.vless-container {
    max-width: 1200px;
    margin: 20px auto;
    padding: 20px;
    background: #1e1e1e;
    border-radius: 8px;
    color: #f0f0f0;
}
.status-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
    flex-wrap: wrap;
    gap: 10px;
}
.status-title {
    font-size: 24px;
    font-weight: bold;
}
.status-badge {
    padding: 6px 12px;
    border-radius: 4px;
    font-weight: bold;
}
.badge-running {
    background: #28a745;
    color: white;
}
.badge-stopped {
    background: #dc3545;
    color: white;
}
.info-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 20px;
    margin-bottom: 30px;
    background: #2d2d2d;
    padding: 20px;
    border-radius: 6px;
}
.info-item {
    display: flex;
    flex-direction: column;
    gap: 5px;
}
.info-label {
    color: #aaa;
    font-size: 12px;
    text-transform: uppercase;
}
.info-value {
    color: #fff;
    font-size: 18px;
    font-weight: bold;
}
.results-container {
    background: #2d2d2d;
    padding: 20px;
    border-radius: 6px;
    margin-top: 20px;
}
.results-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 15px;
}
.results-title {
    font-size: 18px;
    font-weight: bold;
    color: #4dabf7;
}
.results-content {
    background: #000;
    color: #00ff00;
    padding: 15px;
    border-radius: 6px;
    font-family: monospace;
    font-size: 13px;
    line-height: 1.6;
    white-space: pre-wrap;
    max-height: 500px;
    overflow-y: auto;
    border: 1px solid #444;
}
.refresh-btn {
    padding: 8px 16px;
    background: #28a745;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
}
.refresh-btn:hover {
    background: #218838;
}
</style>

<div class="vless-container">
    <div class="status-header">
        <span class="status-title">VLESS Filter - Статус и результаты</span>
        <span id="statusBadge" class="status-badge badge-stopped">Проверка...</span>
    </div>
    
    <div class="info-grid">
        <div class="info-item">
            <span class="info-label">Последнее обновление</span>
            <span id="lastUpdate" class="info-value">Никогда</span>
        </div>
        <div class="info-item">
            <span class="info-label">Авто-обновление</span>
            <span id="autoUpdate" class="info-value">Отключено</span>
        </div>
        <div class="info-item">
            <span class="info-label">Проверено ссылок</span>
            <span id="totalChecked" class="info-value">-</span>
        </div>
        <div class="info-item">
            <span class="info-label">Рабочих ссылок</span>
            <span id="workingCount" class="info-value">-</span>
        </div>
        <div class="info-item">
            <span class="info-label">Отобрано лучших</span>
            <span id="bestCount" class="info-value">-</span>
        </div>
    </div>
    
    <div class="results-container">
        <div class="results-header">
            <span class="results-title">📊 Результаты последней проверки</span>
            <button id="refreshResultsBtn" class="refresh-btn">🔄 Обновить</button>
        </div>
        <pre id="resultsContent" class="results-content">Загрузка результатов...</pre>
    </div>
</div>

<script type="text/javascript">
(function() {
    const statusBadge = document.getElementById('statusBadge');
    const lastUpdate = document.getElementById('lastUpdate');
    const autoUpdate = document.getElementById('autoUpdate');
    const totalChecked = document.getElementById('totalChecked');
    const workingCount = document.getElementById('workingCount');
    const bestCount = document.getElementById('bestCount');
    const resultsContent = document.getElementById('resultsContent');
    const refreshResultsBtn = document.getElementById('refreshResultsBtn');
    
    function fetchStatus() {
        XHR.get('<%=luci.dispatcher.build_url("admin/services/vlessfilter/api")%>?action=status', null, function(x, data) {
            if (data) {
                statusBadge.textContent = data.running ? 'Выполняется' : 'Остановлен';
                statusBadge.className = 'status-badge ' + (data.running ? 'badge-running' : 'badge-stopped');
                lastUpdate.textContent = data.last_update || 'Никогда';
                autoUpdate.textContent = data.enabled === '1' ? 'Включено' : 'Отключено';
            }
        });
    }
    
    function fetchResults() {
        resultsContent.textContent = 'Загрузка результатов...';
        XHR.get('<%=luci.dispatcher.build_url("admin/services/vlessfilter/api")%>?action=get_results', null, function(x, data) {
            if (data && data.results) {
                resultsContent.textContent = data.results || 'Нет результатов. Запустите проверку.';
                
                // Парсим статистику
                const checkedMatch = data.results.match(/проверено ссылок:\s+(\d+)/i);
                const workingMatch = data.results.match(/Рабочих ссылок:\s+(\d+)/i);
                const bestMatch = data.results.match(/Отобрано лучших:\s+(\d+)/i);
                
                if (checkedMatch) totalChecked.textContent = checkedMatch[1];
                if (workingMatch) workingCount.textContent = workingMatch[1];
                if (bestMatch) bestCount.textContent = bestMatch[1];
            }
        });
    }
    
    refreshResultsBtn.addEventListener('click', fetchResults);
    
    // Первоначальная загрузка и периодическое обновление
    fetchStatus();
    fetchResults();
    setInterval(fetchStatus, 5000);
    setInterval(fetchResults, 10000);
})();
</script>
<%+footer%>
EOF

    print_step "Страница статуса создана"
}

# Создание Logs view (русская версия)
create_logs_view() {
    print_step "Создание страницы логов..."
    
    cat > /usr/lib/lua/luci/view/vlessfilter/logs.htm << 'EOF'
<%+header%>
<style>
.log-container {
    max-width: 900px;
    margin: 20px auto;
    padding: 20px;
    background: #1e1e1e;
    border-radius: 8px;
    color: #f0f0f0;
}
.log-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
}
.log-title {
    font-size: 24px;
    font-weight: bold;
}
.log-actions {
    display: flex;
    gap: 10px;
}
.log-btn {
    padding: 8px 16px;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    background: #2d2d2d;
    color: #fff;
}
.log-btn:hover {
    background: #3d3d3d;
}
.log-content {
    background: #000;
    color: #00ff00;
    padding: 15px;
    border-radius: 6px;
    font-family: monospace;
    font-size: 12px;
    min-height: 400px;
    max-height: 600px;
    overflow-y: auto;
    white-space: pre-wrap;
}
</style>

<div class="log-container">
    <div class="log-header">
        <span class="log-title">VLESS Filter - Логи</span>
        <div class="log-actions">
            <button id="refreshBtn" class="log-btn">🔄 Обновить</button>
            <button id="clearBtn" class="log-btn">🗑️ Очистить</button>
        </div>
    </div>
    
    <pre id="logContent" class="log-content">Загрузка логов...</pre>
</div>

<script type="text/javascript">
(function() {
    const logContent = document.getElementById('logContent');
    const refreshBtn = document.getElementById('refreshBtn');
    const clearBtn = document.getElementById('clearBtn');
    
    function fetchLog() {
        XHR.get('<%=luci.dispatcher.build_url("admin/services/vlessfilter/api")%>?action=get_log', null, function(x, data) {
            if (data && data.log) {
                logContent.textContent = data.log || 'Логов пока нет';
            }
        });
    }
    
    refreshBtn.addEventListener('click', fetchLog);
    
    clearBtn.addEventListener('click', function() {
        if (confirm('Очистить все логи?')) {
            XHR.get('<%=luci.dispatcher.build_url("admin/services/vlessfilter/api")%>?action=clear_log', null, function() {
                logContent.textContent = 'Логи очищены';
            });
        }
    });
    
    fetchLog();
    setInterval(fetchLog, 5000);
})();
</script>
<%+footer%>
EOF

    print_step "Страница логов создана"
}

# Создание cron задачи
create_cron_job() {
    print_step "Создание задания cron..."
    
    local cron_cmd="0 */6 * * * /usr/bin/vlessfilter.sh >/dev/null 2>&1"
    
    if command -v crontab >/dev/null 2>&1; then
        (crontab -l 2>/dev/null | grep -v "vlessfilter.sh"; echo "$cron_cmd") | crontab -
        print_step "Задание cron добавлено"
    else
        print_warning "crontab не найден, пропускаем настройку cron"
    fi
}

# Очистка и перезапуск
cleanup() {
    print_step "Очистка и перезапуск сервисов..."
    
    rm -f /tmp/luci-* 2>/dev/null
    rm -f /var/run/luci-indexcache 2>/dev/null
    
    if [ -f /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart
    fi
    
    print_step "Очистка завершена"
}

# Финальное сообщение
show_finish() {
    echo ""
    echo "======================================================"
    echo "  ✅ VLESS Filter LuCI Service Установлен!"
    echo "======================================================"
    echo ""
    echo "📁 Лог установки: $LOG_FILE"
    echo ""
    echo "🌐 LuCI интерфейс: Services → VLESS Filter"
    echo ""
    echo "✨ ОСОБЕННОСТИ ФИНАЛЬНОЙ ВЕРСИИ:"
    echo "   • Полностью на русском языке"
    echo "   • Кнопка принудительной остановки"
    echo "   • Проверка через sing-box (без ping)"
    echo "   • Отбор лучших из каждого источника"
    echo "   • Автоматическое обновление podkop"
    echo ""
    echo "🛠️  Команды:"
    echo "   /usr/bin/vlessfilter.sh force - Запустить проверку"
    echo "   /usr/bin/vlessfilter.sh stop  - Остановить проверку"
    echo "   tail -f /tmp/vlessfilter.log  - Смотреть логи"
    echo "   cat /tmp/vlessfilter_results.txt - Результаты"
    echo ""
    echo "======================================================"
}

# Главная функция
main() {
    print_step "Начало установки VLESS Filter (русская версия)..."
    
    check_openwrt
    create_directories
    install_dependencies
    create_uci_config
    create_main_script
    create_luci_controller
    create_general_cbi
    create_sources_cbi
    create_run_button_template
    create_status_view
    create_logs_view
    create_cron_job
    cleanup
    
    print_success "Установка завершена!"
    show_finish
}

main "$@"
