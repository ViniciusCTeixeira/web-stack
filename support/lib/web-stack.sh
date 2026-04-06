#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="/etc/web-stack.conf"

load_php_env() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Arquivo de configuracao nao encontrado: ${CONFIG_FILE}" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  . "${CONFIG_FILE}"
}

version_exists() {
  local version="$1"
  grep -q "^${version}|" "${VERSIONS_FILE}"
}

require_version_exists() {
  local version="$1"
  if ! version_exists "${version}"; then
    echo "Versao ${version} nao encontrada em ${VERSIONS_FILE}." >&2
    exit 1
  fi
}

get_version_port() {
  local version="$1"
  awk -F'|' -v version="${version}" '$1 == version { print $3; exit }' "${VERSIONS_FILE}"
}

get_version_image() {
  local version="$1"
  awk -F'|' -v version="${version}" '$1 == version { print $2; exit }' "${VERSIONS_FILE}"
}

ensure_hosts_entry() {
  local domain="$1"
  if ! grep -qE "[[:space:]]${domain}$" /etc/hosts; then
    echo "127.0.0.1 ${domain}" >> /etc/hosts
  fi
}

generate_local_cert() {
  local domain="$1"
  local crt="$2"
  local key="$3"

  mkdir -p "$(dirname "${crt}")"

  if command -v mkcert >/dev/null 2>&1; then
    if [[ "${domain}" == "localhost" ]]; then
      mkcert -cert-file "${crt}" -key-file "${key}" localhost 127.0.0.1 ::1 >/dev/null 2>&1
    else
      mkcert -cert-file "${crt}" -key-file "${key}" "${domain}" >/dev/null 2>&1
    fi
    return
  fi

  local san_config
  san_config="$(mktemp)"
  cat > "${san_config}" <<CFG
[req]
distinguished_name=req_distinguished_name
x509_extensions=v3_req
prompt=no

[req_distinguished_name]
C=BR
ST=SaoPaulo
L=SaoPaulo
O=LocalDev
CN=${domain}

[v3_req]
subjectAltName=@alt_names

[alt_names]
DNS.1=${domain}
CFG

  if [[ "${domain}" == "localhost" ]]; then
    cat >> "${san_config}" <<'CFG'
DNS.2=localhost
IP.1=127.0.0.1
IP.2=::1
CFG
  fi

  openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
    -keyout "${key}" \
    -out "${crt}" \
    -config "${san_config}" \
    -extensions v3_req >/dev/null 2>&1

  rm -f "${san_config}"
}

render_compose_from_registry() {
  {
    echo "services:"
    cat <<CFG
  mysql:
    image: ${MYSQL_IMAGE}
    container_name: php-env-mysql
    restart: unless-stopped
    ports:
      - "${MYSQL_PORT}:3306"
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    volumes:
      - ${MYSQL_DATA_DIR}:/var/lib/mysql

  redis:
    image: ${REDIS_IMAGE}
    container_name: php-env-redis
    restart: unless-stopped
    ports:
      - "${REDIS_PORT}:6379"
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - ${REDIS_DATA_DIR}:/data

CFG
    while IFS='|' read -r version image_tag port; do
      [[ -z "${version}" ]] && continue
      cat <<CFG
  php${version}:
    build:
      context: ./php${version}
    container_name: php${version}-fpm
    restart: unless-stopped
    ports:
      - "${port}:9000"
    volumes:
      - ${PHP_ROOT}:${PHP_ROOT}
    extra_hosts:
      - "host.docker.internal:host-gateway"

CFG
    done < "${VERSIONS_FILE}"
  } > "${COMPOSE_FILE}"
}

set_default_php_version() {
  local version="$1"
  sed -i -E "s/^DEFAULT_PHP_VERSION=\"[0-9]{2}\"$/DEFAULT_PHP_VERSION=\"${version}\"/" "${CONFIG_FILE}"
  DEFAULT_PHP_VERSION="${version}"
}

write_php_ini_file() {
  local target_dir="$1"
  cat > "${target_dir}/php.ini" <<'EOF'
memory_limit=1024M
upload_max_filesize=64M
post_max_size=64M
max_execution_time=300
max_input_vars=5000
date.timezone=America/Sao_Paulo
display_errors=On
error_reporting=E_ALL
zend_extension=xdebug
xdebug.mode=debug,develop
xdebug.start_with_request=yes
xdebug.client_host=host.docker.internal
xdebug.client_port=9003
EOF
}

write_php_fpm_pool_file() {
  local target_dir="$1"
  cat > "${target_dir}/zz-www.conf" <<'EOF'
[www]
listen = 9000
listen.owner = www-data
listen.group = www-data
listen.mode = 0666
user = www-data
group = www-data
pm = dynamic
pm.max_children = 20
pm.start_servers = 3
pm.min_spare_servers = 2
pm.max_spare_servers = 5
clear_env = no
catch_workers_output = yes
EOF
}

write_php_dockerfile() {
  local target_dir="$1"
  local version="$2"
  local image_tag="$3"

  case "${version}" in
    74)
      cat > "${target_dir}/Dockerfile" <<EOF
FROM php:${image_tag}

RUN apt-get update && apt-get install -y \
    libicu-dev libzip-dev zlib1g-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    libxml2-dev libxslt1-dev libldap2-dev libc-client2007e-dev libkrb5-dev libgmp-dev \
    libonig-dev libsqlite3-dev libcurl4-openssl-dev libreadline-dev libssl-dev \
    unzip zip git curl && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure imap --with-kerberos --with-imap \
    && docker-php-ext-configure ldap \
    && docker-php-ext-install -j\$(nproc) \
        bcmath calendar curl dom exif fileinfo gd gettext gmp imap intl ldap mbstring \
        mysqli pdo pdo_mysql pdo_sqlite soap sockets sqlite3 xsl xml xmlreader xmlwriter zip opcache

RUN pecl install redis xdebug \
    && docker-php-ext-enable redis xdebug

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY php.ini /usr/local/etc/php/php.ini
COPY zz-www.conf /usr/local/etc/php-fpm.d/zz-www.conf

WORKDIR /var/www
EOF
      ;;
    80|81|82|83)
      cat > "${target_dir}/Dockerfile" <<EOF
FROM php:${image_tag}

RUN apt-get update && apt-get install -y \
    libicu-dev libzip-dev zlib1g-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    libxml2-dev libxslt1-dev libldap2-dev libc-client2007e-dev libkrb5-dev libgmp-dev \
    libsqlite3-dev libcurl4-openssl-dev libreadline-dev libssl-dev \
    unzip zip git curl && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure imap --with-kerberos --with-imap \
    && docker-php-ext-configure ldap \
    && docker-php-ext-install -j\$(nproc) \
        bcmath calendar curl dom exif fileinfo gd gettext gmp imap intl ldap mbstring \
        mysqli pdo pdo_mysql pdo_sqlite soap sockets sqlite3 xsl xml xmlreader xmlwriter zip opcache

RUN pecl install redis xdebug \
    && docker-php-ext-enable redis xdebug

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY php.ini /usr/local/etc/php/php.ini
COPY zz-www.conf /usr/local/etc/php-fpm.d/zz-www.conf

WORKDIR /var/www
EOF
      ;;
    *)
      cat > "${target_dir}/Dockerfile" <<EOF
FROM php:${image_tag}

RUN apt-get update && apt-get install -y \
    libicu-dev libzip-dev zlib1g-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    libxml2-dev libxslt1-dev libldap2-dev libgmp-dev libsqlite3-dev \
    libcurl4-openssl-dev libreadline-dev libssl-dev unzip zip git curl \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure ldap \
    && docker-php-ext-install -j\$(nproc) \
        bcmath calendar curl dom exif fileinfo gd gettext gmp intl ldap mbstring \
        mysqli pdo pdo_mysql pdo_sqlite soap sockets sqlite3 xsl xml xmlreader xmlwriter zip opcache

RUN pecl install redis xdebug \
    && docker-php-ext-enable redis xdebug

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY php.ini /usr/local/etc/php/php.ini
COPY zz-www.conf /usr/local/etc/php-fpm.d/zz-www.conf

WORKDIR /var/www
EOF
      ;;
  esac
}

write_php_runtime_files() {
  local target_dir="$1"
  local version="$2"
  local image_tag="$3"

  mkdir -p "${target_dir}"
  write_php_dockerfile "${target_dir}" "${version}" "${image_tag}"
  write_php_ini_file "${target_dir}"
  write_php_fpm_pool_file "${target_dir}"
}

