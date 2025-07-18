#!/bin/bash
set -e

echo "Instalando dependencias..."
sudo apt update
sudo apt install -y python3-pip python3-dev build-essential wiringpi \
    nginx avahi-daemon

echo "Instalando paquetes de Python..."
pip3 install websockets

echo "Habilitando mDNS (Avahi)..."
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon

echo "Configurando estructura de archivos..."
mkdir -p /home/pi/scripts
mkdir -p /home/pi/serve-and-ate/webapp

cp server.py /home/pi/serve-and-ate/
cp styles.css /home/pi/serve-and-ate/webapp/
cp script.js /home/pi/serve-and-ate/webapp/
cp index.html /home/pi/serve-and-ate/webapp/

echo "Permisos para scripts..."
chmod +x /home/pi/serve-and-ate/server.py

echo "Creando servicio systemd..."
SERVICE_PATH="/etc/systemd/system/serve-and-ate.service"
sudo tee "$SERVICE_PATH" > /dev/null <<EOF
[Unit]
Description=Servidor WebSocket y HTTP para Raspberry Pi (Serve-and-Ate)
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/pi/serve-and-ate/server.py
WorkingDirectory=/home/pi/serve-and-ate
Restart=always
User=pi
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

echo "Recargando daemon y habilitando servicio..."
sudo systemctl daemon-reload
sudo systemctl enable serve-and-ate
sudo systemctl restart serve-and-ate

echo "Servicio iniciado correctamente. Verifica con:"
echo "   sudo systemctl status serve-and-ate"

echo "Accede desde tu navegador a: http://serve-and-ate.local:8080"
