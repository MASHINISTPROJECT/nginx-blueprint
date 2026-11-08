#!/usr/bin/env bash
# Ensure Unix line endings
sed -i 's/\r$//' "$0"
find modules -type f -name "*.sh" -exec sed -i 's/\r$//' {} + 2>/dev/null || true

set -euo pipefail
trap 'echo -e "${RED}[Orchestrator] Error on line $LINENO${NC}"' ERR

# Enable nullglob so non-matching globs expand to empty
shopt -s nullglob

# Color definitions
BLUE='\033[0;34m'; BOLD_BLUE='\033[1;34m'
WHITE='\033[0;37m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; RED='\033[0;31m'
NC='\033[0m'

# Compact header function
header() {
  echo -e "${BOLD_BLUE}➜ $1${NC}"
}

# Start orchestration
echo -e "\n${BOLD_BLUE}Запуск модулей...${NC}"

# Helper to test enabled status: true or 1
is_enabled() { [[ "$1" =~ ^(true|1)$ ]]; }

# 0) PHP extension selection
PHP_VERSION="${PHP_VERSION:-8.4}"
PHP_DISABLED_EXTENSIONS="${PHP_DISABLED_EXTENSIONS:-}"
PHP_CONF_SOURCE="${PHP_CONF_SOURCE:-/etc/php/${PHP_VERSION}}"
PHP_CONF_USER="${PWD}/php/conf.d"
PHP_CONF_ACTIVE="${PWD}/php/conf.d-active"

disabled_list="${PHP_DISABLED_EXTENSIONS//,/ }"
disabled_list="${disabled_list,,}"
user_inis=("$PHP_CONF_USER"/*.ini)

if [[ -n "${disabled_list// /}" || ${#user_inis[@]} -gt 0 ]]; then
  header "Настройка PHP"
  rm -rf "$PHP_CONF_ACTIVE"
  mkdir -p "$PHP_CONF_ACTIVE"

  linked=0
  skipped=" "
  
  for ini in "$PHP_CONF_SOURCE"/fpm/conf.d/*.ini "$PHP_CONF_SOURCE"/cli/conf.d/*.ini; do
    name=$(basename "$ini")
    [[ -e "$PHP_CONF_ACTIVE/$name" ]] && continue
    ext="${name#*-}"; ext="${ext%.ini}"; ext="${ext,,}"
    if [[ " ${disabled_list} " == *" ${ext} "* ]]; then
      skipped+="${ext} "
      continue
    fi
    ln -s "$ini" "$PHP_CONF_ACTIVE/$name"
    linked=$((linked + 1))
  done

  if (( linked == 0 )); then
    echo -e "${YELLOW}⚠ Не найдены конфиги расширений, используем дефолтные.${NC}"
    rm -rf "$PHP_CONF_ACTIVE"
  else
    for ext in $disabled_list; do
      if [[ "$skipped" == *" ${ext} "* ]]; then
        echo -e "${WHITE}  - Отключено: ${ext}${NC}"
      else
        echo -e "${YELLOW}  - Расширение '${ext}' не загружено образом.${NC}"
      fi
    done

    for ini in "${user_inis[@]}"; do
      rm -f "$PHP_CONF_ACTIVE/$(basename "$ini")"
      cp "$ini" "$PHP_CONF_ACTIVE/"
      echo -e "${WHITE}  - Кастомный конфиг: $(basename "$ini")${NC}"
    done

    export PHP_INI_SCAN_DIR="$PHP_CONF_ACTIVE"
  fi
else
  rm -rf "$PHP_CONF_ACTIVE"
fi

# 1) Logcleaner
LOGCLEANER_STATUS="${LOGCLEANER_STATUS:-false}"
if is_enabled "$LOGCLEANER_STATUS"; then
  header "Очистка логов"
  modules/logcleaner/start.sh
fi

# 2) Auto-update
AUTOUPDATE_STATUS="${AUTOUPDATE_STATUS:-true}"
if is_enabled "$AUTOUPDATE_STATUS" && [[ -f "modules/autoupdate/start.sh" ]]; then
  header "Проверка обновлений"
  modules/autoupdate/start.sh
fi

# 3) Git
GIT_STATUS="${GIT_STATUS:-false}"
if is_enabled "$GIT_STATUS" && [[ -x "modules/git/start.sh" ]]; then
  header "Обновление кода (Git)"
  modules/git/start.sh
fi

# 4) Other modules
for module_dir in modules/*/; do
  module_name=$(basename "$module_dir")
  [[ "$module_name" =~ ^(autoupdate|logcleaner|git|nginx)$ ]] && continue
  start_script="${module_dir}start.sh"
  status_var="${module_name^^}_STATUS"
  status="${!status_var:-false}"

  if ! is_enabled "$status"; then
    continue
  fi

  if [[ -x "$start_script" ]]; then
    header "Запуск модуля: ${module_name}"
    "$start_script"
  fi
done

# 5) Nginx
NGINX_STATUS="${NGINX_STATUS:-true}"
if is_enabled "$NGINX_STATUS"; then
  header "Запуск Nginx и PHP-FPM"
  
  # 👇 ПОДСТАНОВКА ПОРТА
  if [ -f "nginx/nginx.conf" ]; then
    sed -i "s/listen 80;/listen ${SERVER_PORT};/g" nginx/nginx.conf
    sed -i "s/listen \${SERVER_PORT};/listen ${SERVER_PORT};/g" nginx/nginx.conf
  fi
  
  if [ -d "nginx/conf.d" ]; then
    find nginx/conf.d -type f -name "*.conf" -exec sed -i "s/listen 80;/listen ${SERVER_PORT};/g" {} +
    find nginx/conf.d -type f -name "*.conf" -exec sed -i "s/listen \${SERVER_PORT};/listen ${SERVER_PORT};/g" {} +
  fi
  
  if [ -f "nginx/sites-enabled/default" ]; then
    sed -i "s/listen 80;/listen ${SERVER_PORT};/g" nginx/sites-enabled/default
    sed -i "s/listen \${SERVER_PORT};/listen ${SERVER_PORT};/g" nginx/sites-enabled/default
  fi

  modules/nginx/start.sh
  exit 0
fi

echo -e "\n${GREEN}✅ Все модули успешно запущены.${NC}\n"
