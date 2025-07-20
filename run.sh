#!/bin/bash
set -e

USER_NAME=$(whoami)
HOME_DIR="/home/$USER_NAME"

echo "🔧 Actualizando repositorios e instalando dependencias..."
sudo apt update
sudo apt install -y build-essential pkg-config avahi-daemon xvfb curl xdotool xorg

echo "🦀 Instalando Rust si no está presente..."
if ! command -v rustc &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME_DIR/.cargo/env"
else
    echo "✅ Rust ya está instalado"
fi

echo "🌐 Habilitando y arrancando servicio mDNS (Avahi)..."
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon

echo "📛 Configurando hostname personalizado para Avahi..."
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

echo "♻️ Reiniciando Avahi para aplicar cambios..."
sudo systemctl restart avahi-daemon

echo "📁 Creando estructura de carpetas..."
mkdir -p "$HOME_DIR/serve-and-ate-rust/webapp"
mkdir -p "$HOME_DIR/serve-and-ate-rust/src"

echo "📂 Copiando archivos del proyecto..."
cp Cargo.toml "$HOME_DIR/serve-and-ate-rust/"
cp src/main.rs "$HOME_DIR/serve-and-ate-rust/src/"
cp ./webapp/index.html "$HOME_DIR/serve-and-ate-rust/webapp/"
cp ./webapp/script.js "$HOME_DIR/serve-and-ate-rust/webapp/"
cp ./webapp/styles.css "$HOME_DIR/serve-and-ate-rust/webapp/"

echo "🔨 Compilando el proyecto Rust en modo release..."
cd "$HOME_DIR/serve-and-ate-rust"
source "$HOME_DIR/.cargo/env"
cargo clean
cargo build --release

echo "📜 Creando script de arranque para el servicio..."
cat << EOF > "$HOME_DIR/serve-and-ate-rust/start.sh"
#!/bin/bash
set -e
pgrep Xvfb || Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset &
sleep 2
exec $HOME_DIR/serve-and-ate-rust/target/release/serve-and-ate-rust
EOF

chmod +x "$HOME_DIR/serve-and-ate-rust/start.sh"

echo "🛠️ Creando archivo systemd para el servicio..."
cat << EOF | sudo tee /etc/systemd/system/serve-and-ate-rust.service
[Unit]
Description=Serve and Ate Rust Remote Control Server
After=network.target

[Service]
Type=simple
User=$USER_NAME
Group=$USER_NAME
WorkingDirectory=$HOME_DIR/serve-and-ate-rust
ExecStart=$HOME_DIR/serve-and-ate-rust/start.sh
Restart=always
RestartSec=10
Environment=DISPLAY=:99
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
EOF

echo "🔄 Recargando systemd y habilitando el servicio..."
sudo systemctl daemon-reload
sudo systemctl enable serve-and-ate-rust.service
sudo systemctl start serve-and-ate-rust.service

echo "✅ Instalación y configuración completa!"
echo "🌍 Accede a: http://serve-and-ate.local:8080 desde tu celular"
echo "📋 Estado del servicio:"
sudo systemctl status serve-and-ate-rust.service --no-pager
