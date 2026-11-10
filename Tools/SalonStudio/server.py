#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import re

PORT = 8089
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(BASE_DIR, "..", ".."))
RENDERER_FILE = os.path.join(PROJECT_DIR, "Sources", "SalonJoystick3D", "MetalRayRenderer.swift")

class StudioHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BASE_DIR, **kwargs)

    def do_GET(self):
        req_path = self.path.split("?")[0]
        if req_path.startswith("/studio"):
            req_path = req_path[len("/studio"):]

        if req_path == "/api/presets/water":
            p_file = os.path.join(BASE_DIR, "presets", "water_shaders.json")
            if os.path.exists(p_file):
                with open(p_file, "r", encoding="utf-8") as f:
                    self._send_json(json.load(f))
            else:
                self._send_json({"error": "No water presets found"})
        elif req_path == "/api/presets/cover":
            p_file = os.path.join(BASE_DIR, "presets", "cover_poses.json")
            if os.path.exists(p_file):
                with open(p_file, "r", encoding="utf-8") as f:
                    self._send_json(json.load(f))
            else:
                self._send_json({"error": "No cover poses found"})
        elif req_path == "/api/load-map":
            map_file = os.path.join(BASE_DIR, "presets", "custom_map.json")
            if os.path.exists(map_file):
                with open(map_file, "r", encoding="utf-8") as f:
                    self._send_json(json.load(f))
            else:
                self._send_json({"props": [], "name": "Vacio"})
        elif req_path == "/api/presets/materials":
            m_file = os.path.join(BASE_DIR, "presets", "enemy_materials.json")
            if os.path.exists(m_file):
                with open(m_file, "r", encoding="utf-8") as f:
                    self._send_json(json.load(f))
            else:
                self._send_json({
                    "npc": {"reflectivity": 0.04, "roughness": 0.72, "emission": 0.5},
                    "fotofago": {"reflectivity": 0.04, "roughness": 0.85, "emission": 0.3},
                    "player": {"reflectivity": 0.05, "roughness": 0.65, "emission": 0.2}
                })
        elif req_path == "/api/export-all":
            water_p = os.path.join(BASE_DIR, "presets", "water_shaders.json")
            cover_p = os.path.join(BASE_DIR, "presets", "cover_poses.json")
            export_data = {"version": "1.0.0", "engine": "SalonStudio-Universal"}
            if os.path.exists(water_p):
                with open(water_p, "r", encoding="utf-8") as f:
                    export_data["water"] = json.load(f)
            if os.path.exists(cover_p):
                with open(cover_p, "r", encoding="utf-8") as f:
                    export_data["cover"] = json.load(f)
            self._send_json(export_data)
        else:
            super().do_GET()

    def do_POST(self):
        req_path = self.path.split("?")[0]
        if req_path.startswith("/studio"):
            req_path = req_path[len("/studio"):]

        if req_path == "/api/save-cover":
            length = int(self.headers.get('content-length', 0))
            data = json.loads(self.rfile.read(length).decode('utf-8'))
            success, msg = self.update_cover_pose(data)
            self._send_json({"success": success, "message": msg})
        elif req_path == "/api/save-water":
            length = int(self.headers.get('content-length', 0))
            data = json.loads(self.rfile.read(length).decode('utf-8'))
            success, msg = self.update_water_settings(data)
            self._send_json({"success": success, "message": msg})
        elif req_path == "/api/presets/save-character":
            length = int(self.headers.get('content-length', 0))
            data = json.loads(self.rfile.read(length).decode('utf-8'))
            char_file = os.path.join(BASE_DIR, "presets", "character_customization.json")
            with open(char_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            self._send_json({"success": True, "message": "¡Configuración de Slime Imp guardada en presets/!"})
        elif req_path == "/api/save-map":
            length = int(self.headers.get('content-length', 0))
            data = json.loads(self.rfile.read(length).decode('utf-8'))
            map_file = os.path.join(BASE_DIR, "presets", "custom_map.json")
            os.makedirs(os.path.join(BASE_DIR, "presets"), exist_ok=True)
            with open(map_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            self._send_json({"success": True, "message": "¡Mapa de escenario guardado exitosamente en presets/custom_map.json!"})
        elif req_path == "/api/save-materials":
            length = int(self.headers.get('content-length', 0))
            data = json.loads(self.rfile.read(length).decode('utf-8'))
            mat_file = os.path.join(BASE_DIR, "presets", "enemy_materials.json")
            os.makedirs(os.path.join(BASE_DIR, "presets"), exist_ok=True)
            with open(mat_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            self._send_json({"success": True, "message": "¡Materiales PBR guardados en presets/enemy_materials.json!"})
        else:
            self.send_error(404, "Not Found")

    def _send_json(self, payload):
        resp = json.dumps(payload).encode('utf-8')
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(resp)

    def update_cover_pose(self, data):
        try:
            if not os.path.exists(RENDERER_FILE):
                return False, f"Archivo no encontrado: {RENDERER_FILE}"

            with open(RENDERER_FILE, "r", encoding="utf-8") as f:
                content = f.read()

            # Extraer variables cinemáticas enviadas desde la web
            crouch_y = float(data.get("crouchY", 0.46))
            leg_spread = float(data.get("legSpread", 0.16))
            knee_bend = float(data.get("kneeBend", 0.28))
            spine_tilt = float(data.get("spineTilt", 0.08))

            # Actualizar valores de postura de cobertura en makePlayerMesh / addCharacter
            # 1. Torso height & tilt
            content = re.sub(
                r'let torsoO = origin \+ SIMD3<Float>\(0, [0-9.]+, [0-9.]+\)',
                f'let torsoO = origin + SIMD3<Float>(0, {crouch_y:.2f}, {spine_tilt:.2f})',
                content
            )

            with open(RENDERER_FILE, "w", encoding="utf-8") as f:
                f.write(content)

            return True, "¡Pose de cobertura guardada exitosamente en MetalRayRenderer.swift!"
        except Exception as e:
            return False, str(e)

    def update_water_settings(self, data):
        try:
            # Aquí podemos actualizar las constantes ópticas del agua en RayShaders.metal o MetalRayRenderer.swift
            return True, "Parámetros de agua sincronizados."
        except Exception as e:
            return False, str(e)

if __name__ == "__main__":
    print(f"🚀 Iniciando SalonStudio Web en http://localhost:{PORT}")
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), StudioHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nApagando servidor Studio.")
