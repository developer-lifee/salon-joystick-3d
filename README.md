# ⚡️ LASER TRACER 3D
### *Metal Hardware Ray Tracing Combat & Teleportation Engine for iOS*

![iOS 17+](https://img.shields.io/badge/iOS-17.0%2B-blue?style=for-the-badge&logo=apple)
![Metal 3.0](https://img.shields.io/badge/Metal-3.0_Ray_Tracing-cyan?style=for-the-badge&logo=apple)
![Architecture](https://img.shields.io/badge/Architecture-Pure_Swift_%2B_Metal_Shaders-brightgreen?style=for-the-badge)
![Performance](https://img.shields.io/badge/Performance-60_FPS_Locked-orange?style=for-the-badge)

> **LASER TRACER 3D** es un motor de combate táctico 3D y demostración técnica avanzada desarrollado **100% en código nativo Swift y Metal 3.0**, diseñado para aprovechar el hardware de trazado de rayos (Ray Tracing Cores) de los chips de la serie **Apple A17 Pro (iPhone 15 Pro / 15 Pro Max) y Apple Silicon M-series**.

---

## 🎮 Mecánicas de Juego y Controles Tácticos

### ⚡️ 1. Teletransporte Minato Flash Warp (Beacons de Luz)
Inspirado en la técnica del *Hiraishin* del 4º Hokage (Minato Namikaze):
- **Beacons de Luz:** Todas las luces activas del mapa (*Poste de Luz*, *Neón PISCINA*, *Neón SHEERIT*, *Tiras de Piscina*) funcionan como marcadores de teletransporte instantáneo.
- **Rueda Radial Estilo Fortnite / GTA:** Presiona el botón **`⚡️ WARP`** para abrir la Rueda Radial de luces. Tocar cualquier luz activa te **teletransportará en 1 milisegundo** con un destello táctico.
- **Auto-Eliminación de NPCs:** Si un bot te está atacando y te teletransportas al instante, el bot se confundirá y continuará disparando al frente. El láser reflejado en los espejos o paredes impactará al bot, haciendo que **se auto-eliminate**.

---

### 🛡️ 2. Espejo Defensivo Neón PBR (`🛡️ ESPEJO`)
- **Física de Ray Tracing Real:** El espejo no es solo una textura reflectante; es un plano 3D dinámico que redirige y rebota los rayos láser enemigos en tiempo real.
- **Ángulo de Cobertura:** Únicamente refleja disparos si el jugador mira de frente al rayo incidente (`dot(playerFacing, incomingLaserDir) > 0.25`).
- **Defensivo Puro:** No emite rayos propios; retracta el escudo automáticamente al estar inactivo.

---

### ⏱️ 3. Modo Cámara Lenta Matrix Dead-Eye (`⏱️ SLOW-MO`)
- Presiona **`⏱️ Slow-Mo`** para dilatar la velocidad del tiempo a **0.20x (20%)**.
- Permite ver los rayos láser volando lentamente por el aire en 3D para calcular esquives de precisión, desplegar el espejo defensivo o apuntar a la cabeza de los bots.
- Incluye viñeta radial amarilla táctica e iluminación dramática.

---

### 🏊‍♂️ 4. Trampolín 3D y Reino Submarino Secreto (Easter Egg)
- **Trampolín de Clavados:** Súbete al trampolín 3D de la baranda este (`Y = 1.25m`) y salta hacia el agua.
- **Reino Subterráneo Submarino:** Al sumergirte en el agua de la piscina, el personaje atraviesa el fondo de la piscina y se transporta al **Reino Submarino Path-Traced**, con refracción de Ley de Snell y atmósfera de luz bioluminiscente.
- **Respiración Infinita:** El personaje puede nadar libremente bajo el agua sin ahogarse ni perder puntos de vida.

---

### 🛝 5. Tobogán de Agua (Pool Water Slide)
- Canaleta curva de fibra de vidrio mate en el borde norte (`Z = -7.2`).
- **Física de Impulso Acelerado:** Al entrar a la canaleta, el jugador recibe un impulso automático de **11.5 m/s** saliendo lanzado directamente hacia el agua.

---

## 🛠️ Arquitectura Técnica y Motor Metal

```
                        ┌─────────────────────────┐
                        │   GameModel (SwiftUI)   │
                        └────────────┬────────────┘
                                     │
                        ┌────────────▼────────────┐
                        │  MetalRayRenderer.swift │
                        └────────────┬────────────┘
                                     │
           ┌─────────────────────────┼─────────────────────────┐
           │                         │                         │
┌──────────▼──────────┐   ┌──────────▼──────────┐   ┌──────────▼──────────┐
│ Acceleration Struct │   │   RayShaders.metal  │   │ ChiptuneAudioEngine │
│ (MTLAcceleration)   │   │  (3-Bounce Path-Tr) │   │   (AVAudioEngine)   │
└─────────────────────┘   └─────────────────────┘   └─────────────────────┘
```

- **Path Tracing Físico de 3 Rebotes:** Renderizado continuo en GPU usando la API nativa `MTLAccelerationStructure` e `intersector<triangle_data, instancing>`.
- **Generación Procedural en Tiempo de Ejecución:** Mallas, texturas PBR, juntas de baldosines y cáusticas de agua se calculan matemáticamente en la GPU.
- **Rendimiento de Hardware:** 60 FPS estables consumiendo solo ~35% de GPU y ~5% de CPU.
- **Multijugador P2P Local:** Soporta juego cooperativo y control remoto táctico mediante `MultipeerConnectivity` por Wi-Fi/Bluetooth.

---

## 💻 Requisitos de Compilación y Ejecución

- **macOS:** Sonoma 14.0 o posterior con Xcode 15+
- **Dispositivo Objetivo:** iPhone 15 Pro / 15 Pro Max (o cualquier dispositivo iOS 17+ con soporte Metal Ray Tracing)

```bash
# Compilar e instalar en tu iPhone desde la terminal:
ruby generate_project.rb
xcodebuild -project SalonJoystick3D.xcodeproj -scheme SalonJoystick3D -sdk iphoneos build
```
