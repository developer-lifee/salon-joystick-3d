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

/* ==========================================================================
   🎛️ GAME AUDIO SYNTHESIZER & REAL-TIME MIXING CONSOLE
   ========================================================================== */

// Navigation Mode Switcher
const navVoiceBtn = document.getElementById('navVoiceBtn');
const navSynthBtn = document.getElementById('navSynthBtn');
const voiceStudioSection = document.getElementById('voiceStudioSection');
const synthStudioSection = document.getElementById('synthStudioSection');

navVoiceBtn.onclick = () => {
  navVoiceBtn.classList.add('active');
  navSynthBtn.classList.remove('active');
  voiceStudioSection.style.display = 'block';
  synthStudioSection.style.display = 'none';
};

navSynthBtn.onclick = () => {
  navSynthBtn.classList.add('active');
  navVoiceBtn.classList.remove('active');
  voiceStudioSection.style.display = 'none';
  synthStudioSection.style.display = 'block';
  initSynthStudio();
};

// Synth Audio Context and Nodes
let synthAudioCtx = null;
let bgmGainNode = null;
let sfxGainNode = null;
let ambGainNode = null;
let bgmSourceNode = null;
let ambSourceNode = null;

let isBgmPlaying = false;
let isAmbPlaying = false;
let isMasterSimActive = false;
let autoSwimInterval = null;

// Controls
const masterSimBtn = document.getElementById('masterSimBtn');
const masterSimText = document.getElementById('masterSimText');
const balanceBadge = document.getElementById('balanceBadge');
const meterBGM = document.getElementById('meterBGM');
const meterSFX = document.getElementById('meterSFX');
const bgmDbLabel = document.getElementById('bgmDbLabel');
const sfxDbLabel = document.getElementById('sfxDbLabel');
const deltaDbLabel = document.getElementById('deltaDbLabel');

const volBgmSlider = document.getElementById('volBgmSlider');
const volBgmVal = document.getElementById('volBgmVal');
const playBgmBtn = document.getElementById('playBgmBtn');

const toggleRhodes = document.getElementById('toggleRhodes');
const togglePad = document.getElementById('togglePad');
const toggleHarp = document.getElementById('toggleHarp');
const toggleBass = document.getElementById('toggleBass');

const volSwimSlider = document.getElementById('volSwimSlider');
const volSwimVal = document.getElementById('volSwimVal');
const swimToneSlider = document.getElementById('swimToneSlider');
const swimToneVal = document.getElementById('swimToneVal');
const triggerSwimBtn = document.getElementById('triggerSwimBtn');
const autoSwimBtn = document.getElementById('autoSwimBtn');
const autoSwimText = document.getElementById('autoSwimText');

const volAmbSlider = document.getElementById('volAmbSlider');
const volAmbVal = document.getElementById('volAmbVal');
const playAmbBtn = document.getElementById('playAmbBtn');

const applyMixBtn = document.getElementById('applyMixBtn');
const synthNotice = document.getElementById('synthNotice');

function getSynthAudioContext() {
  if (!synthAudioCtx) {
    synthAudioCtx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: 44100 });
  }
  if (synthAudioCtx.state === 'suspended') {
    synthAudioCtx.resume();
  }
  return synthAudioCtx;
}

// 1. Synthesize Pure Distortion-Free Underwater Symphony Buffer (24.0s)
function buildUnderwaterMusicBuffer(ctx) {
  const duration = 24.0;
  const sampleRate = ctx.sampleRate;
  const frameCount = sampleRate * duration;
  const buffer = ctx.createBuffer(2, frameCount, sampleRate);
  const left = buffer.getChannelData(0);
  const right = buffer.getChannelData(1);

  const chords = [
    [77.78, 116.54, 155.56, 196.00, 293.66, 349.23, 392.00], // Ebmaj9
    [65.41, 98.00,  155.56, 196.00, 233.08, 293.66, 392.00], // Cm9
    [51.91, 77.78,  130.81, 196.00, 261.63, 293.66, 392.00], // Abmaj9#11
    [58.27, 87.31,  116.54, 155.56, 174.61, 233.08, 293.66]  // Bbsus4
  ];
  const subBassFrequencies = [38.89, 32.70, 51.91, 58.27];
  const melodyNotes = [
    392.00, 349.23, 293.66, 233.08,
    261.63, 311.13, 392.00, 466.16,
    523.25, 466.16, 392.00, 293.66,
    311.13, 349.23, 293.66, 311.13
  ];

  const enableRhodes = toggleRhodes.checked;
  const enablePad = togglePad.checked;
  const enableHarp = toggleHarp.checked;
  const enableBass = toggleBass.checked;

  for (let frame = 0; frame < frameCount; frame++) {
    const time = frame / sampleRate;
    const section = Math.min(3, Math.floor(time / 6.0));
    const chord = chords[section];

    // 1. Lush Chorus Pad with Bounded Vibrato (zero distortion)
    let padL = 0;
    let padR = 0;
    const oceanSwell = 0.75 + 0.25 * Math.sin(2 * Math.PI * 0.12 * time);

    if (enablePad) {
      for (let idx = 0; idx < chord.length; idx++) {
        const noteFreq = chord[idx];
        const pPhase = 2 * Math.PI * noteFreq * time;
        const vibPhase = Math.sin(2 * Math.PI * 3.2 * time + idx) * 0.24;
        const detunePhase = 2 * Math.PI * (noteFreq * (1.0 + idx * 0.0012)) * time;
        const wave1 = Math.sin(pPhase + vibPhase);
        const wave2 = Math.sin(detunePhase - vibPhase + 0.5) * 0.45;
        const voiceAmp = (0.022 / (idx + 1)) * 1.8;
        padL += (wave1 + wave2) * voiceAmp;
        padR += (wave2 + wave1) * voiceAmp;
      }
      padL *= oceanSwell;
      padR *= oceanSwell;
    }

    // 2. Crystal Rhodes Electric Piano with Independent Phase
    let rhodesL = 0;
    let rhodesR = 0;
    if (enableRhodes) {
      const stepDuration = 1.50;
      const noteIdx = Math.min(melodyNotes.length - 1, Math.floor(time / stepDuration));
      const noteTime = time % stepDuration;
      const mAttack = Math.min(1.0, noteTime / 0.04);
      const mDecay = Math.exp(-noteTime * 1.8);
      const mEnv = mAttack * mDecay;
      const mFreq = melodyNotes[noteIdx];
      const vibOffset = (noteTime > 0.35 ? Math.sin(2 * Math.PI * 4.5 * (noteTime - 0.35)) * 0.22 : 0.0);
      const mPhase = 2 * Math.PI * mFreq * time + vibOffset;
      rhodesL = (Math.sin(mPhase) + Math.sin(mPhase * 2.0) * 0.18 + Math.sin(mPhase * 3.0) * 0.04) * mEnv * 0.052;
      rhodesR = (Math.sin(mPhase + 0.15) + Math.sin((mPhase + 0.15) * 2.0) * 0.18 + Math.sin((mPhase + 0.15) * 3.0) * 0.04) * mEnv * 0.052;
    }

    // 3. Liquid Harp Arpeggio
    let harpL = 0;
    let harpR = 0;
    if (enableHarp) {
      const arpStep = 0.25;
      const arpIdx = Math.floor(time / arpStep) % chord.length;
      const arpTime = time % arpStep;
      const arpEnv = Math.min(1.0, arpTime / 0.02) * Math.exp(-arpTime * 6.5);
      const arpHarpFreq = chord[arpIdx] * 2.0;
      const arpHarpPhase = 2 * Math.PI * arpHarpFreq * time;
      const arpPan = arpIdx / (chord.length - 1);
      const arpHarp = Math.sin(arpHarpPhase) * arpEnv * 0.016;
      harpL = arpHarp * (1.0 - arpPan * 0.6);
      harpR = arpHarp * (0.4 + arpPan * 0.6);
    }

    // 4. Sub-Bass
    let subBass = 0;
    if (enableBass) {
      const bassFreq = subBassFrequencies[section];
      subBass = (Math.sin(2 * Math.PI * bassFreq * time) * 0.038 + Math.sin(2 * Math.PI * bassFreq * 2.0 * time) * 0.012) * oceanSwell;
    }

    // Mix with Soft Limiting
    const mixL = padL * 0.78 + rhodesL * 1.15 + harpL * 0.85 + subBass;
    const mixR = padR * 0.78 + rhodesR * 1.15 + harpR * 0.85 + subBass;
    const loopFade = Math.min(1.0, Math.min(time, duration - time) / 0.18);

    left[frame] = Math.tanh(mixL * 1.05) * loopFade * 0.88;
    right[frame] = Math.tanh(mixR * 1.05) * loopFade * 0.88;
  }

  return buffer;
}

// 2. Synthesize Smooth Swim Stroke SFX Buffer (0.36s)
function buildSwimStrokeBuffer(ctx, baseFreq = 180) {
  const duration = 0.36;
  const sampleRate = ctx.sampleRate;
  const frameCount = sampleRate * duration;
  const buffer = ctx.createBuffer(2, frameCount, sampleRate);
  const left = buffer.getChannelData(0);
  const right = buffer.getChannelData(1);

  let lowPass = 0.0;
  for (let frame = 0; frame < frameCount; frame++) {
    const t = frame / sampleRate;
    const progress = t / duration;
    const env = Math.sin(progress * Math.PI) * Math.exp(-progress * 2.2);
    const raw = Math.random() * 2.0 - 1.0;
    lowPass = lowPass * 0.82 + raw * 0.18;

    const sweepFreq = (baseFreq * 0.66) + (baseFreq * 0.66) * Math.sin(progress * Math.PI * 0.80);
    const body = Math.sin(2.0 * Math.PI * sweepFreq * t) * 0.38;
    const bubble = Math.sin(2.0 * Math.PI * (340.0 + 90.0 * Math.sin(t * 32.0)) * t) * Math.exp(-t * 8.0) * 0.14;
    const sample = Math.tanh((lowPass * 0.45 + body + bubble) * env) * 0.48;

    left[frame] = sample;
    right[frame] = sample * 0.92;
  }
  return buffer;
}

// 3. Synthesize Ambient Flowing Water Loop Buffer (10.0s)
function buildWaterAmbianceBuffer(ctx) {
  const duration = 10.0;
  const sampleRate = ctx.sampleRate;
  const frameCount = sampleRate * duration;
  const buffer = ctx.createBuffer(2, frameCount, sampleRate);
  const left = buffer.getChannelData(0);
  const right = buffer.getChannelData(1);

  let seed = 0x72a491c3;
  let middleNoise = 0;
  let lowNoise = 0;

  for (let frame = 0; frame < frameCount; frame++) {
    seed = (seed * 1664525 + 1013904223) | 0;
    const noise = ((seed & 0xffff) / 32767.5) - 1.0;
    middleNoise = middleNoise * 0.88 + noise * 0.12;
    lowNoise = lowNoise * 0.985 + noise * 0.015;

    const time = frame / sampleRate;
    const edgeFade = Math.min(1.0, Math.min(time, duration - time) / 0.12);

    const surge = 0.85 + Math.sin(2 * Math.PI * 0.35 * time) * 0.12 + Math.sin(2 * Math.PI * 0.58 * time + 1.2) * 0.08;
    const flowingWater = (middleNoise - lowNoise) * 0.18 + lowNoise * 0.28;

    const bPeriod1 = time % 0.95;
    const bubble1 = (bPeriod1 < 0.08) ? (Math.sin(2.0 * Math.PI * (320.0 + bPeriod1 * 950.0) * bPeriod1) * Math.exp(-bPeriod1 * 55.0) * 0.024) : 0;
    const bPeriod2 = (time + 0.45) % 1.35;
    const bubble2 = (bPeriod2 < 0.07) ? (Math.sin(2.0 * Math.PI * (280.0 + bPeriod2 * 820.0) * bPeriod2) * Math.exp(-bPeriod2 * 60.0) * 0.020) : 0;
    const bPeriod3 = (time + 0.80) % 1.80;
    const bubble3 = (bPeriod3 < 0.06) ? (Math.sin(2.0 * Math.PI * (410.0 + bPeriod3 * 1100.0) * bPeriod3) * Math.exp(-bPeriod3 * 65.0) * 0.018) : 0;
    const bubbles = bubble1 + bubble2 + bubble3;

    left[frame] = (flowingWater * surge + bubbles) * edgeFade * 0.65;
    right[frame] = (flowingWater * surge * 0.95 - bubble1 * 0.4 + bubble2 * 0.7 + bubble3 * 0.5) * edgeFade * 0.65;
  }
  return buffer;
}

// 4. Playback Actions
function startBgm() {
  const ctx = getSynthAudioContext();
  if (bgmSourceNode) {
    try { bgmSourceNode.stop(); } catch (e) {}
  }
  const buf = buildUnderwaterMusicBuffer(ctx);
  bgmSourceNode = ctx.createBufferSource();
  bgmSourceNode.buffer = buf;
  bgmSourceNode.loop = true;

  if (!bgmGainNode) {
    bgmGainNode = ctx.createGain();
    bgmGainNode.connect(ctx.destination);
  }
  bgmGainNode.gain.setValueAtTime(parseFloat(volBgmSlider.value) / 100, ctx.currentTime);

  bgmSourceNode.connect(bgmGainNode);
  bgmSourceNode.start();
  isBgmPlaying = true;
  playBgmBtn.classList.add('active');
  playBgmBtn.innerHTML = '<span>⏸️ Pausar Música</span>';
}

function stopBgm() {
  if (bgmSourceNode) {
    try { bgmSourceNode.stop(); } catch (e) {}
    bgmSourceNode = null;
  }
  isBgmPlaying = false;
  playBgmBtn.classList.remove('active');
  playBgmBtn.innerHTML = '<span>▶️ Reproducir Música</span>';
}

function startAmb() {
  const ctx = getSynthAudioContext();
  if (ambSourceNode) {
    try { ambSourceNode.stop(); } catch (e) {}
  }
  const buf = buildWaterAmbianceBuffer(ctx);
  ambSourceNode = ctx.createBufferSource();
  ambSourceNode.buffer = buf;
  ambSourceNode.loop = true;

  if (!ambGainNode) {
    ambGainNode = ctx.createGain();
    ambGainNode.connect(ctx.destination);
  }
  ambGainNode.gain.setValueAtTime(parseFloat(volAmbSlider.value) / 100, ctx.currentTime);

  ambSourceNode.connect(ambGainNode);
  ambSourceNode.start();
  isAmbPlaying = true;
  playAmbBtn.classList.add('active');
  playAmbBtn.innerHTML = '<span>⏸️ Pausar Ambiente</span>';
}

function stopAmb() {
  if (ambSourceNode) {
    try { ambSourceNode.stop(); } catch (e) {}
    ambSourceNode = null;
  }
  isAmbPlaying = false;
  playAmbBtn.classList.remove('active');
  playAmbBtn.innerHTML = '<span>🫧 Reproducir Ambiente</span>';
}

function triggerSwimStroke() {
  const ctx = getSynthAudioContext();
  const freq = parseFloat(swimToneSlider.value);
  const buf = buildSwimStrokeBuffer(ctx, freq);
  const strokeSource = ctx.createBufferSource();
  strokeSource.buffer = buf;

  if (!sfxGainNode) {
    sfxGainNode = ctx.createGain();
    sfxGainNode.connect(ctx.destination);
  }
  sfxGainNode.gain.setValueAtTime(parseFloat(volSwimSlider.value) / 100, ctx.currentTime);

  strokeSource.connect(sfxGainNode);
  strokeSource.start();

  // Visual pulse on button
  triggerSwimBtn.style.transform = 'scale(0.96)';
  setTimeout(() => { triggerSwimBtn.style.transform = ''; }, 120);
}

// 5. Volume Sliders and Dynamic Mix Meter
function updateMixBalance() {
  const volBgm = parseFloat(volBgmSlider.value);
  const volSwim = parseFloat(volSwimSlider.value);
  const volAmb = parseFloat(volAmbSlider.value);

  volBgmVal.innerText = `${volBgm}%`;
  volSwimVal.innerText = `${volSwim}%`;
  volAmbVal.innerText = `${volAmb}%`;

  if (bgmGainNode && synthAudioCtx) {
    bgmGainNode.gain.setValueAtTime(volBgm / 100, synthAudioCtx.currentTime);
  }
  if (sfxGainNode && synthAudioCtx) {
    sfxGainNode.gain.setValueAtTime(volSwim / 100, synthAudioCtx.currentTime);
  }
  if (ambGainNode && synthAudioCtx) {
    ambGainNode.gain.setValueAtTime(volAmb / 100, synthAudioCtx.currentTime);
  }

  // Calculate dB relative
  const bgmDb = Math.round(20 * Math.log10(Math.max(0.01, volBgm / 100)));
  const sfxDb = Math.round(20 * Math.log10(Math.max(0.01, volSwim / 100)));
  const diffDb = sfxDb - bgmDb;

  bgmDbLabel.innerText = `${volBgm}% (${bgmDb} dBFS)`;
  sfxDbLabel.innerText = `${volSwim}% (${sfxDb} dBFS)`;
  meterBGM.style.width = `${volBgm}%`;
  meterSFX.style.width = `${volSwim}%`;

  if (diffDb > -6) {
    balanceBadge.className = 'balance-badge badge-warning';
    balanceBadge.innerText = `⚠️ FATIGA AUDITIVA: La brazada supera el estándar (+${diffDb} dB vs música)`;
    deltaDbLabel.style.color = '#ff4e50';
    deltaDbLabel.innerText = `Diferencia: ${diffDb > 0 ? '+' : ''}${diffDb} dB [Muy Fuerte]`;
  } else if (diffDb <= -6 && diffDb >= -15) {
    balanceBadge.className = 'balance-badge badge-optimal';
    balanceBadge.innerText = `✅ BALANCE ÓPTIMO (Foley ${diffDb} dB por debajo de la música)`;
    deltaDbLabel.style.color = '#38ef7d';
    deltaDbLabel.innerText = `Diferencia: ${diffDb} dB [Estándar de Oro]`;
  } else {
    balanceBadge.className = 'balance-badge';
    balanceBadge.innerText = `ℹ️ Brazada Tenue (${diffDb} dB por debajo)`;
    deltaDbLabel.style.color = '#c084fc';
    deltaDbLabel.innerText = `Diferencia: ${diffDb} dB [Muy Suave]`;
  }
}

volBgmSlider.oninput = updateMixBalance;
volSwimSlider.oninput = updateMixBalance;
volAmbSlider.oninput = updateMixBalance;

swimToneSlider.oninput = () => {
  const val = swimToneSlider.value;
  swimToneVal.innerText = `${val < 160 ? 'Grave Suave' : (val < 220 ? 'Sedoso Natural' : 'Brillante')} (${val} Hz)`;
};

// Layer toggle handlers (re-renders buffer on the fly if playing)
[toggleRhodes, togglePad, toggleHarp, toggleBass].forEach(cb => {
  cb.onchange = (e) => {
    e.target.closest('.layer-toggle-btn').classList.toggle('active', e.target.checked);
    if (isBgmPlaying) startBgm();
  };
});

// Single play buttons
playBgmBtn.onclick = () => {
  if (isBgmPlaying) stopBgm();
  else startBgm();
};

playAmbBtn.onclick = () => {
  if (isAmbPlaying) stopAmb();
  else startAmb();
};

triggerSwimBtn.onclick = triggerSwimStroke;

autoSwimBtn.onclick = () => {
  if (autoSwimInterval) {
    clearInterval(autoSwimInterval);
    autoSwimInterval = null;
    autoSwimBtn.classList.remove('active');
    autoSwimText.innerText = '🔁 Auto-Nado: OFF';
  } else {
    autoSwimInterval = setInterval(triggerSwimStroke, 550);
    autoSwimBtn.classList.add('active');
    autoSwimText.innerText = '🟢 Auto-Nado: ACTIVO (0.55s)';
    triggerSwimStroke();
  }
};

// Master Scene Simulator: All 3 simultaneously
masterSimBtn.onclick = () => {
  if (isMasterSimActive) {
    // Stop all
    stopBgm();
    stopAmb();
    if (autoSwimInterval) {
      clearInterval(autoSwimInterval);
      autoSwimInterval = null;
      autoSwimBtn.classList.remove('active');
      autoSwimText.innerText = '🔁 Auto-Nado: OFF';
    }
    isMasterSimActive = false;
    masterSimBtn.classList.remove('active');
    masterSimText.innerText = 'PROBAR MEZCLA EN VIVO (Música + Nado + Ambiente)';
  } else {
    // Start all
    startBgm();
    startAmb();
    if (!autoSwimInterval) {
      autoSwimInterval = setInterval(triggerSwimStroke, 550);
      autoSwimBtn.classList.add('active');
      autoSwimText.innerText = '🟢 Auto-Nado: ACTIVO (0.55s)';
      triggerSwimStroke();
    }
    isMasterSimActive = true;
    masterSimBtn.classList.add('active');
    masterSimText.innerText = '⏹️ DETENER SIMULACIÓN EN VIVO';
  }
};

// Apply and Deploy to iPhone
applyMixBtn.onclick = async () => {
  applyMixBtn.disabled = true;
  applyMixBtn.innerHTML = '<span class="btn-icon">⏳</span><span class="btn-text">Guardando en Xcode y Compilando...</span>';
  synthNotice.innerText = 'Guardando niveles y compilando para tu iPhone 15 Pro Max...';

  try {
    const payload = {
      volBgm: parseFloat(volBgmSlider.value),
      volSwim: parseFloat(volSwimSlider.value),
      volAmb: parseFloat(volAmbSlider.value),
      swimTone: parseFloat(swimToneSlider.value)
    };

    const res = await fetch('/api/synth/apply-levels', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    const result = await res.json();
    if (result.success) {
      synthNotice.innerHTML = `🟢 <b>${result.message}</b>`;
      alert('🚀 ¡Mezcla balanceada aplicada con éxito en tu iPhone 15 Pro Max!');
    } else {
      synthNotice.innerHTML = `<span style="color:#ff4e50">Error al compilar: ${result.error || result.output}</span>`;
      alert('Error en compilación: ' + (result.error || result.output));
    }
  } catch (err) {
    synthNotice.innerHTML = `<span style="color:#ff4e50">Error de conexión: ${err}</span>`;
    alert('Error conectando con el servidor: ' + err);
  } finally {
    applyMixBtn.disabled = false;
    applyMixBtn.innerHTML = '<span class="btn-icon">🚀</span><span class="btn-text">Aplicar Ajustes en Xcode y Compilar en iPhone</span>';
  }
};

// Spacebar trigger when in synth studio
window.addEventListener('keydown', (e) => {
  if (e.code === 'Space' && synthStudioSection.style.display !== 'none') {
    e.preventDefault();
    triggerSwimStroke();
  }
});

function initSynthStudio() {
  updateMixBalance();
}

// Init
loadChapters();
