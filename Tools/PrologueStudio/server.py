#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import sys
import subprocess
import urllib.parse
import shutil
import cgi
import wave
import struct

PORT = 8765
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PUBLIC_DIR = os.path.join(BASE_DIR, "public")
PROJECT_DIR = os.path.dirname(os.path.dirname(BASE_DIR))
ASSETS_DIR = os.path.join(PROJECT_DIR, "Assets.xcassets")

CHAPTERS = [
    {
        "id": 0,
        "title": "Capítulo I • El Reino de Lumina",
        "subtitle": "La armonía de los Slimes y el secreto cuántico de la luz",
        "badge": "ORIGEN ANCESTRAL",
        "panel": "ProloguePanel1.imageset/prologuepanel1.jpg",
        "scriptES": "Registro de emergencia cuántica cero siete. Si recibes esta frecuencia... el Gran Salón de Lumina ha caído. No siempre fuimos soldados. Éramos una pacífica civilización de slimes de gelatina bioluminiscente, guardianes del secreto cósmico de la luz pura."
    },
    {
        "id": 1,
        "title": "Capítulo II • La Invasión Fotófaga",
        "subtitle": "Autómatas biomecánicos descendiendo del vacío estelar",
        "badge": "AMENAZA CÓSMICA",
        "panel": "ProloguePanel2.imageset/prologuepanel2.jpg",
        "scriptES": "Pero en la noche del Eclipse Eterno, ellos descendieron de las estrellas... Los Fotófagos. Autómatas biomecánicos colosales devoradores de energía, decididos a saquear nuestra tecnología de iluminación para saciar el frío vacío de sus mundos muertos."
    },
    {
        "id": 2,
        "title": "Capítulo III • La Arena y las Armas de Luz",
        "subtitle": "Blaster Láser, Escudo Espejo y las 4 luminarias maestras",
        "badge": "OBJETIVO TÁCTICO",
        "panel": "ProloguePanel3.imageset/prologuepanel3.jpg",
        "scriptES": "Nos confinaron en esta arena de pruebas holográfica. Drenaron el cien por ciento de las luces para debilitarnos. Tu misión es sagrada: empuña el Blaster Fotónico y el Escudo Espejo, y reactiva las cuatro luminarias maestras. Cada luz devuelve la energía al sistema."
    },
    {
        "id": 3,
        "title": "Capítulo IV • La Refracción y el Salón Arcoíris",
        "subtitle": "Espejos, fluidos cuánticos y el tobogán subterráneo",
        "badge": "MECÁNICA FOTÓNICA",
        "panel": "ProloguePanel4.imageset/prologuepanel4.jpg",
        "scriptES": "La piscina no es agua ordinaria: es un condensador cuántico de refracción. Usa tu linterna y tu láser reflectante para doblar los haces contra los espejos. Cuando alcances la saturación total de luz, el tobogán abrirá el portal subterráneo hacia el legendario Gran Salón Arcoíris."
    },
    {
        "id": 4,
        "title": "Capítulo V • La Revelación Final",
        "subtitle": "El secreto que cambiará el destino del cosmos para siempre",
        "badge": "GIRO DE GUIÓN // SPOILER",
        "panel": "ProloguePanel5.imageset/prologuepanel5.jpg",
        "scriptES": "Pero escucha la verdad oculta que nadie te dijo... Los invasores contra los que luchas no son monstruos de otra galaxia. Son NUESTROS PROPIOS HERMANOS. Son los slimes del futuro lejano, que renunciaron a su cuerpo orgánico y se transformaron en titanio para no morir de frío. No vienen a destruirnos... vienen desesperados a buscar la luz que perdieron al deshumanizarse. ¡No luches con odio! Enciende las luces, alcanza el cien por ciento... ¡y devuélveles la vida a través del Arcoíris!"
    }
]

def process_audio_filter(input_wav, output_wav, filter_type):
    # Reads 16-bit PCM wav and applies filter
    try:
        import numpy as np
        with wave.open(input_wav, 'r') as wf:
            n_channels = wf.getnchannels()
            sampwidth = wf.getsampwidth()
            framerate = wf.getframerate()
            n_frames = wf.getnframes()
            raw_data = wf.readframes(n_frames)

        if sampwidth == 2:
            dtype = np.int16
        else:
            dtype = np.int16

        samples = np.frombuffer(raw_data, dtype=dtype).astype(np.float32)
        if n_channels == 2:
            samples = samples.reshape(-1, 2)
            left = samples[:, 0]
            right = samples[:, 1]
        else:
            left = samples
            right = samples.copy()

        # Normalize to -1.0 .. 1.0
        max_val = max(np.max(np.abs(left)), 1.0)
        left /= max_val
        right /= max_val

        if filter_type == "cinematic":
            # Warm broadcast movie trailer EQ: gentle saturation + bass warmth
            # Simple bass boost around 120Hz
            t = np.arange(len(left)) / framerate
            # Warm soft clipping
            left = np.tanh(left * 1.35) * 0.92
            right = np.tanh(right * 1.35) * 0.92

        elif filter_type == "hologram":
            # Radio comms / emergency beacon: bandpass + subtle ring mod
            carrier = np.sin(2 * np.pi * 32.0 * np.arange(len(left)) / framerate) * 0.08
            left = (left + left * carrier) * 1.2
            right = (right + right * carrier) * 1.2
            left = np.clip(left, -0.92, 0.92)
            right = np.clip(right, -0.92, 0.92)

        else: # clean
            left = left * 0.92
            right = right * 0.92

        # Interleave
        out_samples = np.empty((len(left) * 2,), dtype=np.int16)
        out_samples[0::2] = (left * 32767).astype(np.int16)
        out_samples[1::2] = (right * 32767).astype(np.int16)

        with wave.open(output_wav, 'w') as wf:
            wf.setnchannels(2)
            wf.setsampwidth(2)
            wf.setframerate(framerate)
            wf.writeframes(out_samples.tobytes())

    except Exception as e:
        print(f"[Warning] Audio DSP fallback to direct copy: {e}")
        shutil.copy(input_wav, output_wav)

class StudioHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PUBLIC_DIR, **kwargs)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/synth/get-levels":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({
                "volBgm": 42,
                "volSwim": 22,
                "volAmb": 18,
                "swimTone": 180
            }).encode("utf-8"))
            return

        if path == "/api/chapters":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            
            # Check recorded status
            res = []
            for ch in CHAPTERS:
                ch_copy = dict(ch)
                ds_path = os.path.join(ASSETS_DIR, f"PrologueAudio{ch['id']}_es.dataset")
                ch_copy["has_audio"] = os.path.exists(ds_path)
                res.append(ch_copy)

            self.wfile.write(json.dumps(res, ensure_ascii=False).encode("utf-8"))
            return

        if path.startswith("/assets/panel/"):
            try:
                ch_id = int(path.split("/")[-1])
                panel_rel = CHAPTERS[ch_id]["panel"]
                panel_path = os.path.join(ASSETS_DIR, panel_rel)
                if os.path.exists(panel_path):
                    self.send_response(200)
                    self.send_header("Content-Type", "image/jpeg")
                    self.send_header("Cache-Control", "max-age=3600")
                    self.end_headers()
                    with open(panel_path, "rb") as f:
                        shutil.copyfileobj(f, self.wfile)
                    return
            except Exception as e:
                print(f"Error serving panel: {e}")

        if path == "/assets/theme":
            theme_path = os.path.join(ASSETS_DIR, "PrologueTheme.dataset", "audio.m4a")
            if os.path.exists(theme_path):
                self.send_response(200)
                self.send_header("Content-Type", "audio/mp4")
                self.send_header("Accept-Ranges", "bytes")
                self.end_headers()
                with open(theme_path, "rb") as f:
                    shutil.copyfileobj(f, self.wfile)
                return

        return super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/save-audio":
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(content_length)
                
                # Check for boundary in content-type
                content_type = self.headers.get("Content-Type", "")
                
                # We also support raw JSON or simple multipart
                # Easiest: JSON with base64, or multipart
                if "multipart/form-data" in content_type:
                    boundary = content_type.split("boundary=")[1].encode()
                    parts = body.split(b"--" + boundary)
                    
                    audio_data = None
                    ch_id = 0
                    filter_mode = "cinematic"
                    
                    for part in parts:
                        if b'name="chapter"' in part:
                            ch_id = int(part.split(b"\r\n\r\n")[1].split(b"\r\n")[0].decode())
                        elif b'name="filter"' in part:
                            filter_mode = part.split(b"\r\n\r\n")[1].split(b"\r\n")[0].decode()
                        elif b'name="audio"' in part:
                            audio_data = part.split(b"\r\n\r\n")[1].rstrip(b"\r\n")

                    if audio_data:
                        raw_temp = f"/tmp/take_raw_{ch_id}.bin"
                        wav_temp = f"/tmp/take_{ch_id}.wav"
                        dsp_temp = f"/tmp/take_dsp_{ch_id}.wav"
                        m4a_target = f"/tmp/take_{ch_id}.m4a"

                        with open(raw_temp, "wb") as f:
                            f.write(audio_data)

                        # If audio is already WAV (starts with RIFF), direct use!
                        if audio_data.startswith(b'RIFF'):
                            shutil.copyfile(raw_temp, wav_temp)
                        else:
                            subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", raw_temp, wav_temp], check=True)

                        process_audio_filter(wav_temp, dsp_temp, filter_mode)
                        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "192000", dsp_temp, m4a_target], check=True)

                        # Copy to dataset
                        dataset_dir = os.path.join(ASSETS_DIR, f"PrologueAudio{ch_id}_es.dataset")
                        os.makedirs(dataset_dir, exist_ok=True)
                        
                        target_audio = os.path.join(dataset_dir, "audio.m4a")
                        shutil.copyfile(m4a_target, target_audio)

                        contents_json = {
                            "data": [
                                {
                                    "filename": "audio.m4a",
                                    "idiom": "universal"
                                }
                            ],
                            "info": {
                                "author": "xcode",
                                "version": 1
                            }
                        }
                        with open(os.path.join(dataset_dir, "Contents.json"), "w") as f:
                            json.dump(contents_json, f, indent=2)

                        self.send_response(200)
                        self.send_header("Content-Type", "application/json")
                        self.end_headers()
                        self.wfile.write(json.dumps({
                            "success": True,
                            "chapter": ch_id,
                            "message": f"¡Capítulo {ch_id + 1} grabado e instalado en Assets con éxito!"
                        }).encode("utf-8"))
                        return

            except Exception as e:
                print(f"Error handling upload: {e}")
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": str(e)}).encode("utf-8"))
                return

        if path == "/api/synth/apply-levels":
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(content_length)
                data = json.loads(body.decode("utf-8"))

                vol_bgm = float(data.get("volBgm", 42)) / 100.0
                vol_swim = float(data.get("volSwim", 22)) / 100.0
                vol_amb = float(data.get("volAmb", 18)) / 100.0
                swim_tone = float(data.get("swimTone", 180))

                # Update ContentView.swift
                cv_path = os.path.join(PROJECT_DIR, "Sources", "SalonJoystick3D", "ContentView.swift")
                with open(cv_path, "r", encoding="utf-8") as f:
                    content = f.read()

                # Replace targetVol for underwater
                import re
                content = re.sub(
                    r'if isUnderwater \{\s*activeBuffer = self\.underwaterMusicBuffer \?\? self\.musicBuffer\s*targetVol = self\.musicEnabled \? \d+\.\d+ : 0',
                    f'if isUnderwater {{\n                activeBuffer = self.underwaterMusicBuffer ?? self.musicBuffer\n                targetVol = self.musicEnabled ? {vol_bgm:.2f} : 0',
                    content
                )

                # Replace splashNode.volume for swim stroke
                content = re.sub(
                    r'self\.splashNode\.volume = \d+\.\d+ \+ max\(0, min\(1, intensity\)\) \* \d+\.\d+',
                    f'self.splashNode.volume = {vol_swim:.2f} + max(0, min(1, intensity)) * 0.10',
                    content
                )

                with open(cv_path, "w", encoding="utf-8") as f:
                    f.write(content)

                # Compile and install
                cmd = f"cd '{PROJECT_DIR}' && xcodebuild -scheme SalonJoystick3D -destination 'id=00008130-00040D8C3489001C' build && xcrun devicectl device install app --device 00008130-00040D8C3489001C /Users/estebanavila/Library/Developer/Xcode/DerivedData/SalonJoystick3D-afpqtvjivuqgwmapvnkigdvmgdya/Build/Products/Debug-iphoneos/SalonJoystick3D.app"
                p = subprocess.run(cmd, shell=True, capture_output=True, text=True)

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({
                    "success": p.returncode == 0,
                    "message": f"Niveles guardados (Música: {int(vol_bgm*100)}%, Nado: {int(vol_swim*100)}%) e instalados en iPhone.",
                    "output": p.stdout[-600:] if p.returncode == 0 else p.stderr[-600:]
                }).encode("utf-8"))
                return
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": str(e)}).encode("utf-8"))
                return

        if path == "/api/install-device":
            try:
                # Trigger xcodebuild & devicectl
                cmd = f"cd '{PROJECT_DIR}' && xcodebuild -scheme SalonJoystick3D -destination 'id=00008130-00040D8C3489001C' build && xcrun devicectl device install app --device 00008130-00040D8C3489001C /Users/estebanavila/Library/Developer/Xcode/DerivedData/SalonJoystick3D-afpqtvjivuqgwmapvnkigdvmgdya/Build/Products/Debug-iphoneos/SalonJoystick3D.app"
                p = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({
                    "success": p.returncode == 0,
                    "output": p.stdout[-600:] if p.returncode == 0 else p.stderr[-600:]
                }).encode("utf-8"))
                return
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": str(e)}).encode("utf-8"))
                return

        self.send_response(404)
        self.end_headers()

def run_server():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), StudioHandler) as httpd:
        print(f"🎤 Lumina Karaoke Studio corriendo en http://localhost:{PORT}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServidor detenido.")

if __name__ == "__main__":
    run_server()

