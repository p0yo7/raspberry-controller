use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, tungstenite::Message};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json;
use tokio::fs;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::process::Command;
use std::path::Path;

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

    while let Some(msg) = ws_receiver.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                if let Ok(data) = serde_json::from_str::<ClientMessage>(&text) {
                    match handle_message(data).await {
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

async fn execute_command(cmd: &str, args: Vec<&str>) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let output = Command::new(cmd)
        .args(args)
        .env("DISPLAY", ":99")
        .output()
        .await?;
    
    if !output.status.success() {
        let error_msg = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Command failed: {}", error_msg).into());
    }
    
    Ok(())
}

async fn handle_message(data: ClientMessage) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    match data.msg_type.as_str() {
        "mouse" => {
            let dx = data.dx.unwrap_or(0);
            let dy = data.dy.unwrap_or(0);
            execute_command("xdotool", vec!["mousemove_relative", "--", &dx.to_string(), &dy.to_string()]).await?;
        }
        "click" => {
            let button = data.button.unwrap_or_else(|| "left".to_string());
            let button_num = match button.as_str() {
                "left" => "1",
                "middle" => "2",
                "right" => "3",
                _ => "1",
            };
            execute_command("xdotool", vec!["click", button_num]).await?;
        }
        "scroll" => {
            let dy = data.dy.unwrap_or(0);
            if dy > 0 {
                execute_command("xdotool", vec!["click", "4"]).await?; // scroll up
            } else if dy < 0 {
                execute_command("xdotool", vec!["click", "5"]).await?; // scroll down
            }
        }
        "key" => {
            if let Some(key_str) = data.key {
                let xdotool_key = match key_str.as_str() {
                    "space" => "space",
                    "enter" => "Return",
                    "escape" => "Escape",
                    "tab" => "Tab",
                    "backspace" => "BackSpace",
                    "delete" => "Delete",
                    "up" => "Up",
                    "down" => "Down",
                    "left" => "Left",
                    "right" => "Right",
                    "ctrl" => "ctrl",
                    "alt" => "alt",
                    "shift" => "shift",
                    // Para letras individuales
                    s if s.len() == 1 => {
                        execute_command("xdotool", vec!["type", s]).await?;
                        return Ok(());
                    }
                    _ => {
                        println!("Tecla no reconocida: {}", key_str);
                        return Ok(());
                    }
                };
                execute_command("xdotool", vec!["key", xdotool_key]).await?;
            }
        }
        _ => {
            println!("Tipo de mensaje no reconocido: {}", data.msg_type);
        }
    }
    Ok(())
}

async fn serve_static_file(path: &str) -> Result<(Vec<u8>, &'static str), std::io::Error> {
    let webapp_dir = "/home/pi/serve-and-ate-rust/webapp";
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
    // Verificar que xdotool esté instalado
    match Command::new("which").arg("xdotool").output().await {
        Ok(output) if output.status.success() => {
            println!("xdotool encontrado");
        }
        _ => {
            eprintln!("Error: xdotool no está instalado. Ejecuta: sudo apt install xdotool");
            return Ok(());
        }
    }
    
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