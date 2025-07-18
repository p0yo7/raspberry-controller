#!/usr/bin/env python3
"""
Servidor completo para control de Raspberry Pi
Incluye servidor WebSocket y servidor HTTP
"""

import asyncio
import websockets
import json
import subprocess
import os
import threading
import logging
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import signal
import sys

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class RaspberryPiServer:
    def __init__(self):
        self.connected_clients = set()
        self.running = True
        
    async def handle_client(self, websocket, path):
        """Maneja conexiones de clientes WebSocket"""
        self.connected_clients.add(websocket)
        client_ip = websocket.remote_address[0]
        logger.info(f"Cliente conectado desde: {client_ip}")
        
        try:
            await websocket.send(json.dumps({
                'type': 'connection',
                'status': 'connected',
                'message': 'Conectado al Raspberry Pi'
            }))
            
            async for message in websocket:
                await self.process_command(websocket, message)
                
        except websockets.exceptions.ConnectionClosed:
            logger.info(f"Cliente desconectado: {client_ip}")
        except Exception as e:
            logger.error(f"Error en cliente {client_ip}: {e}")
        finally:
            self.connected_clients.discard(websocket)
    
    async def process_command(self, websocket, message):
        """Procesa comandos recibidos del cliente"""
        try:
            data = json.loads(message)
            command = data.get('command')
            params = data.get('params', [])
            
            logger.info(f"Ejecutando comando: {command} con parámetros: {params}")
            
            result = await self.execute_command(command, params)
            
            response = {
                'type': 'command_response',
                'status': 'success',
                'command': command,
                'params': params,
                'result': result
            }
            
        except json.JSONDecodeError:
            response = {
                'type': 'error',
                'status': 'error',
                'error': 'Formato JSON inválido'
            }
        except Exception as e:
            logger.error(f"Error procesando comando: {e}")
            response = {
                'type': 'error',
                'status': 'error',
                'error': str(e)
            }
        
        await websocket.send(json.dumps(response))
    
    async def execute_command(self, command, params):
        """Ejecuta comandos permitidos"""
        # Diccionario de comandos permitidos por seguridad
        allowed_commands = {
            'gpio_on': self.gpio_on,
            'gpio_off': self.gpio_off,
            'gpio_toggle': self.gpio_toggle,
            'gpio_read': self.gpio_read,
            'system_info': self.system_info,
            'get_temperature': self.get_temperature,
            'get_memory': self.get_memory,
            'get_disk_usage': self.get_disk_usage,
            'run_script': self.run_script,
            'list_processes': self.list_processes,
            'ping': self.ping,
            'reboot': self.reboot,
            'shutdown': self.shutdown
        }
        
        if command in allowed_commands:
            return await allowed_commands[command](params)
        else:
            raise Exception(f"Comando no permitido: {command}")
    
    async def gpio_on(self, params):
        """Enciende un GPIO"""
        pin = params[0] if params else 18
        try:
            # Usando comando gpio de WiringPi o escribiendo directamente al sysfs
            subprocess.run(['gpio', 'mode', str(pin), 'out'], check=True)
            subprocess.run(['gpio', 'write', str(pin), '1'], check=True)
            return f"GPIO {pin} encendido"
        except subprocess.CalledProcessError:
            # Fallback usando sysfs
            try:
                with open(f'/sys/class/gpio/gpio{pin}/direction', 'w') as f:
                    f.write('out')
                with open(f'/sys/class/gpio/gpio{pin}/value', 'w') as f:
                    f.write('1')
                return f"GPIO {pin} encendido (sysfs)"
            except:
                return f"Error controlando GPIO {pin}"
    
    async def gpio_off(self, params):
        """Apaga un GPIO"""
        pin = params[0] if params else 18
        try:
            subprocess.run(['gpio', 'mode', str(pin), 'out'], check=True)
            subprocess.run(['gpio', 'write', str(pin), '0'], check=True)
            return f"GPIO {pin} apagado"
        except subprocess.CalledProcessError:
            # Fallback usando sysfs
            try:
                with open(f'/sys/class/gpio/gpio{pin}/direction', 'w') as f:
                    f.write('out')
                with open(f'/sys/class/gpio/gpio{pin}/value', 'w') as f:
                    f.write('0')
                return f"GPIO {pin} apagado (sysfs)"
            except:
                return f"Error controlando GPIO {pin}"
    
    async def gpio_toggle(self, params):
        """Cambia el estado de un GPIO"""
        pin = params[0] if params else 18
        try:
            # Leer estado actual
            result = subprocess.run(['gpio', 'read', str(pin)], capture_output=True, text=True)
            current_state = int(result.stdout.strip())
            new_state = 1 if current_state == 0 else 0
            
            subprocess.run(['gpio', 'write', str(pin), str(new_state)], check=True)
            return f"GPIO {pin} cambiado a {new_state}"
        except:
            return f"Error cambiando estado GPIO {pin}"
    
    async def gpio_read(self, params):
        """Lee el estado de un GPIO"""
        pin = params[0] if params else 18
        try:
            result = subprocess.run(['gpio', 'read', str(pin)], capture_output=True, text=True)
            state = result.stdout.strip()
            return f"GPIO {pin} estado: {state}"
        except:
            return f"Error leyendo GPIO {pin}"
    
    async def system_info(self, params):
        """Obtiene información del sistema"""
        try:
            # Información básica del sistema
            uname = subprocess.run(['uname', '-a'], capture_output=True, text=True)
            uptime = subprocess.run(['uptime'], capture_output=True, text=True)
            
            # Información del modelo de Raspberry Pi
            try:
                with open('/proc/device-tree/model', 'r') as f:
                    model = f.read().strip()
            except:
                model = "Desconocido"
            
            # Información de la CPU
            try:
                with open('/proc/cpuinfo', 'r') as f:
                    cpuinfo = f.read()
                # Extraer información relevante
                cpu_model = [line for line in cpuinfo.split('\n') if 'model name' in line]
                cpu_model = cpu_model[0].split(':')[1].strip() if cpu_model else "Desconocido"
            except:
                cpu_model = "Desconocido"
            
            info = {
                'model': model,
                'system': uname.stdout.strip(),
                'uptime': uptime.stdout.strip(),
                'cpu': cpu_model
            }
            
            return json.dumps(info, indent=2)
        except Exception as e:
            return f"Error obteniendo información del sistema: {e}"
    
    async def get_temperature(self, params):
        """Obtiene la temperatura del CPU"""
        try:
            # Temperatura de la GPU/CPU
            result = subprocess.run(['vcgencmd', 'measure_temp'], capture_output=True, text=True)
            temp = result.stdout.strip()
            
            # Temperatura del CPU desde sysfs
            try:
                with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                    cpu_temp = int(f.read().strip()) / 1000
                temp += f"\nCPU: {cpu_temp:.1f}°C"
            except:
                pass
            
            return temp
        except Exception as e:
            return f"Temperatura no disponible: {e}"
    
    async def get_memory(self, params):
        """Obtiene información de memoria"""
        try:
            result = subprocess.run(['free', '-h'], capture_output=True, text=True)
            return result.stdout
        except Exception as e:
            return f"Error obteniendo memoria: {e}"
    
    async def get_disk_usage(self, params):
        """Obtiene uso del disco"""
        try:
            result = subprocess.run(['df', '-h'], capture_output=True, text=True)
            return result.stdout
        except Exception as e:
            return f"Error obteniendo uso del disco: {e}"
    
    async def run_script(self, params):
        """Ejecuta un script desde el directorio de scripts"""
        script_name = params[0] if params else None
        if not script_name:
            return "Nombre de script requerido"
        
        # Directorio seguro para scripts
        script_dir = Path('/home/pi/scripts')
        script_path = script_dir / script_name
        
        if not script_path.exists():
            return f"Script {script_name} no encontrado"
        
        if not script_path.is_file():
            return f"{script_name} no es un archivo"
        
        try:
            # Ejecutar script con timeout
            result = subprocess.run(
                ['python3', str(script_path)], 
                capture_output=True, 
                text=True, 
                timeout=30
            )
            
            output = result.stdout
            if result.stderr:
                output += f"\nErrores: {result.stderr}"
            
            return output or "Script ejecutado sin salida"
        except subprocess.TimeoutExpired:
            return "Script timeout (30s)"
        except Exception as e:
            return f"Error ejecutando script: {e}"
    
    async def list_processes(self, params):
        """Lista procesos del sistema"""
        try:
            result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
            lines = result.stdout.split('\n')
            # Mostrar solo las primeras 20 líneas
            return '\n'.join(lines[:21])
        except Exception as e:
            return f"Error listando procesos: {e}"
    
    async def ping(self, params):
        """Comando ping simple"""
        return "pong"
    
    async def reboot(self, params):
        """Reinicia el sistema (requiere permisos)"""
        try:
            subprocess.run(['sudo', 'reboot'], check=True)
            return "Reiniciando sistema..."
        except Exception as e:
            return f"Error reiniciando: {e}"
    
    async def shutdown(self, params):
        """Apaga el sistema (requiere permisos)"""
        try:
            subprocess.run(['sudo', 'shutdown', 'now'], check=True)
            return "Apagando sistema..."
        except Exception as e:
            return f"Error apagando: {e}"

class CustomHTTPRequestHandler(SimpleHTTPRequestHandler):
    """Manejador HTTP personalizado"""
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory='/home/pi/raspi-control/webapp', **kwargs)
    
    def log_message(self, format, *args):
        """Logging personalizado"""
        logger.info(f"HTTP {self.client_address[0]} - {format % args}")

def start_http_server():
    """Inicia el servidor HTTP"""
    try:
        httpd = HTTPServer(('0.0.0.0', 8080), CustomHTTPRequestHandler)
        logger.info("Servidor HTTP iniciado en puerto 8080")
        logger.info("Acceso web: http://raspi-control.local:8080")
        httpd.serve_forever()
    except Exception as e:
        logger.error(f"Error en servidor HTTP: {e}")

def signal_handler(signum, frame):
    """Manejador de señales para cierre limpio"""
    logger.info("Recibida señal de terminación, cerrando servidores...")
    sys.exit(0)

async def main():
    """Función principal"""
    # Configurar manejadores de señales
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Crear directorio de scripts si no existe
    script_dir = Path('/home/pi/scripts')
    script_dir.mkdir(exist_ok=True)
    
    # Iniciar servidor HTTP en thread separado
    http_thread = threading.Thread(target=start_http_server)
    http_thread.daemon = True
    http_thread.start()
    
    # Iniciar servidor WebSocket
    server = RaspberryPiServer()
    logger.info("Servidor WebSocket iniciado en puerto 8765")
    logger.info("WebSocket: ws://raspi-control.local:8765")
    
    try:
        await websockets.serve(server.handle_client, "0.0.0.0", 8765)
        logger.info("Servidores iniciados correctamente")
        await asyncio.Future()  # Mantener corriendo
    except Exception as e:
        logger.error(f"Error en servidor WebSocket: {e}")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Servidor detenido por el usuario")
    except Exception as e:
        logger.error(f"Error crítico: {e}")