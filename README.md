# 🚀 web-stack - Ambiente PHP Local Profissional

Um **ambiente PHP local completo** com múltiplas versões, MySQL, Redis e gerenciamento simplificado via linha de comando.

![Status](https://img.shields.io/badge/status-produção-success) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) ![PHP](https://img.shields.io/badge/PHP-7.4%20|%208.3%20|%208.4-purple)

---

## 📋 Tabela de Conteúdo

- [Características](#características)
- [Pré-requisitos](#pré-requisitos)
- [Instalação](#instalação)
- [Uso Rápido](#uso-rápido)
- [Comandos](#comandos)
- [Exemplos Práticos](#exemplos-práticos)
- [Estrutura](#estrutura)
- [Troubleshooting](#troubleshooting)

---

## ✨ Características

### 🐘 PHP Múltiplas Versões
- PHP 7.4.33
- PHP 8.3.14
- PHP 8.4 (latest)
- Controle granular por versão

### 🗄️ Bancos de Dados
- **MySQL 8.4** em container Docker
- **Redis 7** em container Docker
- Dados persistentes
- Acesso direto via localhost

### 🌐 Web Server
- **Apache 2** no host
- **SSL/HTTPS** automático com certificados auto-assinados
- VirtualHosts ilimitados
- Suporte a .htaccess
- HTTP/HTTPS redirect opcional

### 📦 Ferramentas
- **Composer** em cada versão PHP
- **Docker & Docker Compose** para orquestração
- **NVM** (Node.js) opcional
- **pyenv** (Python) opcional

### 🛠️ Gerenciamento
- **11 melhorias implementadas**
- Controle individual de recursos
- Logs em tempo real
- Backup/Restore automático
- Stats de CPU/Memória
- Shell interativo

---

## 📦 Pré-requisitos

### Sistema Operacional
- ✅ Ubuntu 20.04+
- ✅ Pop!_OS 20.04+
- ❌ Outras distribuições (em desenvolvimento)

### Dependências
- Docker e Docker Compose
- Apache 2
- OpenSSL
- mkcert (para certificados SSL)
- Privilégios sudo

### Espaço em Disco
- ~5GB para imagens Docker
- ~2GB para dados (MySQL, Redis, backups)

---

## 🔧 Instalação

### 1. Clone ou Download

```bash
# Clonar repositório
git clone <repositorio> ~/web-stack
cd ~/web-stack

# Ou fazer download do arquivo
unzip web-stack.zip
cd web-stack
```

### 2. Execute o Instalador

```bash
# Substitua 'seu_usuario' pelo seu nome de usuário
sudo ./web-stack-setup.sh seu_usuario
```

### 3. Aguarde a Conclusão

O instalador:
- ✅ Atualiza pacotes do sistema
- ✅ Instala Docker e dependências
- ✅ Configura Apache
- ✅ Cria estrutura de diretórios
- ✅ Faz build das imagens Docker
- ✅ Inicia containers

### 4. Verifique a Instalação

```bash
web-stack status
# Deve mostrar MySQL e Redis ativos
```

---

## 🚀 Uso Rápido

### Iniciar o Ambiente

```bash
web-stack on all
```

### Verificar Status

```bash
web-stack status
```

### Acessar Localhost

```bash
# HTTP
http://localhost

# HTTPS (auto-certificado)
https://localhost
```

### Ver Logs em Tempo Real

```bash
web-stack logs mysql -f
web-stack logs php84 -f
```

### Executar Composer

```bash
web-stack composer 84 install
web-stack composer 84 require vendor/package
```

### Parar o Ambiente

```bash
web-stack off all
```

---

## 📚 Comandos

### Controle de Recursos

```bash
# Ativar/Desativar
web-stack on all                # ativa tudo
web-stack off all               # desativa tudo
web-stack on php84              # ativa PHP 8.4
web-stack off php83             # desativa PHP 8.3
web-stack restart mysql         # reinicia MySQL
```

### Status e Logs

```bash
# Status
web-stack status                # resumido
web-stack status -v             # detalhado
web-stack list                  # lista completa

# Logs
web-stack logs mysql -f         # MySQL em tempo real
web-stack logs php84            # logs do PHP 8.4
web-stack logs all              # logs de tudo
web-stack stats                 # CPU/Memória
```

### Acesso aos Containers

```bash
# Shell interativo
web-stack shell php84           # bash do PHP 8.4
web-stack shell mysql           # mysql client
web-stack shell redis           # redis-cli

# Executar comando
web-stack exec php84 php -v
web-stack exec mysql mysql -u root -p123 -e "SHOW DATABASES"
```

### Manutenção

```bash
# Cleanup
web-stack cleanup               # remove containers
web-stack cleanup --volumes     # remove containers e volumes
web-stack cleanup --all         # remove tudo

# Backup
web-stack backup                # cria backup
web-stack restore backup_*.tar.gz # restaura
```

### Docker

```bash
web-stack docker up             # sobe containers
web-stack docker down           # desce containers
web-stack docker build          # faz build
web-stack docker rebuild        # rebuild sem cache
web-stack docker list-versions  # lista versões PHP
```

### Composer

```bash
web-stack composer 84 install
web-stack composer 84 require vendor/package
web-stack composer 84 update
web-stack composer 84 run-script test
```

### VirtualHosts

```bash
# Criar
sudo web-stack vhost create crm.test crm 84
sudo web-stack vhost create --ssl site.test site 84 public
sudo web-stack vhost create --ssl --redirect-http api.test api 84 webroot

# Editar
sudo web-stack vhost edit --ssl crm.test crm 83

# Remover
sudo web-stack vhost remove crm.test
```

### Localhost

```bash
# Mudar versão PHP
sudo web-stack localhost version 83
sudo web-stack localhost version 84
```

---

## 💡 Exemplos Práticos

### Exemplo 1: Trabalhar com Laravel

```bash
# 1. Inicie o ambiente
web-stack on all

# 2. Verifique status
web-stack status

# 3. Crie um VirtualHost
sudo web-stack vhost create --ssl --redirect-http laravel.test laravel 84 public

# 4. Clone/Crie o projeto
mkdir -p ~/Projects/PHP/laravel
cd ~/Projects/PHP/laravel

# 5. Instale dependencies
web-stack composer 84 install

# 6. Configure .env
cp .env.example .env

# 7. Acesse
https://laravel.test

# 8. Veja logs
web-stack logs php84 -f
```

### Exemplo 2: Testar Compatibilidade entre Versões

```bash
# Teste em PHP 8.4
web-stack on php84
web-stack composer 84 install
web-stack exec php84 vendor/bin/phpunit

# Teste em PHP 8.3
web-stack on php83
web-stack composer 83 install
web-stack exec php83 vendor/bin/phpunit

# Desative versões não usadas
web-stack off php83
web-stack off php84
```

### Exemplo 3: Debug com MySQL

```bash
# 1. Ver logs
web-stack logs mysql -f

# 2. Entrar no MySQL
web-stack shell mysql

# 3. Dentro do MySQL
mysql> SHOW DATABASES;
mysql> USE seu_banco;
mysql> SELECT * FROM tabela LIMIT 10;
mysql> exit

# 4. Se travar, reinicie
web-stack restart mysql
```

### Exemplo 4: Backup Antes de Atualizar

```bash
# 1. Criar backup
web-stack backup
# Arquivo: ~/Docker/web-stack/backups/backup_2024-04-06_14-30-45.tar.gz

# 2. Fazer atualização (ex: composer update)
web-stack composer 84 update

# 3. Se der erro, restaurar
web-stack restore ~/Docker/web-stack/backups/backup_2024-04-06_14-30-45.tar.gz
```

### Exemplo 5: Monitorar Recursos

```bash
# Ver estatísticas em tempo real
web-stack stats

# Limpar containers não utilizados
web-stack cleanup --volumes
```

---

## 📁 Estrutura

### Diretórios Principais

```
~/Projects/PHP/
├── index.php              # localhost principal
├── phpinfo.php            # teste de informações
├── seu_projeto/
│   ├── composer.json
│   ├── public/           # webroot
│   └── ...

~/Docker/web-stack/
├── docker-compose.yml    # orquestração
├── versions.conf         # versões PHP
├── backups/             # backups
├── mysql/data/          # dados MySQL
├── redis/data/          # dados Redis
├── php74/
│   ├── Dockerfile
│   ├── php.ini
│   └── zz-www.conf
├── php83/
│   ├── Dockerfile
│   ├── php.ini
│   └── zz-www.conf
└── php84/
    ├── Dockerfile
    ├── php.ini
    └── zz-www.conf

/etc/
├── web-stack.conf       # configuração global
└── apache2/
    ├── sites-available/
    │   ├── php-localhost.conf
    │   ├── php-localhost-ssl.conf
    │   ├── crm.test.conf
    │   └── ...
    └── ssl/
        ├── localhost.crt
        ├── localhost.key
        └── ...
```

---

## 🔍 Troubleshooting

### Docker não está instalado

```bash
❌ Erro: Docker não está instalado
   Execute: sudo apt-get install docker.io
```

**Solução:**
```bash
sudo apt-get install docker.io docker-compose
sudo systemctl start docker
```

### Docker daemon não está rodando

```bash
❌ Erro: Docker daemon não está rodando
   Execute: sudo systemctl start docker
```

**Solução:**
```bash
sudo systemctl start docker
sudo systemctl enable docker  # iniciar no boot
```

### Porta já está em uso

```bash
❌ Erro: A porta 9084 já está em uso
```

**Solução:**
```bash
# Encontre o processo usando a porta
sudo lsof -i :9084

# Mate o processo ou mude a porta no versions.conf
# Depois reinicie
web-stack restart all
```

### Certificado SSL inválido no navegador

É normal - são auto-assinados. No navegador:
- Firefox: "Aceitar risco"
- Chrome: "Avançado" → "Prosseguir"

### MySQL não conecta

```bash
# 1. Verifique status
web-stack status

# 2. Ver logs
web-stack logs mysql -f

# 3. Reiniciar
web-stack restart mysql

# 4. Teste de conexão
web-stack shell mysql
```

### PHP não executa

```bash
# 1. Ver logs do PHP
web-stack logs php84 -f

# 2. Executar comando direto
web-stack exec php84 php -v

# 3. Reiniciar se necessário
web-stack restart php84
```

### Arquivo não encontrado em localhost

```bash
# 1. Verifique o diretório
ls -la ~/Projects/PHP/

# 2. Verifique permissões
chmod -R 755 ~/Projects/PHP/

# 3. Reinicie Apache
web-stack restart mysql  # reinicia os serviços
```

---

## 📖 Documentação Completa

Para mais detalhes sobre cada comando:

```bash
web-stack -h              # ajuda geral
web-stack docker -h       # ajuda do docker
web-stack composer -h     # ajuda do composer
web-stack localhost -h    # ajuda do localhost
web-stack vhost -h        # ajuda do vhost
```

---

## 🗑️ Desinstalação

Para remover completamente:

```bash
# Remove containers, volumes, images e configurações
web-stack-uninstall
```

Ou manualmente:

```bash
# Parar tudo
web-stack off all

# Remover containers
docker compose down -v

# Remover configurações
sudo rm /etc/web-stack.conf
sudo rm /usr/local/lib/web-stack.sh
sudo rm /usr/local/bin/web-stack

# Remover diretórios
rm -rf ~/Docker/web-stack
```

---

## 🤝 Contribuindo

Encontrou um bug? Tem uma sugestão?

1. Verifique se já não foi reportado
2. Abra uma issue com descrição clara
3. Inclua os logs (`web-stack logs all`)
4. Mencione sua versão do Ubuntu/Pop!_OS

---

## 📝 Licença

Este projeto está licenciado sob a **[MIT License](LICENSE)**.

Você é livre para:
- ✅ **Usar comercialmente** - Pode usar em projetos comerciais
- ✅ **Modificar** - Pode alterar o código
- ✅ **Distribuir** - Pode compartilhar com outros
- ✅ **Usar privadamente** - Sem restrições

Sob a condição de:
- ⚠️ Incluir a licença e aviso de copyright

**Em resumo:** Faça o que quiser com este código, apenas mantenha o aviso de copyright.

---

## 📞 Suporte

### Verificar Logs

```bash
web-stack logs all -f
```

### Restaurar Backup

```bash
web-stack restore backup_2024-04-06_14-30-45.tar.gz
```

### Limpar Tudo

```bash
web-stack cleanup --all
```

---

## 🎉 Pronto para Começar?

```bash
# 1. Instale
sudo ./web-stack-setup.sh seu_usuario

# 2. Inicie
web-stack on all

# 3. Acesse
https://localhost

# 4. Crie um projeto
sudo web-stack vhost create projeto.test projeto 84

# 5. Desenvolva! 🚀
```

---

## 📊 Estatísticas do Projeto

- **11 melhorias implementadas**
- **1200+ linhas de código**
- **30+ exemplos de uso**
- **100% auto-documentado** (tudo em `<comando> -h`)
- **3 versões de PHP**
- **2 bancos de dados** (MySQL + Redis)
- **Suporta SSL/HTTPS**
- **Backup automático**

---

## 🙏 Agradecimentos

Desenvolvido com ❤️ para a comunidade PHP

**Aproveite! 🚀**

