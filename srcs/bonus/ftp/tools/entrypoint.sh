#!/bin/sh
set -e

FTP_PASS=$(cat /run/secrets/ftp_password)
FTP_USER="${FTP_USER:-ftpuser}"

# Create FTP user with home dir = WordPress webroot
adduser -h /var/www/html -s /sbin/nologin -D "${FTP_USER}" 2>/dev/null || true
echo "${FTP_USER}:${FTP_PASS}" | chpasswd

# Copy seed images to shared volume uploads directory
SEED_DEST="/var/www/html/wp-content/uploads/seed"
mkdir -p "${SEED_DEST}"
cp /seed/*.jpg  "${SEED_DEST}/" 2>/dev/null || true
cp /seed/*.jpeg "${SEED_DEST}/" 2>/dev/null || true
cp /seed/*.webp "${SEED_DEST}/" 2>/dev/null || true

echo "FTP server starting as user ${FTP_USER}..."
exec vsftpd /etc/vsftpd/vsftpd.conf
