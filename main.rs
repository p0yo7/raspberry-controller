use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, tungstenite::Message};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json;
use tokio::fs;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use std::path::Path;
use enigo::{Enigo, MouseControllable, KeyboardControllable};

#[derive(Deserialize, Debug)]
struct ClientMessage {
    #[serde(rename = "type")]
    msg_type: String,
    dx: Option<i32>,
    dy: Option<i32>,
    button: Option<String>,
    key: Option<String>,
}

#[derive(Serialize)]
struct ServerResponse {
    status: String,
    message: Option<String>,
}

async fn handle_websocket(stream: TcpStream) {
    println!("Cliente conectado");
    
    let ws_stream = match accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            println!("Error al establecer conexión WebSocket: {}", e);
            return;
        }
    };

    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    let mut enigo = Enigo::new();

    while let Some(msg) = ws_receiver.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                if let Ok(data) = serde_json::from_str::<ClientMessage>(&text) {
                    match handle_message(&mut enigo, data).await {
                        Ok(_) => {
                            let response = ServerResponse {
                                status: "ok".to_string(),
                                message: None,
                            };
                            if let Ok(response_json) = serde_json::to_string(&response) {
                                let _ = ws_sender.send(Message::Text(response_json)).await;
                            }
                        }
                        Err(e) => {
                            println!("Error procesando mensaje: {}", e);
                            let response = ServerResponse {
                                status: "error".to_string(),
                                message: Some(e.to_string()),
                            };
                            if let Ok(response_json) = serde_json::to_string(&response) {
                                let _ = ws_sender.send(Message::Text(response_json)).await;
                            }
                        }
                    }
                } else {
                    println!("Error parseando mensaje JSON");
                }
            }
            Ok(Message::Close(_)) => {
                println!("Cliente desconectado");
                break;
            }
            Err(e) => {
                println!("Error en conexión WebSocket: {}", e);
                break;
            }
            _ => {}
        }
    }
}

async fn handle_message(enigo: &mut Enigo, data: ClientMessage) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    match data.msg_type.as_str() {
        "mouse" => {
            let dx = data.dx.unwrap_or(0);
            let dy = data.dy.unwrap_or(0);
            enigo.mouse_move_relative(dx, dy);
        }
        "click" => {
            let button = data.button.unwrap_or_else(|| "left".to_string());
            match button.as_str() {
                "left" => enigo.mouse_click(enigo::MouseButton::Left),
                "right" => enigo.mouse_click(enigo::MouseButton::Right),
                "middle" => enigo.mouse_click(enigo::MouseButton::Middle),
                _ => enigo.mouse_click(enigo::MouseButton::Left),
            }
        }
        "scroll" => {
            let dy = data.dy.unwrap_or(0);
            if dy > 0 {
                for _ in 0..dy {
                    enigo.mouse_scroll_y(1);
                }
            } else {
                for _ in 0..(-dy) {
                    enigo.mouse_scroll_y(-1);
                }
            }
        }
        "key" => {
            if let Some(key_str) = data.key {
                match key_str.as_str() {
                    "space" => enigo.key_click(enigo::Key::Space),
                    "enter" => enigo.key_click(enigo::Key::Return),
                    "escape" => enigo.key_click(enigo::Key::Escape),
                    "tab" => enigo.key_click(enigo::Key::Tab),
                    "backspace" => enigo.key_click(enigo::Key::Backspace),
                    "delete" => enigo.key_click(enigo::Key::Delete),
                    "up" => enigo.key_click(enigo::Key::UpArrow),
                    "down" => enigo.key_click(enigo::Key::DownArrow),
                    "left" => enigo.key_click(enigo::Key::LeftArrow),
                    "right" => enigo.key_click(enigo::Key::RightArrow),
                    "ctrl" => enigo.key_click(enigo::Key::Control),
                    "alt" => enigo.key_click(enigo::Key::Alt),
                    "shift" => enigo.key_click(enigo::Key::Shift),
                    // Para letras individuales
                    s if s.len() == 1 => {
                        let ch = s.chars().next().unwrap();
                        enigo.key_sequence(&ch.to_string());
                    }
                    _ => {
                        println!("Tecla no reconocida: {}", key_str);
                        return Ok(());
                    }
                }
            }
        }
        _ => {
            println!("Tipo de mensaje no reconocido: {}", data.msg_type);
        }
    }
    Ok(())
}

async fn serve_static_file(path: &str) -> Result<(Vec<u8>, &'static str), std::io::Error> {
    let webapp_dir = "/home/pi/serve-and-ate/webapp";
    let full_path = if path == "/" {
        format!("{}/index.html", webapp_dir)
    } else {
        format!("{}{}", webapp_dir, path)
    };

    let content = fs::read(&full_path).await?;
    
    let content_type = match Path::new(&full_path).extension().and_then(|s| s.to_str()) {
        Some("html") => "text/html",
        Some("css") => "text/css",
        Some("js") => "application/javascript",
        Some("json") => "application/json",
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("svg") => "image/svg+xml",
        _ => "text/plain",
    };

    Ok((content, content_type))
}

async fn handle_http(mut stream: TcpStream) {
    let mut buffer = [0; 1024];
    if let Ok(bytes_read) = stream.read(&mut buffer).await {
        let request = String::from_utf8_lossy(&buffer[..bytes_read]);
        
        // Parse simple HTTP request
        let lines: Vec<&str> = request.lines().collect();
        if let Some(request_line) = lines.first() {
            let parts: Vec<&str> = request_line.split_whitespace().collect();
            if parts.len() >= 2 && parts[0] == "GET" {
                let path = parts[1];
                
                match serve_static_file(path).await {
                    Ok((content, content_type)) => {
                        let response = format!(
                            "HTTP/1.1 200 OK\r\n\
                             Content-Type: {}\r\n\
                             Content-Length: {}\r\n\
                             Access-Control-Allow-Origin: *\r\n\
                             Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n\
                             Access-Control-Allow-Headers: Content-Type\r\n\
                             \r\n",
                            content_type,
                            content.len()
                        );
                        let _ = stream.write_all(response.as_bytes()).await;
                        let _ = stream.write_all(&content).await;
                    }
                    Err(_) => {
                        let not_found = b"HTTP/1.1 404 NOT FOUND\r\n\
                                         Content-Length: 13\r\n\
                                         \r\n\
                                         404 Not Found";
                        let _ = stream.write_all(not_found).await;
                    }
                }
            }
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Servidor HTTP para archivos estáticos
    let http_listener = TcpListener::bind("0.0.0.0:8080").await?;
    println!("Servidor HTTP iniciado en puerto 8080");
    
    // Servidor WebSocket
    let ws_listener = TcpListener::bind("0.0.0.0:8765").await?;
    println!("WebSocket escuchando en puerto 8765...");
    
    // Spawn HTTP server task
    tokio::spawn(async move {
        while let Ok((stream, _)) = http_listener.accept().await {
            tokio::spawn(handle_http(stream));
        }
    });
    
    // Handle WebSocket connections
    while let Ok((stream, _)) = ws_listener.accept().await {
        tokio::spawn(handle_websocket(stream));
    }
    
    Ok(())
}