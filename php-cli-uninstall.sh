#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HOME}/.php-cli"

remove_file_if_exists() {
  local file="$1"

  if [ -e "$file" ] || [ -L "$file" ]; then
    sudo rm -f "$file"
    echo "Removido: $file"
  else
    echo "Não encontrado: $file"
  fi
}

main() {
  remove_file_if_exists /usr/local/bin/php
  remove_file_if_exists /usr/local/bin/phpv

  if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    echo "Removido: $CONFIG_DIR"
  else
    echo "Não encontrado: $CONFIG_DIR"
  fi

  echo "Desinstalação concluída."
}

main