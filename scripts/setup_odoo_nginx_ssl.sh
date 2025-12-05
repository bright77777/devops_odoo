#!/usr/bin/env bash
set -euo pipefail

# Script d'automatisation : création des fichiers SSL pour Nginx et config site Odoo
# Usage: exécuter en root
#        sudo ./setup_odoo_nginx_ssl.sh

# Colors
_green="\033[1;32m"; _red="\033[1;31m"; _reset="\033[0m"

echo -e "${_green}=== Script d'installation Nginx + certificat (Cloudflare Origin) pour Odoo ===${_reset}"
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${_red}Ce script doit être exécuté en root (sudo).${_reset}"
  exit 1
fi

read -r -p "Domaine (ex: odoo.fotetsa.com) : " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo -e "${_red}Domaine non fourni, sortie.${_reset}"
  exit 1
fi

SSL_DIR="/etc/nginx/ssl"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
SITE_CONF="${NGINX_SITES_AVAILABLE}/${DOMAIN}"

# Prepare dirs
mkdir -p "$SSL_DIR" "$NGINX_SITES_AVAILABLE" "$NGINX_SITES_ENABLED" "${SSL_DIR}/backup"

echo -e "${_green}Sauvegarde des fichiers existants (s'il y en a)...${_reset}"
timestamp=$(date +"%Y%m%d-%H%M%S")
for f in origin.crt origin.key; do
  if [ -f "${SSL_DIR}/${f}" ]; then
    cp -a "${SSL_DIR}/${f}" "${SSL_DIR}/backup/${f}.bak.${timestamp}"
    echo "  sauvegardé: ${SSL_DIR}/${f} -> ${SSL_DIR}/backup/${f}.bak.${timestamp}"
  fi
done

# ---------------------- CERTIFICAT --------------------------
echo
echo "➡️  Maintenant, colle ton CERTIFICAT (PEM)."
echo "    Quand tu as fini, appuie sur CTRL+D"
cat > "${SSL_DIR}/origin.crt"

# ----------------------- CLÉ PRIVÉE --------------------------
echo
echo "➡️  Maintenant, colle ta CLE PRIVEE (PEM)."
echo "    Quand tu as fini, appuie sur CTRL+D"
cat > "${SSL_DIR}/origin.key"

# Set permissions
chmod 600 "${SSL_DIR}/origin.key" || true
chmod 644 "${SSL_DIR}/origin.crt" || true

echo -e "${_green}Fichiers créés en : ${SSL_DIR}${_reset}"
echo " - ${SSL_DIR}/origin.crt"
echo " - ${SSL_DIR}/origin.key"

# ---------------- Vérification cert/key ----------------
check_cert() {
  okcert=0
  okkey=0
  if openssl x509 -in "${SSL_DIR}/origin.crt" -noout -text >/dev/null 2>&1; then okcert=1; fi
  if openssl pkey -in "${SSL_DIR}/origin.key" -check -noout >/dev/null 2>&1 || openssl rsa -in "${SSL_DIR}/origin.key" -check -noout >/dev/null 2>&1; then okkey=1; fi
  echo "${okcert}:${okkey}"
}

result=$(check_cert)
okcert=$(echo "$result" | cut -d: -f1)
okkey=$(echo "$result" | cut -d: -f2)

# Si fichiers inversés, auto-swap
first_line_cert=$(sed -n '1p' "${SSL_DIR}/origin.crt" || true)
first_line_key=$(sed -n '1p' "${SSL_DIR}/origin.key" || true)
if [[ "$first_line_cert" == "-----BEGIN PRIVATE KEY-----" && "$first_line_key" == "-----BEGIN CERTIFICATE-----" ]]; then
  echo -e "${_green}Fichiers inversés détectés. Permutation automatique...${_reset}"
  mv "${SSL_DIR}/origin.crt" "${SSL_DIR}/origin.crt.tmp"
  mv "${SSL_DIR}/origin.key" "${SSL_DIR}/origin.crt"
  mv "${SSL_DIR}/origin.crt.tmp" "${SSL_DIR}/origin.key"
  chmod 600 "${SSL_DIR}/origin.key"
  chmod 644 "${SSL_DIR}/origin.crt"
  result=$(check_cert)
  okcert=$(echo "$result" | cut -d: -f1)
  okkey=$(echo "$result" | cut -d: -f2)
fi

if [ "$okcert" -eq 1 ] && [ "$okkey" -eq 1 ]; then
  echo -e "${_green}Vérification SSL réussie : certificat et clé valides.${_reset}"
else
  echo -e "${_red}Vérification SSL échouée.${_reset}"
  read -r -p "Générer un certificat auto-signé temporaire ? (Y/n) : " genself
  if [[ "${genself,,}" == "n" || "${genself,,}" == "no" ]]; then
    echo "Abandon. Corrige les fichiers puis relance le script."
    exit 1
  fi
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${SSL_DIR}/origin.key" \
    -out "${SSL_DIR}/origin.crt" \
    -subj "/C=CM/ST=Douala/L=Douala/O=Fotetsa/OU=IT/CN=${DOMAIN}"
  chmod 600 "${SSL_DIR}/origin.key"
  chmod 644 "${SSL_DIR}/origin.crt"
  echo -e "${_green}Certificat auto-signé créé.${_reset}"
fi

# ---------------- Config Nginx ----------------
echo -e "${_green}Création du fichier Nginx pour ${DOMAIN}...${_reset}"

cat > "${SITE_CONF}" <<NCONF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/letsencrypt; }
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate ${SSL_DIR}/origin.crt;
    ssl_certificate_key ${SSL_DIR}/origin.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    real_ip_header CF-Connecting-IP;

    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log  /var/log/nginx/${DOMAIN}.error.log;

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_pass http://127.0.0.1:8069;

        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 900s;
    }

    location ~* /web/static/ {
        proxy_cache_valid 200 60m;
        proxy_pass http://127.0.0.1:8069;
    }

    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header Referrer-Policy "no-referrer-when-downgrade";
}
NCONF

ln -sf "${SITE_CONF}" "${NGINX_SITES_ENABLED}/${DOMAIN}"

echo -e "${_green}Test de la configuration Nginx...${_reset}"
if nginx -t; then
  systemctl reload nginx
  echo -e "${_green}Nginx rechargé avec succès.${_reset}"
else
  echo -e "${_red}Erreur Nginx. Consulte les logs.${_reset}"
  journalctl -xeu nginx.service --no-pager --since "2 minutes ago"
  exit 1
fi

echo
echo -e "${_green}--- Terminé ---${_reset}"
echo "Domaine: ${DOMAIN}"
echo "Cert: ${SSL_DIR}/origin.crt"
echo "Key:  ${SSL_DIR}/origin.key"
