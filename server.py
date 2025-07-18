#!/usr/bin/env python3
import asyncio
import websockets
import json
import pyautogui
import os
from http.server import HTTPServer, SimpleHTTPRequestHandler
import threading

# Configurar pyautogui
pyautogui.FAILSAFE = False  # Evita excepciones si se mueve a esquina
pyautogui.PAUSE = 0.1  # Pausa entre comandos para mejor rendimiento

async def handle_client(websocket):
    print("Cliente conectado")
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                t = data.get("type")
                
                if t == "mouse":
                    dx = data.get("dx", 0)
                    dy = data.get("dy", 0)
                    pyautogui.moveRel(dx, dy)
                    
                elif t == "click":
                    button = data.get("button", "left")
                    pyautogui.click(button=button)
                    
                elif t == "scroll":
                    dy = data.get("dy", 0)
                    pyautogui.scroll(dy)
                    
                elif t == "key":
                    key = data.get("key")
                    if key:
                        pyautogui.press(key)
                        
            except Exception as e:
                print(f"Error procesando mensaje: {e}")
                
    except websockets.exceptions.ConnectionClosed:
        print("Cliente desconectado")
    except Exception as e:
        print(f"Error en conexión: {e}")

def start_web_server():
    """Inicia el servidor web en un hilo separado"""
    os.chdir('/home/pi/serve-and-ate/webapp')
    
    class CustomHandler(SimpleHTTPRequestHandler):
        def end_headers(self):
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type')
            super().end_headers()
    
    httpd = HTTPServer(('0.0.0.0', 8080), CustomHandler)
    print("Servidor web iniciado en puerto 8080")
    httpd.serve_forever()

async def main():
    # Iniciar servidor web en hilo separado
    web_thread = threading.Thread(target=start_web_server, daemon=True)
    web_thread.start()
    
    # Iniciar servidor WebSocket
    async with websockets.serve(handle_client, "0.0.0.0", 8765):
        print("WebSocket escuchando en puerto 8765...")
        print("Accede a http://[IP_DE_TU_PI]:8080 desde tu celular")
        await asyncio.Future()  # Ejecutar indefinidamente

if __name__ == "__main__":
    asyncio.run(main())