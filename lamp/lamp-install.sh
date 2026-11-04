#!/bin/bash
# lamp-install.sh - paigaldab LAMP keskkonna: Apache2 + PHP 8.x + MySQL Server 8.0
# Autor: Janre Puuorg, ITS25
# Kaivitada root kasutajana: ./lamp-install.sh

set -e
export DEBIAN_FRONTEND=noninteractive

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
