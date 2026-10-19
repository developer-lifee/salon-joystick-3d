// SalonStudio 3D - Inspector Visual de Rigging & Simulador de Agua
const canvas = document.getElementById('three-canvas');
const container = document.getElementById('viewport-container');

// 1. Escena y Configuración
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x070a0f);

// Cámara inicial: Vista de perfil 3/4 perfecta para ver cobertura y ambas rodillas
const camera = new THREE.PerspectiveCamera(45, container.clientWidth / container.clientHeight, 0.1, 100);
camera.position.set(-1.8, 0.75, 0.85);

const renderer = new THREE.WebGLRenderer({ canvas: canvas, antialias: true });
renderer.setSize(container.clientWidth, container.clientHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

const controls = new THREE.OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.target.set(0, 0.45, 0.35);

// 2. Luces
const ambientLight = new THREE.AmbientLight(0x334455, 1.6);
scene.add(ambientLight);

const sunLight = new THREE.DirectionalLight(0xfff7e6, 2.2);
sunLight.position.set(4, 8, 5);
sunLight.castShadow = true;
sunLight.shadow.mapSize.width = 1024;
sunLight.shadow.mapSize.height = 1024;
scene.add(sunLight);

const rimLight = new THREE.PointLight(0x00e5ff, 2.8, 7);
rimLight.position.set(-2.0, 1.5, 0.5);
scene.add(rimLight);

const fillLight = new THREE.PointLight(0xff007f, 1.6, 6);
fillLight.position.set(1.5, 0.8, -0.5);
scene.add(fillLight);

// 3. Suelo de Patio
const patioFloor = new THREE.Mesh(
  new THREE.PlaneGeometry(14, 14),
  new THREE.MeshStandardMaterial({ color: 0x12171f, roughness: 0.8, metalness: 0.1 })
);
patioFloor.rotation.x = -Math.PI / 2;
patioFloor.receiveShadow = true;
scene.add(patioFloor);

const gridHelper = new THREE.GridHelper(14, 28, 0x00e5ff, 0x1f2b38);
gridHelper.position.y = 0.002;
scene.add(gridHelper);

// ----------------------------------------------------
// 4. PERSONAJE ARTICULADO & RIGGING DE RODILLAS (GTA COVER)
// ----------------------------------------------------
const coverGroup = new THREE.Group();

// Materiales del Traje con soporte para Modo Rayos X
const suitMat = new THREE.MeshStandardMaterial({
  color: 0x14d1ad,
  roughness: 0.35,
  metalness: 0.2,
  transparent: true,
  opacity: 0.50 // Semi-translúcido para ver el rigging interior
});
const armorMat = new THREE.MeshStandardMaterial({
  color: 0x141f29,
  roughness: 0.20,
  metalness: 0.65,
  transparent: true,
  opacity: 0.70
});
const visorMat = new THREE.MeshStandardMaterial({
  color: 0x0de9fc,
  roughness: 0.05,
  emissive: 0x00aacc,
  emissiveIntensity: 0.95
});
const scubaTankMat = new THREE.MeshStandardMaterial({
  color: 0xebda1f,
  roughness: 0.20,
  metalness: 0.75,
  transparent: true,
  opacity: 0.70
});
const flipperMat = new THREE.MeshStandardMaterial({ color: 0xf2730d, roughness: 0.35 });

// Torso y Cabeza
const torsoPivot = new THREE.Group();
const torsoMesh = new THREE.Mesh(new THREE.SphereGeometry(0.32, 16, 16), suitMat);
torsoMesh.scale.set(1.0, 1.35, 0.82);
torsoMesh.castShadow = true;

const chestArmor = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.38, 0.12), armorMat);
chestArmor.position.set(0, 0.04, 0.14);

const scubaTank = new THREE.Mesh(new THREE.BoxGeometry(0.28, 0.48, 0.18), scubaTankMat);
scubaTank.position.set(0, 0.04, -0.18);

const headMesh = new THREE.Mesh(new THREE.SphereGeometry(0.30, 16, 16), suitMat);
headMesh.position.set(0, 0.55, 0.06);

const visorMesh = new THREE.Mesh(new THREE.BoxGeometry(0.36, 0.17, 0.14), visorMat);
visorMesh.position.set(0, 0.57, 0.26);

// Brazos en guardia táctica
const leftArm = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.26, 0.14), suitMat);
const rightArm = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.26, 0.14), suitMat);
leftArm.position.set(-0.32, 0.10, 0.12);
rightArm.position.set(0.32, 0.10, 0.12);

torsoPivot.add(torsoMesh, chestArmor, scubaTank, headMesh, visorMesh, leftArm, rightArm);
coverGroup.add(torsoPivot);

// ----------------------------------------------------
// SISTEMA DE HUESOS & ARTICULACIONES VISIBLES (SKELETON)
// ----------------------------------------------------
const kneeFrontMat = new THREE.MeshBasicMaterial({ color: 0x00e676 }); // Verde neón
const kneeKneelMat = new THREE.MeshBasicMaterial({ color: 0xff007f }); // Magenta neón
const hipJointMat = new THREE.MeshBasicMaterial({ color: 0xffd600 }); // Oro neón

// --- PIERNA IZQUIERDA (Rodilla Adelante / Arriba) ---
const leftHipPivot = new THREE.Group();
const leftThigh = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.26, 0.15), suitMat);
leftThigh.position.set(0, -0.13, 0);

const leftKneePivot = new THREE.Group();
leftKneePivot.position.set(0, -0.26, 0);

// Marcador Esfera + Anillo de Rotación para Rodilla Adelante
const leftKneeMarker = new THREE.Group();
const leftKneeSphere = new THREE.Mesh(new THREE.SphereGeometry(0.09, 16, 16), kneeFrontMat);
const leftKneeRing = new THREE.Mesh(
  new THREE.TorusGeometry(0.13, 0.022, 8, 24),
  kneeFrontMat
);
leftKneeRing.rotation.y = Math.PI / 2;
leftKneeMarker.add(leftKneeSphere, leftKneeRing);

const leftShin = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.26, 0.14), suitMat);
leftShin.position.set(0, -0.13, 0);

const leftFoot = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.06, 0.36), flipperMat);
leftFoot.position.set(0, -0.26, 0.10);

leftKneePivot.add(leftKneeMarker, leftShin, leftFoot);
leftHipPivot.add(leftThigh, leftKneePivot);
coverGroup.add(leftHipPivot);

// --- PIERNA DERECHA (Rodilla Hincada en el Suelo) ---
const rightHipPivot = new THREE.Group();
const rightThigh = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.26, 0.15), suitMat);
rightThigh.position.set(0, -0.13, 0);

const rightKneePivot = new THREE.Group();
rightKneePivot.position.set(0, -0.26, 0);

// Marcador Esfera + Anillo de Rotación para Rodilla Hincada
const rightKneeMarker = new THREE.Group();
const rightKneeSphere = new THREE.Mesh(new THREE.SphereGeometry(0.09, 16, 16), kneeKneelMat);
const rightKneeRing = new THREE.Mesh(
  new THREE.TorusGeometry(0.13, 0.022, 8, 24),
  kneeKneelMat
);
rightKneeRing.rotation.y = Math.PI / 2;
rightKneeMarker.add(rightKneeSphere, rightKneeRing);

const rightShin = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.24, 0.14), suitMat);
rightShin.position.set(0, -0.12, 0);

const rightFoot = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.06, 0.36), flipperMat);
rightFoot.position.set(0, -0.24, 0.08);

rightKneePivot.add(rightKneeMarker, rightShin, rightFoot);
rightHipPivot.add(rightThigh, rightKneePivot);
coverGroup.add(rightHipPivot);

// Cadera Central (Pelvis)
const hipJoint = new THREE.Mesh(new THREE.SphereGeometry(0.10, 16, 16), hipJointMat);
coverGroup.add(hipJoint);

// Roca de Río Táctica
const rockGroup = new THREE.Group();
const rockMesh = new THREE.Mesh(
  new THREE.DodecahedronGeometry(0.55, 2),
  new THREE.MeshStandardMaterial({ color: 0x47535e, roughness: 0.85, metalness: 0.08, flatShading: true })
);
rockMesh.scale.set(1.2, 0.8, 1.0);
rockMesh.castShadow = true;
rockMesh.receiveShadow = true;
rockGroup.add(rockMesh);
coverGroup.add(rockGroup);

scene.add(coverGroup);

// ----------------------------------------------------
// 5. PISCINA 3D COMPLETA & SHADER DE AGUA TURQUESA
// ----------------------------------------------------
const poolGroup = new THREE.Group();
poolGroup.visible = false;

// Terraza / Deck de la piscina
const deckMat = new THREE.MeshStandardMaterial({
  color: 0x1f2b38,
  roughness: 0.7,
  metalness: 0.1
});
const poolDeck = new THREE.Mesh(new THREE.PlaneGeometry(16, 16), deckMat);
poolDeck.rotation.x = -Math.PI / 2;
poolDeck.position.y = 0.0;
poolDeck.receiveShadow = true;
poolGroup.add(poolDeck);

// Crear textura de azulejos de piscina procedimental con canvas
const tileCanvas = document.createElement('canvas');
tileCanvas.width = 256;
tileCanvas.height = 256;
const tCtx = tileCanvas.getContext('2d');
tCtx.fillStyle = '#0284c7';
tCtx.fillRect(0, 0, 256, 256);
tCtx.strokeStyle = '#38bdf8';
tCtx.lineWidth = 3;
const step = 32;
for (let x = 0; x <= 256; x += step) {
  tCtx.beginPath();
  tCtx.moveTo(x, 0);
  tCtx.lineTo(x, 256);
  tCtx.stroke();
}
for (let y = 0; y <= 256; y += step) {
  tCtx.beginPath();
  tCtx.moveTo(0, y);
  tCtx.lineTo(256, y);
  tCtx.stroke();
}
const tileTexture = new THREE.CanvasTexture(tileCanvas);
tileTexture.wrapS = THREE.RepeatWrapping;
tileTexture.wrapT = THREE.RepeatWrapping;
tileTexture.repeat.set(8, 6);

const poolTileMat = new THREE.MeshStandardMaterial({
  map: tileTexture,
  roughness: 0.15,
  metalness: 0.05
});

const copingMat = new THREE.MeshStandardMaterial({
  color: 0xf1f5f9,
  roughness: 0.35
});

// Vaso de la piscina (Fondo y 4 paredes)
const poolBottom = new THREE.Mesh(new THREE.PlaneGeometry(6.4, 4.4), poolTileMat);
poolBottom.rotation.x = -Math.PI / 2;
poolBottom.position.y = -1.35;
poolBottom.receiveShadow = true;
poolGroup.add(poolBottom);

// Paredes interiores
const wallNorth = new THREE.Mesh(new THREE.PlaneGeometry(6.4, 1.35), poolTileMat);
wallNorth.position.set(0, -0.675, -2.2);
poolGroup.add(wallNorth);

const wallSouth = new THREE.Mesh(new THREE.PlaneGeometry(6.4, 1.35), poolTileMat);
wallSouth.position.set(0, -0.675, 2.2);
wallSouth.rotation.y = Math.PI;
poolGroup.add(wallSouth);

const wallWest = new THREE.Mesh(new THREE.PlaneGeometry(4.4, 1.35), poolTileMat);
wallWest.position.set(-3.2, -0.675, 0);
wallWest.rotation.y = Math.PI / 2;
poolGroup.add(wallWest);

const wallEast = new THREE.Mesh(new THREE.PlaneGeometry(4.4, 1.35), poolTileMat);
wallEast.position.set(3.2, -0.675, 0);
wallEast.rotation.y = -Math.PI / 2;
poolGroup.add(wallEast);

// Borde de piedra blanca (Coping)
const copingNorth = new THREE.Mesh(new THREE.BoxGeometry(6.8, 0.14, 0.38), copingMat);
copingNorth.position.set(0, 0.07, -2.35);
const copingSouth = new THREE.Mesh(new THREE.BoxGeometry(6.8, 0.14, 0.38), copingMat);
copingSouth.position.set(0, 0.07, 2.35);
const copingWest = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.14, 4.8), copingMat);
copingWest.position.set(-3.35, 0.07, 0);
const copingEast = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.14, 4.8), copingMat);
copingEast.position.set(3.35, 0.07, 0);
poolGroup.add(copingNorth, copingSouth, copingWest, copingEast);

// Luces Subacuáticas de la Piscina (Efecto Resort)
const underwaterLight1 = new THREE.PointLight(0x00f0ff, 4.0, 5);
underwaterLight1.position.set(-1.8, -0.7, 0);
const underwaterLight2 = new THREE.PointLight(0x00f0ff, 4.0, 5);
underwaterLight2.position.set(1.8, -0.7, 0);
poolGroup.add(underwaterLight1, underwaterLight2);

// Flotador inflable naranja
const floatMesh = new THREE.Mesh(
  new THREE.TorusGeometry(0.48, 0.14, 16, 28),
  new THREE.MeshStandardMaterial({ color: 0xff5500, roughness: 0.15 })
);
floatMesh.rotation.x = Math.PI / 2;
floatMesh.position.set(1.0, -0.08, 0.2);
poolGroup.add(floatMesh);

// Superficie de Agua Cristalina
const waterGeometry = new THREE.PlaneGeometry(6.4, 4.4, 56, 42);
const waterMaterial = new THREE.MeshStandardMaterial({
  color: 0x06b6d4, // Cyan turquesa caribeño
  roughness: 0.08,
  metalness: 0.12,
  transparent: true,
  opacity: 0.65, // Deja ver los azulejos y luces del fondo
  flatShading: true
});
const waterSurface = new THREE.Mesh(waterGeometry, waterMaterial);
waterSurface.rotation.x = -Math.PI / 2;
waterSurface.position.y = -0.06;
poolGroup.add(waterSurface);

scene.add(poolGroup);

// ----------------------------------------------------
// 6. CONTROLADORES DE CÁMARA & ANIMACIONES
// ----------------------------------------------------
function setCameraView(type) {
  if (type === 'side') {
    // Vista Lateral directa a la flexión de rodillas y distancia a la roca
    camera.position.set(-1.8, 0.65, 0.5);
    controls.target.set(0, 0.45, 0.4);
  } else if (type === 'knees') {
    // Zoom directo a las rodillas
    camera.position.set(-0.9, 0.42, 0.3);
    controls.target.set(0, 0.35, 0.1);
  } else if (type === 'front') {
    // Vista desde el frente de la roca hacia el jugador cubriéndose
    camera.position.set(0.2, 0.9, 2.2);
    controls.target.set(0, 0.45, 0.35);
  } else if (type === 'reset') {
    camera.position.set(-1.8, 0.75, 0.85);
    controls.target.set(0, 0.45, 0.35);
  } else if (type === 'pool-resort') {
    camera.position.set(-3.8, 2.4, 3.6);
    controls.target.set(0, -0.4, 0);
  } else if (type === 'pool-waterline') {
    camera.position.set(-2.8, 0.25, 1.8);
    controls.target.set(0, -0.1, 0);
  } else if (type === 'pool-underwater') {
    camera.position.set(0, -0.6, 1.8);
    controls.target.set(0, -0.7, 0);
  } else if (type === 'pool-top') {
    camera.position.set(0, 5.2, 0.01);
    controls.target.set(0, 0, 0);
  }
  controls.update();
}

function updateCameraButtons(tab) {
  const bar = document.querySelector('.camera-bar');
  if (tab === 'tab-water') {
    bar.innerHTML = `
      <button class="cam-btn" onclick="setCameraView('pool-resort')">🏝️ Vista Resort 3D</button>
      <button class="cam-btn" onclick="setCameraView('pool-waterline')">🌊 A ras de Agua</button>
      <button class="cam-btn" onclick="setCameraView('pool-underwater')">🤿 Bajo el Agua</button>
      <button class="cam-btn" onclick="setCameraView('pool-top')">🦅 Vista Aérea</button>
    `;
  } else {
    bar.innerHTML = `
      <button class="cam-btn" onclick="setCameraView('side')">👁️ Vista Lateral (Perfil)</button>
      <button class="cam-btn" onclick="setCameraView('knees')">🦵 Detalle Rodillas</button>
      <button class="cam-btn" onclick="setCameraView('front')">🪨 Vista Frontal Roca</button>
      <button class="cam-btn" onclick="setCameraView('reset')">🔄 Órbita General</button>
    `;
  }
}

function updatePose() {
  const crouchY = parseFloat(document.getElementById('crouchY').value);
  const legSpread = parseFloat(document.getElementById('legSpread').value);
  const kneeFrontAngle = parseFloat(document.getElementById('kneeFrontAngle').value);
  const kneeKneelAngle = parseFloat(document.getElementById('kneeKneelAngle').value);
  const spineTilt = parseFloat(document.getElementById('spineTilt').value);

  document.getElementById('val-crouchY').textContent = crouchY.toFixed(2) + 'm';
  document.getElementById('val-legSpread').textContent = legSpread.toFixed(2) + 'm';
  document.getElementById('val-kneeFrontAngle').textContent = kneeFrontAngle + '°';
  document.getElementById('val-kneeKneelAngle').textContent = kneeKneelAngle + '°';
  document.getElementById('val-spineTilt').textContent = spineTilt + '°';

  // 1. Cadera & Torso
  hipJoint.position.set(0, crouchY, 0);
  torsoPivot.position.set(0, crouchY, 0);
  torsoPivot.rotation.x = THREE.MathUtils.degToRad(spineTilt);

  // 2. Pierna Izquierda (Adelante, flexión hacia arriba)
  leftHipPivot.position.set(-legSpread, crouchY, 0.05);
  leftHipPivot.rotation.x = THREE.MathUtils.degToRad(-kneeFrontAngle * 0.7);
  leftKneePivot.rotation.x = THREE.MathUtils.degToRad(kneeFrontAngle * 0.95);

  // 3. Pierna Derecha (Hincada tocando el piso)
  rightHipPivot.position.set(legSpread, crouchY, -0.05);
  rightHipPivot.rotation.x = THREE.MathUtils.degToRad(kneeKneelAngle * 0.45);
  rightKneePivot.rotation.x = THREE.MathUtils.degToRad(-kneeKneelAngle * 0.9);
}

function toggleSkeletonView() {
  const show = document.getElementById('toggleSkeleton').checked;
  leftKneeMarker.visible = show;
  rightKneeMarker.visible = show;
  hipJoint.visible = show;
}

function toggleXRayView() {
  const xray = document.getElementById('toggleXRay').checked;
  suitMat.opacity = xray ? 0.45 : 1.0;
  armorMat.opacity = xray ? 0.60 : 1.0;
  scubaTankMat.opacity = xray ? 0.60 : 1.0;
  suitMat.needsUpdate = true;
  armorMat.needsUpdate = true;
  scubaTankMat.needsUpdate = true;
}

function updateRock() {
  const rockRadius = parseFloat(document.getElementById('rockRadius').value);
  const rockDist = parseFloat(document.getElementById('rockDist').value);

  document.getElementById('val-rockRadius').textContent = rockRadius.toFixed(2) + 'm';
  document.getElementById('val-rockDist').textContent = rockDist.toFixed(2) + 'm';

  rockGroup.scale.set(rockRadius / 0.55, rockRadius / 0.55, rockRadius / 0.55);
  rockGroup.position.set(0, rockRadius * 0.42, rockDist + rockRadius);
}

function updateWater() {
  const clarity = parseFloat(document.getElementById('waterClarity').value);
  const reflect = parseFloat(document.getElementById('waterReflect').value);
  const waves = parseFloat(document.getElementById('waterWaves').value);
  const speed = parseFloat(document.getElementById('waterSpeed').value);

  document.getElementById('val-waterClarity').textContent = clarity.toFixed(2);
  document.getElementById('val-waterReflect').textContent = reflect.toFixed(2);
  document.getElementById('val-waterWaves').textContent = waves.toFixed(3);
  document.getElementById('val-waterSpeed').textContent = speed.toFixed(1) + 'x';

  waterMaterial.opacity = 0.25 + (clarity * 0.55);
  waterMaterial.metalness = reflect * 0.25;
  waterMaterial.roughness = 0.04 + (1.0 - reflect) * 0.15;
}

function applyWaterPreset(preset) {
  if (preset === 'caribe') {
    waterMaterial.color.setHex(0x06b6d4); // Turquesa Caribeño
    document.getElementById('waterClarity').value = 0.92;
    document.getElementById('waterReflect').value = 0.95;
    document.getElementById('waterWaves').value = 0.030;
  } else if (preset === 'cyberpunk') {
    waterMaterial.color.setHex(0xa855f7); // Neón Púrpura
    document.getElementById('waterClarity').value = 0.75;
    document.getElementById('waterReflect').value = 0.98;
    document.getElementById('waterWaves').value = 0.045;
  } else if (preset === 'emerald') {
    waterMaterial.color.setHex(0x10b981); // Esmeralda
    document.getElementById('waterClarity').value = 0.82;
    document.getElementById('waterReflect').value = 0.88;
    document.getElementById('waterWaves').value = 0.025;
  } else if (preset === 'crystal') {
    waterMaterial.color.setHex(0x38bdf8); // Azul Celeste Cristalino
    document.getElementById('waterClarity').value = 0.96;
    document.getElementById('waterReflect').value = 0.95;
    document.getElementById('waterWaves').value = 0.018;
  }
  updateWater();
}

function switchTab(tabId) {
  const btnCover = document.getElementById('btn-tab-cover');
  const btnWater = document.getElementById('btn-tab-water');
  const panelCover = document.getElementById('tab-cover');
  const panelWater = document.getElementById('tab-water');

  if (tabId === 'tab-water') {
    btnCover.classList.remove('active');
    btnWater.classList.add('active');
    panelCover.classList.remove('active');
    panelWater.classList.add('active');

    // Ocultar personaje y cobertura, mostrar piscina 3D viva
    coverGroup.visible = false;
    patioFloor.visible = false;
    gridHelper.visible = false;
    poolGroup.visible = true;

    // Actualizar botones de cámara para piscina
    updateCameraButtons('tab-water');
    setCameraView('pool-resort');
  } else {
    btnWater.classList.remove('active');
    btnCover.classList.add('active');
    panelWater.classList.remove('active');
    panelCover.classList.add('active');

    // Mostrar personaje y cobertura
    coverGroup.visible = true;
    patioFloor.visible = true;
    gridHelper.visible = true;
    poolGroup.visible = false;

    // Actualizar botones de cámara para cobertura
    updateCameraButtons('tab-cover');
    setCameraView('side');
  }
}

async function saveCoverPose() {
  const payload = {
    crouchY: parseFloat(document.getElementById('crouchY').value),
    legSpread: parseFloat(document.getElementById('legSpread').value),
    kneeFrontAngle: parseFloat(document.getElementById('kneeFrontAngle').value),
    kneeKneelAngle: parseFloat(document.getElementById('kneeKneelAngle').value),
    spineTilt: parseFloat(document.getElementById('spineTilt').value),
    rockRadius: parseFloat(document.getElementById('rockRadius').value),
    rockDist: parseFloat(document.getElementById('rockDist').value)
  };

  try {
    const res = await fetch('/api/save-cover', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const data = await res.json();
    const badge = document.getElementById('status-cover');
    badge.textContent = '✅ ' + (data.message || 'Pose guardada en Swift');
    badge.style.display = 'block';
    setTimeout(() => { badge.style.display = 'none'; }, 4000);
  } catch (err) {
    alert('Error al conectar con el servidor local: ' + err.message);
  }
}

async function saveWaterSettings() {
  const payload = {
    clarity: parseFloat(document.getElementById('waterClarity').value),
    reflect: parseFloat(document.getElementById('waterReflect').value),
    waves: parseFloat(document.getElementById('waterWaves').value),
    speed: parseFloat(document.getElementById('waterSpeed').value),
    color: '#' + waterMaterial.color.getHexString()
  };

  try {
    const res = await fetch('/api/save-water', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const data = await res.json();
    const badge = document.getElementById('status-water');
    badge.textContent = '✅ ' + (data.message || 'Shader sincronizado en Swift');
    badge.style.display = 'block';
    setTimeout(() => { badge.style.display = 'none'; }, 4000);
  } catch (err) {
    alert('Error al conectar con el servidor local: ' + err.message);
  }
}

// ----------------------------------------------------
// 7. BUCLE DE RENDER & ANIMACIÓN ONDULATORIA
// ----------------------------------------------------
const posAttr = waterGeometry.attributes.position;
const originalPositions = posAttr.array.slice();

function animate() {
  requestAnimationFrame(animate);
  controls.update();

  // Animación ondulatoria del agua viva
  if (poolGroup.visible) {
    const time = performance.now() * 0.002 * parseFloat(document.getElementById('waterSpeed').value);
    const waveAmp = parseFloat(document.getElementById('waterWaves').value) * 1.5;

    for (let i = 0; i < posAttr.count; i++) {
      const u = originalPositions[i * 3];
      const v = originalPositions[i * 3 + 1];
      const zWave = Math.sin(u * 2.5 + time) * Math.cos(v * 2.2 + time * 0.8) * waveAmp;
      posAttr.setZ(i, zWave);
    }
    posAttr.needsUpdate = true;

    // Balanceo suave del flotador
    floatMesh.position.y = -0.08 + Math.sin(time * 1.2) * 0.025;
    floatMesh.rotation.z = Math.sin(time * 0.8) * 0.05;
  }

  renderer.render(scene, camera);
}

window.addEventListener('resize', () => {
  camera.aspect = container.clientWidth / container.clientHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(container.clientWidth, container.clientHeight);
});

// Inicializar estado inicial
updatePose();
updateRock();
updateWater();
animate();
