// Lumina Karaoke Teleprompter & Voice Studio Client
let chapters = [];
let currentChapterIndex = 0;
let isRecording = false;
let recordedBlob = null;
let audioContext = null;
let analyser = null;
let sourceNode = null;
let animFrameId = null;
let karaokeInterval = null;
let currentWordIndex = 0;
let words = [];

// DOM Elements
const chapterTabs = document.getElementById('chapterTabs');
const panelBadge = document.getElementById('panelBadge');
const panelPart = document.getElementById('panelPart');
const panelImage = document.getElementById('panelImage');
const chapterTitle = document.getElementById('chapterTitle');
const chapterSubtitle = document.getElementById('chapterSubtitle');
const karaokeText = document.getElementById('karaokeText');
const recordBtn = document.getElementById('recordBtn');
const recordBtnText = document.getElementById('recordBtnText');
const playTakeBtn = document.getElementById('playTakeBtn');
const saveBtn = document.getElementById('saveBtn');
const statusNotice = document.getElementById('statusNotice');
const pacerSpeed = document.getElementById('pacerSpeed');
const speedVal = document.getElementById('speedVal');
const themeToggleBtn = document.getElementById('themeToggleBtn');
const themeStatus = document.getElementById('themeStatus');
const bgAudio = document.getElementById('bgAudio');
const deployBtn = document.getElementById('deployBtn');
const visualizerCanvas = document.getElementById('visualizerCanvas');
const canvasCtx = visualizerCanvas.getContext('2d');
const takePlayer = document.getElementById('takePlayer');

let bgMusicEnabled = true;

// 1. Fetch Chapters from Server
async function loadChapters() {
  try {
    const res = await fetch('/api/chapters');
    chapters = await res.json();
    renderTabs();
    selectChapter(0);
  } catch (err) {
    statusNotice.innerHTML = `<span style="color:#ff0844">Error cargando capítulos: ${err}</span>`;
  }
}

// 2. Render Chapter Tabs
function renderTabs() {
  chapterTabs.innerHTML = '';
  chapters.forEach((ch, idx) => {
    const btn = document.createElement('button');
    btn.className = `tab-btn ${idx === currentChapterIndex ? 'active' : ''}`;
    btn.innerHTML = `
      <span class="tab-tag">PARTE ${idx + 1}</span>
      <span class="tab-name">${ch.title.split('•')[0].trim()}</span>
      <span class="tab-status" id="tabStatus${idx}">${ch.has_audio ? '🟢 Listo' : '⚪ Sin grabar'}</span>
    `;
    btn.onclick = () => selectChapter(idx);
    chapterTabs.appendChild(btn);
  });
}

// 3. Select Chapter
function selectChapter(idx) {
  if (isRecording) stopRecording();
  currentChapterIndex = idx;
  const ch = chapters[idx];

  // Update Active Tab
  document.querySelectorAll('.tab-btn').forEach((b, i) => {
    b.classList.toggle('active', i === idx);
  });

  // Update UI Elements
  panelBadge.innerText = ch.badge;
  panelPart.innerText = `PARTE ${idx + 1} / ${chapters.length}`;
  panelImage.src = `/assets/panel/${idx}?t=${Date.now()}`;
  chapterTitle.innerText = ch.title;
  chapterSubtitle.innerText = ch.subtitle;

  // Split Script into Words for Karaoke Teleprompter
  words = ch.scriptES.split(' ');
  karaokeText.innerHTML = words.map((w, i) => `<span class="karaoke-word" id="word_${i}">${w}</span>`).join(' ');

  // Reset Take state
  recordedBlob = null;
  playTakeBtn.disabled = true;
  saveBtn.disabled = true;
  takePlayer.style.display = 'none';
  takePlayer.src = '';
  resetKaraokeHighlight();
  statusNotice.innerHTML = `Capítulo ${idx + 1} listo. Presiona <b>INICIAR GRABACIÓN</b> para comenzar.`;
}

function resetKaraokeHighlight() {
  clearInterval(karaokeInterval);
  currentWordIndex = 0;
  document.querySelectorAll('.karaoke-word').forEach(el => {
    el.classList.remove('active', 'past');
  });
}

// 4. Karaoke Pacing Engine
function startKaraokePacing() {
  resetKaraokeHighlight();
  const speed = parseFloat(pacerSpeed.value);
  const intervalMs = Math.round(290 / speed);

  karaokeInterval = setInterval(() => {
    if (currentWordIndex >= words.length) {
      clearInterval(karaokeInterval);
      return;
    }

    const prevEl = document.getElementById(`word_${currentWordIndex - 1}`);
    if (prevEl) {
      prevEl.classList.remove('active');
      prevEl.classList.add('past');
    }

    const currEl = document.getElementById(`word_${currentWordIndex}`);
    if (currEl) {
      currEl.classList.add('active');
      currEl.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }

    currentWordIndex++;
  }, intervalMs);
}

// 5. Universal WAV Audio Recorder (100% compatible with Mac/Safari/Chrome)
let wavStream = null;
let scriptProcessor = null;
let audioChunksWav = [];

async function startRecording() {
  try {
    audioContext = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 44100 });
    if (audioContext.state === 'suspended') {
      await audioContext.resume();
    }

    wavStream = await navigator.mediaDevices.getUserMedia({ 
      audio: {
        echoCancellation: false,
        noiseSuppression: false,
        autoGainControl: false
      } 
    });

    // Audio Visualizer
    setupVisualizer(wavStream);

    // Play Backing Track softly if enabled
    if (bgMusicEnabled) {
      bgAudio.volume = 0.20;
      bgAudio.currentTime = 0;
      bgAudio.play().catch(e => console.log('Autoplay muted:', e));
    }

    sourceNode = audioContext.createMediaStreamSource(wavStream);
    // Buffer size 4096, 1 channel
    scriptProcessor = audioContext.createScriptProcessor(4096, 1, 1);
    audioChunksWav = [];

    scriptProcessor.onaudioprocess = (e) => {
      if (!isRecording) return;
      const input = e.inputBuffer.getChannelData(0);
      audioChunksWav.push(new Float32Array(input));
    };

    sourceNode.connect(scriptProcessor);
    scriptProcessor.connect(audioContext.destination);

    isRecording = true;
    recordBtn.classList.add('recording');
    recordBtnText.innerText = '⏹️ DETENER GRABACIÓN (Espacio)';

    takePlayer.style.display = 'none';
    playTakeBtn.disabled = true;
    saveBtn.disabled = true;

    // Start Karaoke Pacer
    startKaraokePacing();
    statusNotice.innerHTML = `🎙️ <b style="color:#00f2fe">GRABANDO AHORA</b> — Lee el texto iluminado con tu entonación dramática.`;

  } catch (err) {
    alert('Permiso de micrófono o error de audio: ' + err.message);
  }
}

function stopRecording() {
  if (!isRecording) return;
  isRecording = false;
  recordBtn.classList.remove('recording');
  recordBtnText.innerText = '🎙️ GRABAR OTRA VEZ (Espacio)';

  if (scriptProcessor) scriptProcessor.disconnect();
  if (sourceNode) sourceNode.disconnect();
  if (wavStream) {
    wavStream.getTracks().forEach(t => t.stop());
  }

  clearInterval(karaokeInterval);
  if (bgMusicEnabled) {
    bgAudio.pause();
  }
  cancelAnimationFrame(animFrameId);

  // Encode WAV
  let totalLength = 0;
  for (const chunk of audioChunksWav) {
    totalLength += chunk.length;
  }
  const merged = new Float32Array(totalLength);
  let offset = 0;
  for (const chunk of audioChunksWav) {
    merged.set(chunk, offset);
    offset += chunk.length;
  }

  recordedBlob = encodeWAV(merged, audioContext.sampleRate || 44100);

  // Set up Native Player
  const audioUrl = URL.createObjectURL(recordedBlob);
  takePlayer.src = audioUrl;
  takePlayer.style.display = 'block';
  playTakeBtn.disabled = false;
  saveBtn.disabled = false;

  const durationSec = (totalLength / (audioContext.sampleRate || 44100)).toFixed(1);
  statusNotice.innerHTML = `✨ ¡Toma grabada (${durationSec}s)! Puedes escucharla abajo o pulsar <b>Guardar en el Juego</b>.`;
}

function encodeWAV(samples, sampleRate) {
  const buffer = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(buffer);

  function writeString(offset, string) {
    for (let i = 0; i < string.length; i++) {
      view.setUint8(offset + i, string.charCodeAt(i));
    }
  }

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + samples.length * 2, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // Mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true); // Block align
  view.setUint16(34, 16, true); // 16-bit
  writeString(36, 'data');
  view.setUint32(40, samples.length * 2, true);

  let index = 44;
  for (let i = 0; i < samples.length; i++) {
    let s = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(index, s < 0 ? s * 0x8000 : s * 0x7FFF, true);
    index += 2;
  }

  return new Blob([view], { type: 'audio/wav' });
}

// Toggle Record Button
recordBtn.onclick = () => {
  if (isRecording) {
    stopRecording();
  } else {
    startRecording();
  }
};

// Spacebar shortcut
window.onkeydown = (e) => {
  if (e.code === 'Space' && e.target.tagName !== 'INPUT') {
    e.preventDefault();
    recordBtn.click();
  }
};

// 6. Play Recorded Take
playTakeBtn.onclick = () => {
  if (!recordedBlob) return;
  takePlayer.currentTime = 0;
  takePlayer.play().then(() => {
    statusNotice.innerHTML = `▶️ <b style="color:#00f2fe">Reproduciendo tu toma...</b>`;
  }).catch(err => {
    statusNotice.innerHTML = `<span style="color:#ff0844">Error al reproducir: ${err.message}</span>`;
  });
};

takePlayer.onended = () => {
  statusNotice.innerHTML = `✅ Reproducción finalizada. Pulsa <b>Guardar en el Juego</b> para confirmar.`;
};

takePlayer.onerror = (e) => {
  statusNotice.innerHTML = `<span style="color:#ff0844">Error en reproductor nativo.</span>`;
};

// 7. Save Take to Game Assets (POST /api/save-audio)
saveBtn.onclick = async () => {
  if (!recordedBlob) return;

  saveBtn.disabled = true;
  saveBtn.innerText = '⏳ Aplicando Filtro y Guardando...';
  statusNotice.innerHTML = 'Procesando tu voz e insertándola en los assets del juego...';

  const filter = document.querySelector('input[name="voiceFilter"]:checked').value;
  const formData = new FormData();
  formData.append('chapter', currentChapterIndex);
  formData.append('filter', filter);
  formData.append('audio', recordedBlob, 'take.wav');

  try {
    const res = await fetch('/api/save-audio', {
      method: 'POST',
      body: formData
    });
    const result = await res.json();

    if (result.success) {
      statusNotice.innerHTML = `<span style="color:#38ef7d">✅ ${result.message}</span>`;
      saveBtn.innerText = '✨ ¡Guardado con Éxito!';
      
      // Update Tab Status Badge
      const statusBadge = document.getElementById(`tabStatus${currentChapterIndex}`);
      if (statusBadge) statusBadge.innerText = '🟢 Listo';

      // Automatically recommend next chapter
      setTimeout(() => {
        saveBtn.innerText = '✨ Guardar en el Juego';
        if (currentChapterIndex < chapters.length - 1) {
          selectChapter(currentChapterIndex + 1);
        }
      }, 1400);

    } else {
      throw new Error(result.error);
    }
  } catch (err) {
    statusNotice.innerHTML = `<span style="color:#ff0844">Error al guardar: ${err.message}</span>`;
    saveBtn.disabled = false;
    saveBtn.innerText = '✨ Reintentar Guardar';
  }
};

// 8. Visualizer Canvas
function setupVisualizer(stream) {
  if (!audioContext) audioContext = new (window.AudioContext || window.webkitAudioContext)();
  analyser = audioContext.createAnalyser();
  analyser.fftSize = 128;
  const vSource = audioContext.createMediaStreamSource(stream);
  vSource.connect(analyser);

  const bufferLength = analyser.frequencyBinCount;
  const dataArray = new Uint8Array(bufferLength);

  function draw() {
    animFrameId = requestAnimationFrame(draw);
    analyser.getByteFrequencyData(dataArray);

    canvasCtx.clearRect(0, 0, visualizerCanvas.width, visualizerCanvas.height);
    const barWidth = (visualizerCanvas.width / bufferLength) * 2.2;
    let x = 0;

    for (let i = 0; i < bufferLength; i++) {
      const barHeight = (dataArray[i] / 255) * visualizerCanvas.height * 0.9;
      const grad = canvasCtx.createLinearGradient(0, visualizerCanvas.height, 0, 0);
      grad.addColorStop(0, '#00f2fe');
      grad.addColorStop(1, '#ff007a');

      canvasCtx.fillStyle = grad;
      canvasCtx.fillRect(x, visualizerCanvas.height - barHeight, barWidth - 1, barHeight);
      x += barWidth;
    }
  }
  draw();
}

// 9. Speed Control
pacerSpeed.oninput = () => {
  speedVal.innerText = `${pacerSpeed.value}x`;
};

// 10. Background Music Toggle
themeToggleBtn.onclick = () => {
  bgMusicEnabled = !bgMusicEnabled;
  themeStatus.innerText = bgMusicEnabled ? 'ON' : 'OFF';
  themeToggleBtn.classList.toggle('btn-secondary', bgMusicEnabled);
  if (!bgMusicEnabled && !bgAudio.paused) bgAudio.pause();
};

// 11. Deploy to iPhone Button
deployBtn.onclick = async () => {
  deployBtn.disabled = true;
  deployBtn.innerText = '⏳ Compilando e Instalando...';
  statusNotice.innerHTML = `Compilando Xcode e instalando en tu iPhone 15 Pro Max...`;

  try {
    const res = await fetch('/api/install-device', { method: 'POST' });
    const result = await res.json();
    if (result.success) {
      alert('🚀 ¡Instalación exitosa en tu iPhone con tus nuevas voces!');
      statusNotice.innerHTML = `🟢 App instalada con éxito en tu iPhone 15 Pro Max.`;
    } else {
      alert('Error en compilación: ' + result.output);
    }
  } catch (err) {
    alert('Error conectando: ' + err);
  } finally {
    deployBtn.disabled = false;
    deployBtn.innerText = '🚀 Compilar e Instalar en iPhone';
  }
};

// Init
loadChapters();
