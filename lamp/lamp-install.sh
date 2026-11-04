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
