# SalonStudio 3D - Motor Visual y Suite de Herramientas Universales

**Ubicación:** `Tools/SalonStudio/`  
**Objetivo:** Herramienta visual web modular y agnóstica de motor diseñada para inspeccionar, calibrar cinemática/rigging (posturas tácticas estilo GTA/Gears) y simular fluidos/shaders de agua en tiempo real con Three.js y WebGL.

---

## 🛠️ Arquitectura Modular y Desacoplada

La suite está estructurada para ser **100% reutilizable en cualquier juego futuro** (Metal/Swift, Godot 4, Unity, Unreal Engine 5 o WebGL/Three.js):

```
Tools/SalonStudio/
├── index.html        # Viewport 3D reactivo (Three.js r128 + OrbitControls + Glassmorphism HUD)
├── studio.js         # Lógica visual: cinemática de huesos, simulación ondulatoria, props realistas
├── server.py         # Servidor REST ultraligero en Python 3 (cero dependencias externas / npm)
├── presets/          # Especificaciones abiertas en formato JSON universal
│   ├── water_shaders.json   # Coeficientes ópticos: reflectividad, claridad, ondas, cáusticas
│   └── cover_poses.json     # Ángulos articulares: flexión de rodillas, cadera, inclinación de espina
└── README.md         # Documentación de integración y endpoints
```

---

## 🚀 Cómo Ejecutarlo

Solo requiere **Python 3** (instalado de serie en macOS y Linux):

```bash
cd Tools/SalonStudio
python3 server.py
```
Abre en tu navegador: **`http://localhost:8089`**

---

## 🔌 API REST Universale para Motores de Juego

Cualquier motor o script de compilación puede consumir o guardar parámetros mediante HTTP:

| Método | Endpoint | Descripción |
|---|---|---|
| `GET` | `/api/presets/water` | Obtiene la biblioteca de preajustes ópticos de agua |
| `GET` | `/api/presets/cover` | Obtiene el catálogo de cinemática de cobertura |
| `POST` | `/api/save-cover` | Actualiza directamente los coeficientes en código fuente (Swift/Godot) |
| `POST` | `/api/save-water` | Sincroniza variables de shaders en tiempo real |
| `GET` | `/api/export-all` | Descarga el snapshot completo en formato JSON para importar en cualquier engine |

---

## 🌊 Escenario de Agua y Referencias Visuales

Para que el agua sea visualmente reconocible como **líquido con volumen y profundidad**, el escenario incluye:
1. **Escalera de acero inoxidable cromada**: Con peldaños sumergidos bajo el agua. La distorsión y refracción de los peldaños bajo las ondas es la referencia óptica #1 de una piscina real.
2. **Pelota de playa tricolor inflable**: Flotando y oscilando en sintonía con las olas.
3. **Línea de boyas de carril**: Flotadores bicolores que delimitan la zona acuática.
4. **Flotador salvavidas con cinchas blancas**: Con balanceo hidrodinámico.
5. **Tumbona de terraza resort**: Aporta escala humana y contexto inmediato.
6. **Iluminación solar con brillos especulares**: Genera reflejos y destellos en las crestas del oleaje.
7. **Cáusticas proyectadas en el suelo**: Patrones de luz en movimiento sobre los azulejos sumergidos.
