#!/bin/bash
# lamp-install.sh - paigaldab LAMP keskkonna: Apache2 + PHP 8.x + MySQL Server 8.0
# Autor: Janre Puuorg, ITS25
# Kaivitada root kasutajana: ./lamp-install.sh

set -e
export DEBIAN_FRONTEND=noninteractive
# "su" (ilma "-") jatab /usr/sbin PATH-ist valja -> lisan selle (dpkg vajab ldconfig'i)
export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"

# ---------- Muutujad ----------
STUDENT="Janre Puuorg"
GROUP="ITS25"
MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:-Lamp2026Parool}"   # MySQL root parool (raportis ei kuvata)
MYSQL_APT_DEB="mysql-apt-config_0.8.40-1_all.deb"
MYSQL_APT_URL="https://dev.mysql.com/get/${MYSQL_APT_DEB}"

# Abifunktsioon: kas pakett on paigaldatud (dpkg-query)
pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# Skript peab tootama root oigustes
if [ "$(id -u)" -ne 0 ]; then
    echo "VIGA: kaivita skript root kasutajana."
    exit 1
fi

# ---------- 1. Abipaketid ----------
echo "==> Uuendan paketiloendit..."
apt-get update -q

for p in wget ca-certificates gnupg debconf-utils; do
    if pkg_installed "$p"; then
        echo "$p on juba paigaldatud."
    else
        echo "Paigaldan abipaketi $p..."
        apt-get install -y -q "$p"
    fi
done

# ---------- 2. MySQL Server 8.0 ----------
echo "==> MySQL Server 8.0 kontroll..."
if (pkg_installed mysql-community-server || pkg_installed mysql-server) \
   && mysql --version 2>/dev/null | grep -q " 8\.0\."; then
    echo "MySQL 8.0 on juba paigaldatud."
else
    echo "MySQL 8.0 puudub - paigaldan..."

    # Vastused paigaldusel kusitavatele kusimustele (mitteinteraktiivne paigaldus)
    debconf-set-selections <<EOF
mysql-apt-config mysql-apt-config/select-server select mysql-8.0
mysql-apt-config mysql-apt-config/select-tools select Disabled
mysql-apt-config mysql-apt-config/select-preview select Disabled
mysql-apt-config mysql-apt-config/select-product select Ok
mysql-community-server mysql-community-server/root-pass password ${MYSQL_ROOT_PASS}
mysql-community-server mysql-community-server/re-root-pass password ${MYSQL_ROOT_PASS}
mysql-community-server mysql-server/default-auth-override select Use Strong Password Encryption (RECOMMENDED)
EOF

    # Oracle MySQL APT konfiguratsioonipakett
    wget -q -O "/tmp/${MYSQL_APT_DEB}" "${MYSQL_APT_URL}"
    apt-get install -y -q "/tmp/${MYSQL_APT_DEB}"

    # Debian 13 (trixie) jaoks Oracle repos MySQL 8.0 puudub -> kasutan bookworm repot
    CODENAME=$(. /etc/os-release; echo "$VERSION_CODENAME")
    if [ "$CODENAME" != "bookworm" ] && [ "$CODENAME" != "bullseye" ]; then
        echo "Debian $CODENAME: kasutan MySQL 8.0 jaoks bookworm repositooriumi."
        KEY=/usr/share/keyrings/mysql-apt-config.gpg
        cat > /etc/apt/sources.list.d/mysql.list <<EOF
deb [signed-by=${KEY}] http://repo.mysql.com/apt/debian/ bookworm mysql-apt-config
deb [signed-by=${KEY}] http://repo.mysql.com/apt/debian/ bookworm mysql-8.0
EOF
        # MySQL 8.0 (bookworm) vajab libaio1, Debian 13-s on ainult libaio1t64
        if ! pkg_installed libaio1; then
            echo "Paigaldan libaio1 (bookworm) MySQL 8.0 jaoks..."
            wget -q -O /tmp/libaio1.deb \
                http://deb.debian.org/debian/pool/main/liba/libaio/libaio1_0.3.113-4_amd64.deb
            dpkg -i /tmp/libaio1.deb
        fi
    fi

    apt-get update -q
    apt-get install -y -q mysql-server

    mysql --version | grep -q " 8\.0\." && echo "MySQL 8.0 paigaldatud." \
        || { echo "VIGA: MySQL 8.0 paigaldus ebaonnestus."; exit 1; }
fi

# Teenus toole ja automaatselt kaivituma
systemctl enable mysql >/dev/null 2>&1 || true
systemctl start mysql

# /root/.my.cnf - root saab kasutada mysql klienti ilma parooli sisestamata
if [ -f /root/.my.cnf ]; then
    echo "/root/.my.cnf on juba olemas."
else
    cat > /root/.my.cnf <<EOF
[client]
host=localhost
user=root
password=${MYSQL_ROOT_PASS}
EOF
    echo "/root/.my.cnf loodud."
fi
chmod 600 /root/.my.cnf

# ---------- 3. Apache2 ----------
echo "==> Apache2 kontroll..."
if dpkg-query -W -f='${Package} ${Status}\n' apache2 2>/dev/null | grep -q "install ok installed"; then
    echo "Apache2 on juba paigaldatud."
else
    echo "Apache2 puudub - paigaldan..."
    apt-get install -y -q apache2
fi

# Teenus peab olema active ja enabled
systemctl is-enabled --quiet apache2 || systemctl enable apache2
systemctl is-active --quiet apache2 || systemctl start apache2

# Apache vaikimisi veebileht
INSTALL_TIME=$(date "+%Y-%m-%d %H:%M:%S")
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html lang="et">
<head><meta charset="utf-8"><title>LAMP server</title></head>
<body>
<h1>LAMP server t&ouml;&ouml;tab!</h1>
<p>LAMP paigaldus &otilde;nnestus.</p>
<p>&Otilde;pilane: ${STUDENT}</p>
<p>Grupp: ${GROUP}</p>
<p>Paigaldatud: ${INSTALL_TIME}</p>
</body>
</html>
EOF
echo "Apache vaikimisi leht uuendatud."

# ---------- 4. PHP 8.x ----------
echo "==> PHP 8.x kontroll..."
if command -v php >/dev/null 2>&1 && php -v | grep -q "^PHP 8\."; then
    echo "PHP 8.x on juba paigaldatud: $(php -v | head -n1)"
else
    echo "PHP 8.x puudub - paigaldan..."
    # Debian 12 -> PHP 8.2, Debian 13 -> PHP 8.4 (votan versiooni repost)
    PHP_VER=$(apt-cache depends php 2>/dev/null | grep -o "php8\.[0-9]*" | head -n1 | sed 's/php//')
    PHP_VER=${PHP_VER:-8.2}
    apt-get install -y -q php${PHP_VER} php${PHP_VER}-cli php${PHP_VER}-common \
        php${PHP_VER}-mysql libapache2-mod-php${PHP_VER}
    systemctl restart apache2
    echo "PHP paigaldatud: $(php -v | head -n1)"
fi

# PHP testfail
echo "<?php phpinfo(); ?>" > /var/www/html/info.php

# ---------- 5. Kontrollid ja raport ----------
APACHE_VER=$(apache2 -v | head -n1 | cut -d' ' -f3)
PHP_V=$(php -v | head -n1 | cut -d' ' -f2)
MYSQL_V=$(mysql --version | grep -o "[0-9]*\.[0-9]*\.[0-9]*" | head -n1)
[ -f /root/.my.cnf ] && MYCNF="olemas" || MYCNF="PUUDUB"
[ -f /var/www/html/index.html ] && IDX="olemas" || IDX="PUUDUB"
[ -f /var/www/html/info.php ] && INFO="olemas" || INFO="PUUDUB"
IP=$(hostname -I | awk '{print $1}')

echo
echo "=================================="
echo "           LAMP REPORT            "
echo "=================================="
echo "Apache2:"
echo "  Version:   ${APACHE_VER}"
echo "  Status:    $(systemctl is-active apache2 || true)"
echo "  Autostart: $(systemctl is-enabled apache2 || true)"
echo
echo "PHP:"
echo "  Version:   ${PHP_V}"
echo
echo "MySQL:"
echo "  Version:   ${MYSQL_V}"
echo "  Status:    $(systemctl is-active mysql || true)"
echo "  Autostart: $(systemctl is-enabled mysql || true)"
echo "  Root login .my.cnf kaudu: $(mysql -N -e 'SELECT 1' >/dev/null 2>&1 && echo OK || echo VIGA)"
echo
echo "Apache default page:"
echo "  /var/www/html/index.html - ${IDX}  (http://${IP}/)"
echo
echo "PHP test page:"
echo "  /var/www/html/info.php - ${INFO}  (http://${IP}/info.php)"
echo
echo "MySQL root configuration:"
echo "  /root/.my.cnf - ${MYCNF}"
echo "=================================="
