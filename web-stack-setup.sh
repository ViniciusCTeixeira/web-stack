#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/etc/web-stack.conf"
LIB_FILE="/usr/local/lib/web-stack.sh"
SUPPORT_LIB_SOURCE="${SCRIPT_DIR}/support/lib/web-stack.sh"
SUPPORT_BIN_DIR="${SCRIPT_DIR}/support/bin"
DEFAULT_PHP_VERSION="84"
LOCALHOST_HTTP_REDIRECT_TO_HTTPS=0
MYSQL_IMAGE="mysql:8.4"
MYSQL_PORT="3306"
MYSQL_ROOT_PASSWORD="123"
REDIS_IMAGE="redis:7"
REDIS_PORT="6379"
SKIP_UPGRADE=0
SKIP_NODE=0
SKIP_PYTHON=0

trap 'echo; echo "Erro na linha ${LINENO}: ${BASH_COMMAND}" >&2' ERR

show_help() {
  cat <<EOF
Uso:
  sudo ./${SCRIPT_NAME} [opcoes] SEU_USUARIO

Opcoes:
  --skip-upgrade    nao executa apt-get upgrade
  --skip-node       nao instala NVM
  --skip-python     nao instala pyenv
  --mysql-root-password SENHA
                    define a senha do usuario root do MySQL Docker
  --localhost-http-redirect
                    redireciona http://localhost para https://localhost
  -h, --help        mostra esta ajuda

O que instala/configura:
  - Apache central no host
  - Docker com PHP-FPM 7.4, 8.3 e 8.4
  - MySQL e Redis em containers Docker
  - localhost com HTTP e HTTPS, usando PHP 8.4 por padrao
  - pasta unica de projetos em ~/Projects/PHP
  - configuracao persistente em ${CONFIG_FILE}
  - comando unico web-stack para gerenciar Docker, Composer, localhost e VirtualHosts

Comandos criados:
  - web-stack
  - web-stack-uninstall

Exemplos de uso:
  web-stack -h
  web-stack docker up
  web-stack docker list-versions
  sudo web-stack docker version add 82 8.2-fpm
  web-stack composer 84 install
  sudo web-stack localhost version 83
  sudo web-stack vhost create crm.test crm 84
  sudo web-stack vhost create --ssl crm.test crm 84 public
  sudo web-stack vhost edit --ssl --redirect-http crm.test crm 84 public
  sudo web-stack vhost remove crm.test
  sudo web-stack-uninstall

Exemplo:
  sudo ./${SCRIPT_NAME} vinicius
EOF
}

parse_args() {
  local positional=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-upgrade)
        SKIP_UPGRADE=1
        ;;
      --skip-node)
        SKIP_NODE=1
        ;;
      --skip-python)
        SKIP_PYTHON=1
        ;;
      --localhost-http-redirect)
        LOCALHOST_HTTP_REDIRECT_TO_HTTPS=1
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      -*)
        echo "Opcao invalida: $1" >&2
        show_help
        exit 1
        ;;
      *)
        positional+=("$1")
        ;;
    esac
    shift
  done

  if [[ "${#positional[@]}" -ne 1 ]]; then
    show_help
    exit 1
  fi

  TARGET_USER="${positional[0]}"
}

validate_root_and_user() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Execute com sudo: sudo ./${SCRIPT_NAME} SEU_USUARIO"
    exit 1
  fi

  if ! id "${TARGET_USER}" >/dev/null 2>&1; then
    echo "Usuario '${TARGET_USER}' nao encontrado."
    exit 1
  fi
}

validate_os() {
  . /etc/os-release
  case "${ID}" in
    ubuntu|pop)
      ;;
    *)
      echo "Sistema nao suportado: ${PRETTY_NAME}. Use Ubuntu ou Pop!_OS."
      exit 1
      ;;
  esac
}

load_paths() {
  USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  if [[ -z "${USER_HOME}" || ! -d "${USER_HOME}" ]]; then
    echo "Nao foi possivel determinar o HOME do usuario '${TARGET_USER}'."
    exit 1
  fi

  PROJECTS_ROOT="${USER_HOME}/Projects"
  PHP_ROOT="${PROJECTS_ROOT}/PHP"
  DOCKER_ROOT="${USER_HOME}/Docker/web-stack"
  VERSIONS_FILE="${DOCKER_ROOT}/versions.conf"
  COMPOSE_FILE="${DOCKER_ROOT}/docker-compose.yml"
  MYSQL_DATA_DIR="${DOCKER_ROOT}/mysql/data"
  REDIS_DATA_DIR="${DOCKER_ROOT}/redis/data"
  CERTS_DIR="/etc/apache2/ssl"
  LOCALHOST_HTTP_VHOST="/etc/apache2/sites-available/php-localhost.conf"
  LOCALHOST_SSL_VHOST="/etc/apache2/sites-available/php-localhost-ssl.conf"
}

validate_support_files() {
  if [[ ! -f "${SUPPORT_LIB_SOURCE}" ]]; then
    echo "Biblioteca de suporte nao encontrada: ${SUPPORT_LIB_SOURCE}"
    exit 1
  fi

  if [[ ! -f "${SUPPORT_BIN_DIR}/web-stack" ]]; then
    echo "Comando de suporte nao encontrado: ${SUPPORT_BIN_DIR}/web-stack"
    exit 1
  fi
}

load_existing_defaults() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    local existing_default
    existing_default="$(grep -E '^DEFAULT_PHP_VERSION="[0-9]{2}"$' "${CONFIG_FILE}" | head -n1 | cut -d'"' -f2 || true)"
    if [[ -n "${existing_default}" ]]; then
      DEFAULT_PHP_VERSION="${existing_default}"
    fi

    local existing_redirect
    existing_redirect="$(grep -E '^LOCALHOST_HTTP_REDIRECT_TO_HTTPS="[01]"$' "${CONFIG_FILE}" | head -n1 | cut -d'"' -f2 || true)"
    if [[ -n "${existing_redirect}" ]]; then
      LOCALHOST_HTTP_REDIRECT_TO_HTTPS="${existing_redirect}"
    fi
  fi
}

log() {
  echo
  echo "==> $1"
}

run_as_user() {
  sudo -H -u "${TARGET_USER}" bash -lc "$1"
}

append_if_missing() {
  local file="$1"
  local line="$2"
  touch "$file"
  grep -Fqx "$line" "$file" || echo "$line" >> "$file"
}

write_config_file() {
  log "Gravando configuracao em ${CONFIG_FILE}"
  cat > "${CONFIG_FILE}" <<EOF
TARGET_USER="${TARGET_USER}"
USER_HOME="${USER_HOME}"
PROJECTS_ROOT="${PROJECTS_ROOT}"
PHP_ROOT="${PHP_ROOT}"
DOCKER_ROOT="${DOCKER_ROOT}"
VERSIONS_FILE="${VERSIONS_FILE}"
COMPOSE_FILE="${COMPOSE_FILE}"
MYSQL_DATA_DIR="${MYSQL_DATA_DIR}"
REDIS_DATA_DIR="${REDIS_DATA_DIR}"
MYSQL_IMAGE="${MYSQL_IMAGE}"
MYSQL_PORT="${MYSQL_PORT}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}"
REDIS_IMAGE="${REDIS_IMAGE}"
REDIS_PORT="${REDIS_PORT}"
CERTS_DIR="${CERTS_DIR}"
LIB_FILE="${LIB_FILE}"
DEFAULT_PHP_VERSION="${DEFAULT_PHP_VERSION}"
LOCALHOST_HTTP_REDIRECT_TO_HTTPS="${LOCALHOST_HTTP_REDIRECT_TO_HTTPS}"
LOCALHOST_HTTP_VHOST="${LOCALHOST_HTTP_VHOST}"
LOCALHOST_SSL_VHOST="${LOCALHOST_SSL_VHOST}"
EOF
  chmod 0644 "${CONFIG_FILE}"
}

install_base_packages() {
  log "Atualizando pacotes"
  apt-get update
  if [[ "${SKIP_UPGRADE}" -eq 0 ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  fi

  log "Instalando pacotes base"
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apache2 apache2-utils openssl mkcert libnss3-tools \
    curl wget git unzip zip jq ca-certificates gnupg lsb-release \
    software-properties-common apt-transport-https \
    build-essential make gcc pkg-config \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev \
    xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    libyaml-dev python3 python3-pip python3-venv pipx
}

install_docker() {
  log "Instalando Docker"
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi

  local codename
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"

  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable
EOF

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  usermod -aG docker "${TARGET_USER}"
  systemctl enable docker
  systemctl restart docker
}

configure_apache() {
  log "Configurando Apache"
  a2enmod proxy proxy_fcgi rewrite headers expires actions alias setenvif ssl >/dev/null
  systemctl enable apache2
  systemctl restart apache2
}

configure_services() {
  log "Ajustando servicos locais para evitar conflito com Docker"
  if systemctl list-unit-files 2>/dev/null | grep -q '^mysql\.service'; then
    systemctl stop mysql >/dev/null 2>&1 || true
    systemctl disable mysql >/dev/null 2>&1 || true
  fi

  if systemctl list-unit-files 2>/dev/null | grep -q '^redis-server\.service'; then
    systemctl stop redis-server >/dev/null 2>&1 || true
    systemctl disable redis-server >/dev/null 2>&1 || true
  fi
}

install_nvm() {
  if [[ "${SKIP_NODE}" -eq 1 ]]; then
    return
  fi

  log "Instalando NVM"
  run_as_user 'if [[ ! -d "$HOME/.nvm" ]]; then export PROFILE="$HOME/.bashrc"; curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash; fi'
  append_if_missing "${USER_HOME}/.bashrc" 'export NVM_DIR="$HOME/.nvm"'
  append_if_missing "${USER_HOME}/.bashrc" '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
  append_if_missing "${USER_HOME}/.bashrc" '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
}

install_pyenv() {
  if [[ "${SKIP_PYTHON}" -eq 1 ]]; then
    return
  fi

  log "Instalando pyenv"
  run_as_user 'if [[ ! -d "$HOME/.pyenv" ]]; then git clone https://github.com/pyenv/pyenv.git "$HOME/.pyenv"; fi'
  append_if_missing "${USER_HOME}/.bashrc" 'export PYENV_ROOT="$HOME/.pyenv"'
  append_if_missing "${USER_HOME}/.bashrc" '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
  append_if_missing "${USER_HOME}/.bashrc" 'eval "$(pyenv init - bash)"'
}

create_directories() {
  log "Criando diretorios"
  install -d -m 0755 "${CERTS_DIR}" /usr/local/lib
  run_as_user "mkdir -p '${PROJECTS_ROOT}' '${PHP_ROOT}' '${DOCKER_ROOT}' '${MYSQL_DATA_DIR}' '${REDIS_DATA_DIR}'"
}

ensure_versions_file() {
  touch "${VERSIONS_FILE}"
  chmod 0644 "${VERSIONS_FILE}"
}

ensure_version_entry() {
  local version="$1"
  local image_tag="$2"
  local port="$3"

  if ! grep -q "^${version}|" "${VERSIONS_FILE}"; then
    echo "${version}|${image_tag}|${port}" >> "${VERSIONS_FILE}"
  fi
}

sync_version_files() {
  log "Gerando arquivos das versoes PHP"
  # shellcheck disable=SC1090
  . "${SUPPORT_LIB_SOURCE}"
  while IFS='|' read -r version image_tag port; do
    [[ -z "${version}" ]] && continue
    local target_dir="${DOCKER_ROOT}/php${version}"
    write_php_runtime_files "${target_dir}" "${version}" "${image_tag}"
  done < "${VERSIONS_FILE}"
}

render_compose_file() {
  log "Gerando docker-compose.yml"
  # shellcheck disable=SC1090
  . "${SUPPORT_LIB_SOURCE}"
  render_compose_from_registry
}

create_localhost_files() {
  log "Criando arquivos iniciais do localhost"
  run_as_user "cat > '${PHP_ROOT}/index.php' <<'EOF'
<?php
echo '<h1>Ambiente PHP local</h1>';
echo '<p>DocumentRoot: ${PHP_ROOT}</p>';
echo '<p><a href=\"/phpinfo.php\">Abrir phpinfo()</a></p>';
EOF"

  run_as_user "cat > '${PHP_ROOT}/phpinfo.php' <<'EOF'
<?php
phpinfo();
EOF"
}

write_shared_library() {
  log "Instalando biblioteca compartilhada"
  install -m 0755 "${SUPPORT_LIB_SOURCE}" "${LIB_FILE}"
}

create_localhost_vhost() {
  log "Configurando localhost com HTTPS"
  local localhost_crt="${CERTS_DIR}/localhost.crt"
  local localhost_key="${CERTS_DIR}/localhost.key"
  local localhost_port

  localhost_port="$(awk -F'|' -v version="${DEFAULT_PHP_VERSION}" '$1 == version { print $3; exit }' "${VERSIONS_FILE}")"
  if [[ -z "${localhost_port}" ]]; then
    echo "Nao foi possivel definir a porta do localhost para PHP ${DEFAULT_PHP_VERSION}."
    exit 1
  fi

  # shellcheck disable=SC1091
  . "${LIB_FILE}"
  load_php_env
  generate_local_cert "localhost" "${localhost_crt}" "${localhost_key}"

  if [[ "${LOCALHOST_HTTP_REDIRECT_TO_HTTPS}" == "1" ]]; then
    cat > "${LOCALHOST_HTTP_VHOST}" <<EOF
<VirtualHost *:80>
    ServerName localhost
    Redirect permanent / https://localhost/
</VirtualHost>
EOF
  else
    cat > "${LOCALHOST_HTTP_VHOST}" <<EOF
<VirtualHost *:80>
    ServerName localhost
    ServerAdmin dev@local

    # Managed by php-local-env
    # php-local-env:docroot=${PHP_ROOT}
    # php-local-env:php_version=${DEFAULT_PHP_VERSION}
    # php-local-env:php_port=${localhost_port}
    # php-local-env:http_redirect=0

    DocumentRoot ${PHP_ROOT}

    <Directory ${PHP_ROOT}>
        AllowOverride All
        Require all granted
        Options FollowSymLinks Indexes
        DirectoryIndex index.php index.html
    </Directory>

    ProxyTimeout 300

    <FilesMatch \.php$>
        SetHandler "proxy:fcgi://127.0.0.1:${localhost_port}"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/localhost_error.log
    CustomLog \${APACHE_LOG_DIR}/localhost_access.log combined
</VirtualHost>
EOF
  fi

  cat > "${LOCALHOST_SSL_VHOST}" <<EOF
<VirtualHost *:443>
    ServerName localhost
    ServerAdmin dev@local

    # Managed by php-local-env
    # php-local-env:docroot=${PHP_ROOT}
    # php-local-env:php_version=${DEFAULT_PHP_VERSION}
    # php-local-env:php_port=${localhost_port}
    # php-local-env:http_redirect=${LOCALHOST_HTTP_REDIRECT_TO_HTTPS}

    DocumentRoot ${PHP_ROOT}

    <Directory ${PHP_ROOT}>
        AllowOverride All
        Require all granted
        Options FollowSymLinks Indexes
        DirectoryIndex index.php index.html
    </Directory>

    ProxyTimeout 300

    SSLEngine on
    SSLCertificateFile ${localhost_crt}
    SSLCertificateKeyFile ${localhost_key}

    <FilesMatch \.php$>
        SetHandler "proxy:fcgi://127.0.0.1:${localhost_port}"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/localhost_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/localhost_ssl_access.log combined
</VirtualHost>
EOF

  a2dissite 000-default.conf >/dev/null 2>&1 || true
  a2ensite "$(basename "${LOCALHOST_HTTP_VHOST}")" >/dev/null
  a2ensite "$(basename "${LOCALHOST_SSL_VHOST}")" >/dev/null
  apache2ctl configtest
  systemctl reload apache2
}

write_helper_scripts() {
  log "Instalando scripts auxiliares"
  install -d -m 0755 /usr/local/bin
  install -m 0755 "${SUPPORT_BIN_DIR}/web-stack" /usr/local/bin/web-stack
  rm -f /usr/local/bin/create-php-vhost
  rm -f /usr/local/bin/create-php-vhost-ssl
  rm -f /usr/local/bin/edit-php-vhost
  rm -f /usr/local/bin/remove-php-vhost
  rm -f /usr/local/bin/enable-php-vhost-ssl
  rm -f /usr/local/bin/php-composer
  rm -f /usr/local/bin/php-docker-up
  rm -f /usr/local/bin/php-docker-down
  rm -f /usr/local/bin/php-docker-build
  rm -f /usr/local/bin/php-docker-rebuild
  rm -f /usr/local/bin/php-docker-refresh-compose
  rm -f /usr/local/bin/php-docker-list-versions
  rm -f /usr/local/bin/php-docker-add-version
  rm -f /usr/local/bin/php-docker-edit-version
  rm -f /usr/local/bin/php-docker-remove-version
  rm -f /usr/local/bin/php-localhost-version
}

set_permissions() {
  chown -R "${TARGET_USER}:${TARGET_USER}" "${PROJECTS_ROOT}" "${DOCKER_ROOT}"
}

build_and_start_images() {
  log "Fazendo build das imagens PHP"
  cd "${DOCKER_ROOT}"
  docker compose build

  log "Subindo containers PHP"
  docker compose up -d
}

main() {
  parse_args "$@"
  validate_root_and_user
  validate_os
  load_paths
  validate_support_files
  load_existing_defaults
  install_base_packages
  install_docker
  configure_apache
  configure_services
  install_nvm
  install_pyenv
  create_directories
  write_config_file
  ensure_versions_file
  ensure_version_entry "74" "7.4.33-fpm" "9074"
  ensure_version_entry "83" "8.3.14-fpm" "9083"
  ensure_version_entry "84" "8.4-fpm" "9084"
  sync_version_files
  render_compose_file
  create_localhost_files
  write_shared_library
  create_localhost_vhost
  write_helper_scripts
  set_permissions
  build_and_start_images

  cat <<EOF

Instalacao concluida.

Estrutura:
- ${PHP_ROOT} -> seus projetos PHP
- ${DOCKER_ROOT} -> imagens, versoes e docker-compose.yml
- ${MYSQL_DATA_DIR} -> dados persistentes do MySQL
- ${REDIS_DATA_DIR} -> dados persistentes do Redis

Arquivos centrais:
- ${CONFIG_FILE}
- ${VERSIONS_FILE}
- ${COMPOSE_FILE}

Comando criado:
- php-env

Exemplos:
- web-stack -h
- web-stack docker up
- web-stack docker list-versions
- sudo web-stack docker version add 82 8.2-fpm
- web-stack composer 84 install
- sudo web-stack localhost version 83
- sudo web-stack vhost create crm.test crm 84
- sudo web-stack vhost create --ssl crm.test crm 84 public
- sudo web-stack vhost edit --ssl --redirect-http crm.test crm 84 public
- sudo web-stack vhost remove crm.test

Padroes:
- localhost usa PHP ${DEFAULT_PHP_VERSION}; redirect HTTP -> HTTPS e opcional
- create/edit de vhost usam raiz por padrao
- Composer roda dentro dos containers via web-stack composer
- MySQL Docker: localhost:${MYSQL_PORT} / usuario root / senha ${MYSQL_ROOT_PASSWORD}
- Redis Docker: localhost:${REDIS_PORT}
EOF
}

main "$@"
