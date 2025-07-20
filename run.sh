#!/bin/bash
set -e

echo "Actualizando repositorios e instalando dependencias..."
sudo apt update
sudo apt install -y build-essential pkg-config libx11-dev libxtst-dev libxinerama-dev libxrandr-dev libxi-dev libxcursor-dev avahi-daemon xvfb curl

echo "Instalando Rust..."
if ! command -v rustc &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
else
    echo "Rust ya está instalado"
fi

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
mkdir -p ~/serve-and-ate-rust/webapp
mkdir -p ~/serve-and-ate-rust/src

echo "Copiando archivos al directorio ~/serve-and-ate-rust/ ..."
cp Cargo.toml ~/serve-and-ate-rust/
cp src/main.rs ~/serve-and-ate-rust/src/
cp ./webapp/index.html ~/serve-and-ate-rust/webapp/
cp ./webapp/script.js ~/serve-and-ate-rust/webapp/
cp ./webapp/styles.css ~/serve-and-ate-rust/webapp/

echo "Navegando al directorio del proyecto y compilando..."
cd ~/serve-and-ate-rust
source ~/.cargo/env
cargo build --release

echo "Creando servicio systemd..."
cat << EOF | sudo tee /etc/systemd/system/serve-and-ate-rust.service
[Unit]
Description=Serve and Ate Rust Remote Control Server
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$HOME/serve-and-ate-rust
ExecStartPre=/usr/bin/Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset
ExecStart=$HOME/serve-and-ate-rust/target/release/serve-and-ate-rust
Restart=always
RestartSec=10
Environment=DISPLAY=:99
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
EOF

echo "Recargando systemd, habilitando y arrancando el servicio..."
sudo systemctl daemon-reload
sudo systemctl enable serve-and-ate-rust.service
sudo systemctl start serve-and-ate-rust.service

echo "Instalación y configuración completa!"
echo "Accede a http://serve-and-ate.local:8080 desde tu celular para controlar tu Raspberry Pi."

# Mostrar estado del servicio
echo "Estado del servicio:"
sudo systemctl status serve-and-ate-rust.service --no-pager