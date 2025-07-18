#!/usr/bin/env python3
import asyncio
import websockets
import json
import pyautogui

pyautogui.FAILSAFE = False  # Evita excepciones si se mueve a esquina

async def handle_client(websocket):
    print("Cliente conectado")
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
                pyautogui.press(key)
        except Exception as e:
            print("Error:", e)

async def main():
    async with websockets.serve(handle_client, "0.0.0.0", 8765):
        print("WebSocket escuchando en puerto 8765...")
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
