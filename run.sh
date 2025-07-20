#!/bin/bash
set -e

echo "Actualizando repositorios e instalando dependencias..."
sudo apt update
sudo apt install -y python3-pip python3-dev build-essential avahi-daemon

echo "Instalando paquetes Python necesarios..."
pip3 install --upgrade --break-system-packages pip
pip3 install --break-system-packages websockets pyautogui rpi.gpio

echo "Instalando Xvfb para display virtual..."
sudo apt install -y xvfb

echo "Habilitando y arrancando servicio mDNS (Avahi)..."
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon

echo "Configurando hostname personalizado para Avahi..."
sudo mkdir -p /etc/avahi/services
cat << EOF | sudo tee /etc/avahi/services/serve-and-ate.service
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Serve and Ate Remote Control</name>
  <service>
    <type>_http._tcp</type>
    <port>8080</port>
    <host-name>serve-and-ate.local</host-name>
  </service>
</service-group>
EOF

echo "Reiniciando servicio Avahi para aplicar configuración..."
sudo systemctl restart avahi-daemon

echo "Creando estructura de carpetas..."
mkdir -p ~/serve-and-ate/webapp
mkdir -p ~/serve-and-ate/scripts

echo "Copiando archivos al directorio ~/serve-and-ate/ ..."
cp server.py ~/serve-and-ate/
cp ./webapp/index.html ~/serve-and-ate/webapp/
cp ./webapp/script.js ~/serve-and-ate/webapp/
cp ./webapp/styles.css ~/serve-and-ate/webapp/

echo "Asignando permisos de ejecución a server.py..."
chmod +x ~/serve-and-ate/server.py

echo "Creando servicio systemd..."
cat << EOF | sudo tee /etc/systemd/system/serve-and-ate.service
[Unit]
Description=Serve and Ate Raspberry Pi Remote Control Server
After=network.target
[Service]
Type=simple
User=p0yo7
Group=p0yo7
WorkingDirectory=$HOME/serve-and-ate
ExecStartPre=/usr/bin/Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset
ExecStart=/usr/bin/python3 $HOME/serve-and-ate/server.py
Restart=always
RestartSec=10
Environment=DISPLAY=:99
Environment=PYTHONPATH=$HOME/serve-and-ate
[Install]
WantedBy=multi-user.target
EOF

echo "Recargando systemd, habilitando y arrancando el servicio..."
sudo systemctl daemon-reload
sudo systemctl enable serve-and-ate.service
sudo systemctl start serve-and-ate.service

echo "Instalación y configuración completa!"

echo "Accede a http://serve-and-ate.local:8080 desde tu celular para controlar tu Raspberry Pi."
# Mostrar estado del servicio

echo "Estado del servicio:"
sudo systemctl status serve-and-ate.service --no-pager