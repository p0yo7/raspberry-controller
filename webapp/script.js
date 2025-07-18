let ws = null;

function connect() {
    const host = document.getElementById("raspberry-host").value || "raspi-control.local";
    const url = `ws://${host}:8765`;
    ws = new WebSocket(url);

    ws.onopen = () => {
        updateConnectionStatus(true);
        document.getElementById("websocket-url").textContent = url;
        logStatus("✅ Conectado al servidor");
    };

    ws.onclose = () => {
        updateConnectionStatus(false);
        document.getElementById("websocket-url").textContent = "No conectado";
        logStatus("🔌 Conexión cerrada");
    };

    ws.onerror = (e) => {
        logStatus("❌ Error en conexión WebSocket");
    };

    ws.onmessage = (event) => {
        logStatus(`📩 Respuesta:\n${event.data}`);
    };
}

function disconnect() {
    if (ws) ws.close();
}

function sendCommand(command, params = []) {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
        logStatus("⚠️ WebSocket no conectado");
        return;
    }
    const msg = JSON.stringify({ command, params });
    ws.send(msg);
    logStatus(`➡️ Enviado: ${msg}`);
}

function sendGPIOCommand(cmd) {
    const pin = parseInt(document.getElementById("gpio-pin").value);
    sendCommand(cmd, [pin]);
}

function sendCustomCommand() {
    const cmd = document.getElementById("custom-command").value;
    const paramStr = document.getElementById("custom-params").value;
    const params = paramStr.split(',').map(x => isNaN(x) ? x : parseInt(x));
    sendCommand(cmd, params);
}

function runScript() {
    const script = document.getElementById("script-name").value;
    if (script.trim()) sendCommand("run_script", [script.trim()]);
}

function autoDetect() {
    alert("Auto-detección no implementada todavía.");
}

function saveHost() {
    const host = document.getElementById("raspberry-host").value;
    localStorage.setItem("raspberry-host", host);
    alert("Host guardado.");
}

function confirmAction(action) {
    if (confirm(`¿Seguro que quieres ejecutar ${action}?`)) {
        sendCommand(action, []);
    }
}

function updateConnectionStatus(connected) {
    const el = document.getElementById("connection-status");
    el.className = connected ? "connection-status connected" : "connection-status disconnected";
    el.querySelector(".status-icon").textContent = connected ? "🟢" : "🔴";
    el.querySelector(".status-text").textContent = connected ? "Conectado" : "Desconectado";
}

function logStatus(text) {
    const el = document.getElementById("status");
    el.textContent += `\n${text}`;
    el.scrollTop = el.scrollHeight;
}

function clearStatus() {
    document.getElementById("status").textContent = "";
}

// Cargar host guardado
window.onload = () => {
    const savedHost = localStorage.getItem("raspberry-host");
    if (savedHost) {
        document.getElementById("raspberry-host").value = savedHost;
    }
};
