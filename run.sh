#!/bin/bash
set -e

echo "Actualizando repositorios e instalando dependencias..."
sudo apt update
sudo apt install -y python3-pip python3-dev build-essential python3-venv avahi-daemon xvfb

# Ruta del proyecto
APP_DIR="$HOME/serve-and-ate"
VENV_DIR="$APP_DIR/venv"

echo "Creando estructura de carpetas..."
mkdir -p "$APP_DIR/webapp"
mkdir -p "$APP_DIR/scripts"

echo "Creando entorno virtual en $VENV_DIR..."
python3 -m venv "$VENV_DIR"

echo "Activando entorno virtual e instalando paquetes Python necesarios..."
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install websockets pyautogui rpi.gpio

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

echo "Copiando archivos al directorio $APP_DIR ..."
cp server.py "$APP_DIR/"
cp ./webapp/index.html "$APP_DIR/webapp/"
cp ./webapp/script.js "$APP_DIR/webapp/"
cp ./webapp/styles.css "$APP_DIR/webapp/"

echo "Asignando permisos de ejecución a server.py..."
chmod +x "$APP_DIR/server.py"

echo "Creando servicio systemd..."

cat << EOF | sudo tee /etc/systemd/system/serve-and-ate.service
[Unit]
Description=Serve and Ate Raspberry Pi Remote Control Server
After=network.target
[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$APP_DIR
ExecStartPre=/usr/bin/Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset
ExecStart=$VENV_DIR/bin/python $APP_DIR/server.py
Restart=always
RestartSec=10
Environment=DISPLAY=:99
Environment=PYTHONPATH=$APP_DIR
[Install]
WantedBy=multi-user.target
EOF

echo "Recargando systemd, habilitando y arrancando el servicio..."
sudo systemctl daemon-reload
sudo systemctl enable serve-and-ate.service
sudo systemctl start serve-and-ate.service

echo "Instalación y configuración completa!"
echo "Accede a http://serve-and-ate.local:8080 desde tu celular para controlar tu Raspberry Pi."

echo "Estado del servicio:"
sudo systemctl status serve-and-ate.service --no-pager
