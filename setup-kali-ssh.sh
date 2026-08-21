#!/bin/bash
# Run this on your Kali NetHunter terminal to enable SSH access

mkdir -p ~/.ssh
chmod 700 ~/.ssh

echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMiniO5oHjW6f8Yc0TjTyjpKSjFHu8CBbBown418lN/e root@Ubuntu-ahk" > ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chown -R root:root ~/.ssh

echo "[+] SSH key added"
echo "[+] Verifying key:"
cat ~/.ssh/authorized_keys

# Set root password
echo "[+] Setting root password to 'root'"
echo "root:root" | chpasswd

# Enable and restart sshd
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

if command -v systemctl &>/dev/null; then
    systemctl restart ssh
elif command -v service &>/dev/null; then
    service ssh restart
fi

echo "[+] SSH setup complete"
echo "[+] Try: ssh root@192.168.0.114"
