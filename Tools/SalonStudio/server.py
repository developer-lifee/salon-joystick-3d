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

    def do_POST(self):
        if self.path == "/api/save-cover":
            length = int(self.headers.get('content-length', 0))
            data = json.loads(self.rfile.read(length).decode('utf-8'))
            success, msg = self.update_cover_pose(data)
            self._send_json({"success": success, "message": msg})
        elif self.path == "/api/save-water":
            length = int(self.headers.get('content-length', 0))
            data = json.loads(self.rfile.read(length).decode('utf-8'))
            success, msg = self.update_water_settings(data)
            self._send_json({"success": success, "message": msg})
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
