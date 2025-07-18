const ws = new WebSocket("ws://" + location.hostname + ":8765");

ws.onopen = () => console.log("WebSocket conectado");
ws.onclose = () => console.log("WebSocket cerrado");

const trackpad = document.getElementById("trackpad");
let lastX = null,
  lastY = null;

let lastTap = 0;

trackpad.addEventListener("touchstart", (e) => {
  if (e.touches.length === 1) {
    // Un dedo: trackpad movimiento y doble tap
    const t = e.touches[0];
    lastX = t.clientX;
    lastY = t.clientY;

    const currentTime = new Date().getTime();
    const tapLength = currentTime - lastTap;
    if (tapLength < 300 && tapLength > 0) {
      // Doble tap detectado: clic izquierdo
      ws.send(JSON.stringify({ type: "click", button: "left" }));
      e.preventDefault();
    }
    lastTap = currentTime;
  }
});

trackpad.addEventListener("touchmove", (e) => {
  if (e.touches.length === 1) {
    e.preventDefault(); // Evita scroll

    const t = e.touches[0];
    const dx = t.clientX - lastX;
    const dy = t.clientY - lastY;
    lastX = t.clientX;
    lastY = t.clientY;

    ws.send(
      JSON.stringify({
        type: "mouse",
        dx: dx,
        dy: dy,
      })
    );
  } else if (e.touches.length === 2) {
    // Scroll vertical con dos dedos
    e.preventDefault();

    const t1 = e.touches[0];
    const t2 = e.touches[1];

    const currentY = (t1.clientY + t2.clientY) / 2;
    if (trackpad.lastScrollY !== undefined) {
      const dy = trackpad.lastScrollY - currentY;
      ws.send(JSON.stringify({ type: "scroll", dy: dy * 10 })); // Multiplica para que sea más sensible
    }
    trackpad.lastScrollY = currentY;
  }
});

trackpad.addEventListener("touchend", (e) => {
  if (e.touches.length < 2) {
    trackpad.lastScrollY = undefined;
  }
  if (e.touches.length === 0) {
    lastX = null;
    lastY = null;
  }
});

const keyboard = document.getElementById("keyboard");

keyboard.addEventListener("keydown", (e) => {
  ws.send(JSON.stringify({ type: "key", key: e.key }));
});

// Botón clic derecho
const rightClickBtn = document.getElementById("right-click-btn");
rightClickBtn.addEventListener("click", () => {
  ws.send(JSON.stringify({ type: "click", button: "right" }));
});
