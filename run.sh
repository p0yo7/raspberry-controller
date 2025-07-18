#!/bin/bash
set -e

echo "Actualizando repositorios e instalando dependencias..."
sudo apt update
sudo apt install -y python3-pip python3-dev build-essential wiringpi avahi-daemon

echo "Instalando paquetes Python necesarios..."
pip3 install --upgrade pip
pip3 install websockets pyautogui

echo "Habilitando y arrancando servicio mDNS (Avahi)..."
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon

echo "Creando estructura de carpetas..."
mkdir -p /home/pi/serve-and-ate/webapp
mkdir -p /home/pi/serve-and-ate/scripts

echo "Copiando archivos al directorio /home/pi/serve-and-ate/ ..."
cp server.py /home/pi/serve-and-ate/
cp index.html /home/pi/serve-and-ate/webapp/
cp script.js /home/pi/serve-and-ate/webapp/

echo "Asignando permisos de ejecución a server.py..."
chmod +x /home/pi/serve-and-ate/server.py

echo "Creando servicio systemd..."

cat << EOF | sudo tee /etc/systemd/system/serve-and-ate.service
[Unit]
Description=Serve and Ate Raspberry Pi Remote Control Server
After=network.target

[Service]
User=pi
WorkingDirectory=/home/pi/serve-and-ate
ExecStart=/usr/bin/python3 /home/pi/serve-and-ate/server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "Recargando systemd, habilitando y arrancando el servicio..."
sudo systemctl daemon-reload
sudo systemctl enable serve-and-ate.service
sudo systemctl start serve-and-ate.service

echo "Instalación y configuración completa!"
echo "Accede a http://serve-and-ate.local:8080 desde tu celular para controlar tu Raspberry Pi."
