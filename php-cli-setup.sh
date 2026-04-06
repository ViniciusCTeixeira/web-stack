#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HOME}/.php-cli"
CONFIG_FILE="${CONFIG_DIR}/version"
DEFAULT_VERSION="${1:-php84}"

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Erro: docker não encontrado."
    exit 1
  fi
}

ensure_config() {
  mkdir -p "$CONFIG_DIR"
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "$DEFAULT_VERSION" > "$CONFIG_FILE"
  fi
}

install_php_wrapper() {
  sudo tee /usr/local/bin/php >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${HOME}/.php-cli/version"

if [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$(dirname "$CONFIG_FILE")"
  echo "php84" > "$CONFIG_FILE"
fi

PHP_CONTAINER="$(cat "$CONFIG_FILE")"

if [ -z "${PHP_CONTAINER:-}" ]; then
  echo "Nenhum container PHP configurado."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker não encontrado."
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$PHP_CONTAINER"; then
  if docker ps -a --format '{{.Names}}' | grep -qx "$PHP_CONTAINER"; then
    echo "Container '$PHP_CONTAINER' existe mas não está rodando."
    echo "Inicie ele antes de usar o comando php."
    exit 1
  else
    echo "Container '$PHP_CONTAINER' não existe."
    exit 1
  fi
fi

USER_ID="$(id -u)"
GROUP_ID="$(id -g)"
WORKDIR="$(pwd)"

exec docker exec \
  -u "${USER_ID}:${GROUP_ID}" \
  -w "$WORKDIR" \
  "$PHP_CONTAINER" \
  php "$@"
EOF

  sudo chmod +x /usr/local/bin/php
}

install_phpv_wrapper() {
  sudo tee /usr/local/bin/phpv >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HOME}/.php-cli"
CONFIG_FILE="${CONFIG_DIR}/version"

mkdir -p "$CONFIG_DIR"

case "${1:-}" in
  current)
    cat "$CONFIG_FILE" 2>/dev/null || echo "php84"
    ;;
  use)
    if [ -z "${2:-}" ]; then
      echo "Uso: phpv use <container>"
      exit 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
      echo "Docker não encontrado."
      exit 1
    fi

    if ! docker ps -a --format '{{.Names}}' | grep -qx "$2"; then
      echo "Container '$2' não existe."
      exit 1
    fi

    echo "$2" > "$CONFIG_FILE"
    echo "Agora o comando php usa: $2"
    ;;
  list)
    docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
    ;;
  *)
    echo "Uso:"
    echo "  phpv current"
    echo "  phpv use php84"
    echo "  phpv list"
    exit 1
    ;;
esac
EOF

  sudo chmod +x /usr/local/bin/phpv
}

set_initial_version() {
  if docker ps -a --format '{{.Names}}' | grep -qx "$DEFAULT_VERSION"; then
    echo "$DEFAULT_VERSION" > "$CONFIG_FILE"
  fi
}

main() {
  require_docker
  ensure_config
  install_php_wrapper
  install_phpv_wrapper
  set_initial_version

  echo "Instalação concluída."
  echo "Versão atual: $(cat "$CONFIG_FILE")"
  echo
  echo "Comandos disponíveis:"
  echo "  php -v"
  echo "  phpv current"
  echo "  phpv use php84"
  echo "  phpv use php83"
  echo "  phpv list"
}

main