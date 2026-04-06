#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
CONFIG_FILE="/etc/web-stack.conf"
LIB_FILE="/usr/local/lib/web-stack.sh"

trap 'echo; echo "Erro na linha ${LINENO}: ${BASH_COMMAND}" >&2' ERR

show_help() {
  cat <<EOF
Uso:
  sudo ./${SCRIPT_NAME}

Descricao:
  Desinstala o ambiente PHP web-stack, removendo:
  - Contêineres Docker
  - Imagens Docker personalizadas
  - Configurações do Apache
  - Certificados SSL
  - Scripts e bibliotecas do sistema
  - Arquivo de configuração

Nota: Nao remove:
  - Docker e ferramentas do sistema
  - Diretórios de projetos (~/Projects/PHP)
  - Dados persistentes (~/Docker/web-stack/mysql, ~/Docker/web-stack/redis)
  - Entradas do /etc/hosts

Exemplo:
  sudo ./${SCRIPT_NAME}
EOF
}

validate_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Execute com sudo: sudo ./${SCRIPT_NAME}"
    exit 1
  fi
}

load_config() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Configuracao nao encontrada: ${CONFIG_FILE}"
    echo "O ambiente pode nao estar instalado."
    exit 1
  fi

  # shellcheck disable=SC1090
  . "${CONFIG_FILE}"
}

log() {
  echo
  echo "==> $1"
}

confirm_uninstall() {
  echo
  echo "ATENCAO: Voce esta prestes a desinstalar o ambiente web-stack."
  echo
  echo "Serao removidos:"
  echo "  - Contêineres Docker (php74, php83, php84, mysql, redis)"
  echo "  - Imagens Docker personalizadas"
  echo "  - Configuracoes do Apache"
  echo "  - Certificados SSL"
  echo "  - Scripts em /usr/local/bin"
  echo "  - Biblioteca em /usr/local/lib"
  echo "  - Arquivo de configuracao"
  echo
  echo "NAO serao removidos:"
  echo "  - Diretorio de projetos: ${PHP_ROOT}"
  echo "  - Dados do MySQL: ${MYSQL_DATA_DIR}"
  echo "  - Dados do Redis: ${REDIS_DATA_DIR}"
  echo "  - Diretorio do Docker: ${DOCKER_ROOT}"
  echo
  read -p "Deseja continuar? (s/n): " -r response
  if [[ ! "${response}" =~ ^[sS]$ ]]; then
    echo "Desinstalacao cancelada."
    exit 0
  fi
}

remove_containers() {
  log "Removendo contêineres Docker"
  cd "${DOCKER_ROOT}" || return

  if [[ -f "docker-compose.yml" ]]; then
    docker compose down --remove-orphans >/dev/null 2>&1 || true
  fi

  # Remove contêineres restantes manualmente
  docker rm -f php-env-mysql >/dev/null 2>&1 || true
  docker rm -f php-env-redis >/dev/null 2>&1 || true
  docker rm -f php74-fpm >/dev/null 2>&1 || true
  docker rm -f php83-fpm >/dev/null 2>&1 || true
  docker rm -f php84-fpm >/dev/null 2>&1 || true
}

remove_docker_images() {
  log "Removendo imagens Docker personalizadas"

  docker rmi php-web-stack-php74 >/dev/null 2>&1 || true
  docker rmi php-web-stack-php83 >/dev/null 2>&1 || true
  docker rmi php-web-stack-php84 >/dev/null 2>&1 || true
}

remove_apache_config() {
  log "Removendo configuracoes do Apache"

  a2dissite php-localhost.conf >/dev/null 2>&1 || true
  a2dissite php-localhost-ssl.conf >/dev/null 2>&1 || true
  a2dissite '*.conf' 2>/dev/null | grep -E '(crm|test|\.test)' || true

  rm -f "${LOCALHOST_HTTP_VHOST}"
  rm -f "${LOCALHOST_SSL_VHOST}"

  # Disable modules se nao forem utilizadas
  a2dismod proxy proxy_fcgi >/dev/null 2>&1 || true

  apache2ctl configtest >/dev/null 2>&1
  systemctl reload apache2 >/dev/null 2>&1 || true
}

remove_certificates() {
  log "Removendo certificados SSL"

  if [[ -d "${CERTS_DIR}" ]]; then
    rm -rf "${CERTS_DIR}"
  fi
}

remove_scripts() {
  log "Removendo scripts do sistema"

  rm -f /usr/local/bin/web-stack
  rm -f /usr/local/bin/web-stack-uninstall
  rm -f /usr/local/bin/php-env
}

remove_library() {
  log "Removendo biblioteca compartilhada"

  rm -f "${LIB_FILE}"
}

remove_config() {
  log "Removendo arquivo de configuracao"

  rm -f "${CONFIG_FILE}"
}

cleanup_vhost_configs() {
  log "Limpando configuracoes de VirtualHosts"

  # Remove apenas arquivos de vhost personalizados, nao localhost
  find /etc/apache2/sites-available -type f -name '*.conf' 2>/dev/null | while read -r file; do
    if grep -q 'php-local-env' "${file}" && [[ "${file}" != *"localhost"* ]]; then
      a2dissite "$(basename "${file}")" >/dev/null 2>&1 || true
      rm -f "${file}"
    fi
  done
}

main() {
  validate_root

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
  fi

  load_config
  confirm_uninstall

  remove_containers
  remove_docker_images
  cleanup_vhost_configs
  remove_apache_config
  remove_certificates
  remove_scripts
  remove_library
  remove_config

  cat <<EOF

Desinstalacao concluida.

Arquivos/diretorios preservados:
- ${PHP_ROOT}
- ${MYSQL_DATA_DIR}
- ${REDIS_DATA_DIR}
- ${DOCKER_ROOT}/docker-compose.yml

Para remover completamente:
  rm -rf ${DOCKER_ROOT}
  rm -rf ${PROJECTS_ROOT}

EOF
}

main "$@"

