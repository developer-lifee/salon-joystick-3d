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

// 1.1 TransformControls 3D (Gizmo de manipulación directa estilo Roblox / Fortnite Creative)
const transformControl = new THREE.TransformControls(camera, renderer.domElement);
transformControl.size = 0.85;
transformControl.addEventListener('change', () => {
  if (selectedMapProp) {
    updateSelectedPropInfo();
  }
});
transformControl.addEventListener('dragging-changed', (event) => {
  controls.enabled = !event.value;
});
scene.add(transformControl);

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

// Terraza / Deck de la piscina (Suelo exterior de resort con contraste elegante)
const deckMat = new THREE.MeshStandardMaterial({
  color: 0x334155, // Piedra pizarra moderna con contraste frente al agua
  roughness: 0.65,
  metalness: 0.15
});
const poolDeck = new THREE.Mesh(new THREE.PlaneGeometry(28, 28), deckMat);
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
const underwaterLight1 = new THREE.PointLight(0x00f0ff, 1.5, 6);
underwaterLight1.position.set(-1.8, -0.7, 0);
const underwaterLight2 = new THREE.PointLight(0x00f0ff, 1.5, 6);
underwaterLight2.position.set(1.8, -0.7, 0);
poolGroup.add(underwaterLight1, underwaterLight2);

// ----------------------------------------------------
// PROPS DE REALISMO ACUÁTICO
// ----------------------------------------------------
// Materiales de Props
const chromeMat = new THREE.MeshStandardMaterial({
  color: 0xf8fafc,
  metalness: 0.96,
  roughness: 0.08
});
const blackRubberMat = new THREE.MeshStandardMaterial({
  color: 0x18181b,
  roughness: 0.8
});

// 1. ESCALERA DE PISCINA DE ACERO INOXIDABLE (Referencia clave de inmersión)
const ladderGroup = new THREE.Group();
ladderGroup.position.set(-1.6, 0.07, -2.15);

// Pasamanos izquierdo y derecho curvados
function createLadderRail(xOffset) {
  const railGroup = new THREE.Group();
  // Barra vertical en la pared (sumergida hasta -0.85m)
  const lowerPipe = new THREE.Mesh(new THREE.CylinderGeometry(0.022, 0.022, 0.95, 16), chromeMat);
  lowerPipe.position.set(xOffset, -0.475, 0.06);
  // Arco superior de agarre que sale hacia el coping
  const upperPipe = new THREE.Mesh(new THREE.CylinderGeometry(0.022, 0.022, 0.45, 16), chromeMat);
  upperPipe.position.set(xOffset, 0.22, 0.06);
  const topCurve = new THREE.Mesh(new THREE.TorusGeometry(0.12, 0.022, 12, 16, Math.PI), chromeMat);
  topCurve.rotation.y = Math.PI / 2;
  topCurve.position.set(xOffset, 0.44, -0.06);
  const backPost = new THREE.Mesh(new THREE.CylinderGeometry(0.022, 0.022, 0.44, 16), chromeMat);
  backPost.position.set(xOffset, 0.22, -0.18);
  const baseFlange = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.045, 0.02, 16), chromeMat);
  baseFlange.position.set(xOffset, 0.01, -0.18);
  const bumper = new THREE.Mesh(new THREE.SphereGeometry(0.028, 12, 12), blackRubberMat);
  bumper.position.set(xOffset, -0.95, 0.06);

  railGroup.add(lowerPipe, upperPipe, topCurve, backPost, baseFlange, bumper);
  return railGroup;
}
ladderGroup.add(createLadderRail(-0.24));
ladderGroup.add(createLadderRail(0.24));

// 3 Peldaños cromados (1 sobre el agua, 2 sumergidos con distorsión acuática)
const stepRungs = [];
[-0.04, -0.34, -0.66].forEach(yPos => {
  const rung = new THREE.Mesh(new THREE.BoxGeometry(0.44, 0.025, 0.08), chromeMat);
  rung.position.set(0, yPos, 0.06);
  ladderGroup.add(rung);
  stepRungs.push(rung);
});
poolGroup.add(ladderGroup);

// 2. PELOTA DE PLAYA INFLABLE MULTICOLOR
const ballCanvas = document.createElement('canvas');
ballCanvas.width = 256;
ballCanvas.height = 128;
const bCtx = ballCanvas.getContext('2d');
const colors = ['#ef4444', '#ffffff', '#3b82f6', '#ffffff', '#eab308', '#22c55e'];
const sliceW = 256 / colors.length;
colors.forEach((col, idx) => {
  bCtx.fillStyle = col;
  bCtx.fillRect(idx * sliceW, 0, sliceW, 128);
});
const ballTexture = new THREE.CanvasTexture(ballCanvas);
const beachBallMesh = new THREE.Mesh(
  new THREE.SphereGeometry(0.26, 24, 24),
  new THREE.MeshStandardMaterial({ map: ballTexture, roughness: 0.18, metalness: 0.05 })
);
beachBallMesh.position.set(-1.2, -0.06, -0.6);
beachBallMesh.castShadow = true;
poolGroup.add(beachBallMesh);

// 3. FLOTADOR SALVAVIDAS CON CINCHAS BLANCAS
const lifeBuoyGroup = new THREE.Group();
const buoyTorus = new THREE.Mesh(
  new THREE.TorusGeometry(0.46, 0.13, 16, 32),
  new THREE.MeshStandardMaterial({ color: 0xff4500, roughness: 0.20 })
);
buoyTorus.rotation.x = Math.PI / 2;
lifeBuoyGroup.add(buoyTorus);
// 4 Cinchas blancas de agarre
const strapMat = new THREE.MeshStandardMaterial({ color: 0xf8fafc, roughness: 0.4 });
for (let a = 0; a < 4; a++) {
  const strap = new THREE.Mesh(new THREE.TorusGeometry(0.14, 0.015, 8, 16), strapMat);
  strap.rotation.y = (a * Math.PI) / 2;
  strap.position.set(Math.cos((a * Math.PI) / 2) * 0.46, 0, Math.sin((a * Math.PI) / 2) * 0.46);
  lifeBuoyGroup.add(strap);
}
lifeBuoyGroup.position.set(1.1, -0.07, 0.3);
poolGroup.add(lifeBuoyGroup);
const floatMesh = lifeBuoyGroup; // Alias para compatibilidad de animación

// 4. LÍNEA DE BOYAS DE CARRIL DE NATACIÓN (Separador flotante)
const laneBuoysGroup = new THREE.Group();
const buoyMatRed = new THREE.MeshStandardMaterial({ color: 0xef4444, roughness: 0.25 });
const buoyMatWhite = new THREE.MeshStandardMaterial({ color: 0xf8fafc, roughness: 0.25 });
const buoysList = [];
const buoyCount = 14;
for (let b = 0; b < buoyCount; b++) {
  const bx = -2.8 + (b / (buoyCount - 1)) * 5.6;
  const buoy = new THREE.Mesh(
    new THREE.SphereGeometry(0.085, 16, 16),
    b % 2 === 0 ? buoyMatRed : buoyMatWhite
  );
  buoy.scale.set(1.3, 0.85, 0.85);
  buoy.position.set(bx, -0.06, 1.1);
  laneBuoysGroup.add(buoy);
  buoysList.push(buoy);
}
// Cable central de las boyas
const laneCable = new THREE.Mesh(
  new THREE.CylinderGeometry(0.012, 0.012, 5.6, 8),
  new THREE.MeshStandardMaterial({ color: 0x64748b, metalness: 0.8 })
);
laneCable.rotation.z = Math.PI / 2;
laneCable.position.set(0, -0.06, 1.1);
laneBuoysGroup.add(laneCable);
poolGroup.add(laneBuoysGroup);

// 5. MOBILIARIO DE RESORT: TUMBONA Y SOMBRILLA AL BORDE
const loungeGroup = new THREE.Group();
loungeGroup.position.set(2.4, 0.07, -2.8);
loungeGroup.rotation.y = Math.PI / 4;

// Estructura de la tumbona
const loungerFrame = new THREE.Mesh(
  new THREE.BoxGeometry(0.70, 0.12, 1.70),
  new THREE.MeshStandardMaterial({ color: 0xf1f5f9, roughness: 0.4 })
);
loungerFrame.position.set(0, 0.06, 0);
// Respaldo inclinado
const backrest = new THREE.Mesh(
  new THREE.BoxGeometry(0.68, 0.08, 0.65),
  new THREE.MeshStandardMaterial({ color: 0xf1f5f9, roughness: 0.4 })
);
backrest.rotation.x = -Math.PI / 6;
backrest.position.set(0, 0.24, -0.55);
// Toalla azul turquesa doblada
const towel = new THREE.Mesh(
  new THREE.BoxGeometry(0.55, 0.04, 0.95),
  new THREE.MeshStandardMaterial({ color: 0x06b6d4, roughness: 0.85 })
);
towel.position.set(0, 0.13, 0.20);
loungeGroup.add(loungerFrame, backrest, towel);
poolGroup.add(loungeGroup);

// Sombrilla de Terraza (Parasol)
const parasolGroup = new THREE.Group();
parasolGroup.position.set(3.4, 0.07, -2.7);
const umbrellaPole = new THREE.Mesh(
  new THREE.CylinderGeometry(0.03, 0.03, 2.2, 12),
  new THREE.MeshStandardMaterial({ color: 0xe2e8f0, metalness: 0.7 })
);
umbrellaPole.position.y = 1.1;
const umbrellaCanopy = new THREE.Mesh(
  new THREE.ConeGeometry(1.2, 0.45, 8),
  new THREE.MeshStandardMaterial({ color: 0x0284c7, roughness: 0.5 })
);
umbrellaCanopy.position.y = 2.15;
parasolGroup.add(umbrellaPole, umbrellaCanopy);
poolGroup.add(parasolGroup);

// 6. BOQUILLAS DE HIDROMASAJE & BURBUJAS SUBACUÁTICAS ASCENDENTES
const bubbleMat = new THREE.MeshStandardMaterial({
  color: 0xe0f2fe,
  roughness: 0.05,
  metalness: 0.1,
  transparent: true,
  opacity: 0.65
});
const bubblesList = [];
for (let i = 0; i < 28; i++) {
  const bMesh = new THREE.Mesh(
    new THREE.SphereGeometry(0.016 + Math.random() * 0.016, 8, 8),
    bubbleMat
  );
  bMesh.position.set(
    -3.1 + Math.random() * 0.5,
    -1.2 + Math.random() * 1.1,
    -1.0 + (Math.random() - 0.5) * 1.6
  );
  bMesh.userData = {
    speedY: 0.008 + Math.random() * 0.012,
    baseX: bMesh.position.x,
    baseZ: bMesh.position.z,
    wobblePhase: Math.random() * Math.PI * 2
  };
  poolGroup.add(bMesh);
  bubblesList.push(bMesh);
}

// 7. SUPERFICIE DE AGUA CRISTALINA CON SHADER ULTRA-REALISTA
const waterGeometry = new THREE.PlaneGeometry(6.4, 4.4, 56, 42);
const waterMaterial = new THREE.MeshStandardMaterial({
  color: 0x06b6d4, // Cyan turquesa caribeño
  roughness: 0.06,
  metalness: 0.18,
  transparent: true,
  opacity: 0.68, // Permite ver peldaños de escalera y azulejos sumergidos
  flatShading: true
});
const waterSurface = new THREE.Mesh(waterGeometry, waterMaterial);
waterSurface.rotation.x = -Math.PI / 2;
waterSurface.position.y = -0.06;
poolGroup.add(waterSurface);

// Borde de Espuma Perimetral (Menisco blanco donde el agua toca el borde)
const foamMat = new THREE.MeshBasicMaterial({
  color: 0xffffff,
  transparent: true,
  opacity: 0.40,
  wireframe: false
});
const foamBorderNorth = new THREE.Mesh(new THREE.PlaneGeometry(6.4, 0.08), foamMat);
foamBorderNorth.rotation.x = -Math.PI / 2;
foamBorderNorth.position.set(0, -0.055, -2.16);
const foamBorderSouth = new THREE.Mesh(new THREE.PlaneGeometry(6.4, 0.08), foamMat);
foamBorderSouth.rotation.x = -Math.PI / 2;
foamBorderSouth.position.set(0, -0.055, 2.16);
const foamBorderWest = new THREE.Mesh(new THREE.PlaneGeometry(0.08, 4.4), foamMat);
foamBorderWest.rotation.x = -Math.PI / 2;
foamBorderWest.position.set(-3.16, -0.055, 0);
const foamBorderEast = new THREE.Mesh(new THREE.PlaneGeometry(0.08, 4.4), foamMat);
foamBorderEast.rotation.x = -Math.PI / 2;
foamBorderEast.position.set(3.16, -0.055, 0);
poolGroup.add(foamBorderNorth, foamBorderSouth, foamBorderWest, foamBorderEast);

scene.add(poolGroup);

// ----------------------------------------------------
// 5.5 SLIME IMP 3D PROCEDURAL (PERSONAJE & COSMÉTICOS FREEMIUM)
// ----------------------------------------------------
const slimeImpGroup = new THREE.Group();
slimeImpGroup.visible = false;

// Material de Slime Orgánico Verde Lima (Referencia exacta de la imagen)
const slimeMat = new THREE.MeshStandardMaterial({
  color: 0x4ade80, // Verde lima vivo
  roughness: 0.28,
  metalness: 0.08,
  flatShading: false
});
const slimeDarkMat = new THREE.MeshStandardMaterial({
  color: 0x15803d, // Verde oscuro para hueco de orejas y pliegues
  roughness: 0.45
});
const teethMat = new THREE.MeshStandardMaterial({
  color: 0xfef9c3, // Colmillos afilados marfil
  roughness: 0.15
});
const mouthInteriorMat = new THREE.MeshBasicMaterial({ color: 0x052e16 });
const tongueMat = new THREE.MeshStandardMaterial({ color: 0x22c55e, roughness: 0.35 });

// 1. CUERPO PERIFORME (Torso + Barriga regordeta)
const slimeBodyGroup = new THREE.Group();

// Barriga inferior esférica prominente
const bellyMesh = new THREE.Mesh(new THREE.SphereGeometry(0.36, 32, 28), slimeMat);
bellyMesh.scale.set(1.12, 1.0, 1.02);
bellyMesh.position.set(0, 0.34, 0.02);
bellyMesh.castShadow = true;

// Cabeza / Torso superior fusionado (ligeramente inclinado para albergar la cara)
const slimeHeadMesh = new THREE.Mesh(new THREE.SphereGeometry(0.35, 32, 28), slimeMat);
slimeHeadMesh.scale.set(1.04, 1.15, 1.02);
slimeHeadMesh.position.set(0, 0.65, 0.04);
slimeHeadMesh.castShadow = true;

// Manchas sutiles de piel de slime (Puntos claros de brillo)
const speckleMat = new THREE.MeshBasicMaterial({ color: 0x86efac });
for (let s = 0; s < 12; s++) {
  const spk = new THREE.Mesh(new THREE.SphereGeometry(0.012 + Math.random() * 0.012, 8, 8), speckleMat);
  const ang = (s / 12) * Math.PI * 2;
  spk.position.set(Math.cos(ang) * 0.35, 0.30 + Math.random() * 0.40, Math.sin(ang) * 0.32);
  slimeBodyGroup.add(spk);
}
slimeBodyGroup.add(bellyMesh, slimeHeadMesh);
slimeImpGroup.add(slimeBodyGroup);

// 2. OREJAS DE DUENDE PUNTIAGUDAS (Goblin Ears - Grandes y expresivas)
const earsGroup = new THREE.Group();
function createGoblinEar(isLeft) {
  const ear = new THREE.Group();
  const sign = isLeft ? -1 : 1;
  const outerCone = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.52, 16), slimeMat);
  outerCone.scale.set(1.0, 1.0, 0.50);
  outerCone.rotation.z = sign * 0.38;
  outerCone.rotation.x = -0.15;
  outerCone.position.set(sign * 0.28, 1.02, -0.02);

  // Hueco interior oscuro de la oreja
  const innerCone = new THREE.Mesh(new THREE.ConeGeometry(0.11, 0.40, 16), slimeDarkMat);
  innerCone.scale.set(0.9, 0.9, 0.45);
  innerCone.rotation.z = sign * 0.38;
  innerCone.rotation.x = -0.12;
  innerCone.position.set(sign * 0.27, 1.02, 0.02);

  ear.add(outerCone, innerCone);
  return ear;
}
const slimeLeftEar = createGoblinEar(true);
const slimeRightEar = createGoblinEar(false);
earsGroup.add(slimeLeftEar, slimeRightEar);
slimeImpGroup.add(earsGroup);

// 3. BOCA PICARA Y DIENTES AFILADOS (En el frontal de la cara)
const mouthGroup = new THREE.Group();
mouthGroup.position.set(0, 0.57, 0.37);

// Cavidad de la boca abierta
const mouthCavity = new THREE.Mesh(new THREE.SphereGeometry(0.18, 24, 18), mouthInteriorMat);
mouthCavity.scale.set(1.4, 0.85, 0.40);
mouthGroup.add(mouthCavity);

// Lengua de slime
const tongue = new THREE.Mesh(new THREE.SphereGeometry(0.10, 16, 14), tongueMat);
tongue.scale.set(1.2, 0.4, 0.9);
tongue.position.set(0, -0.05, 0.08);
mouthGroup.add(tongue);

// 4 Colmillos afilados marfil (2 superiores, 2 inferiores)
const fangs = [
  { x: -0.10, y: 0.06, z: 0.08, rx: Math.PI },   // Superior izquierdo
  { x: 0.10, y: 0.06, z: 0.08, rx: Math.PI },    // Superior derecho
  { x: -0.13, y: -0.07, z: 0.08, rx: 0 },        // Inferior izquierdo
  { x: 0.13, y: -0.07, z: 0.08, rx: 0 }          // Inferior derecho
];
fangs.forEach(f => {
  const fangMesh = new THREE.Mesh(new THREE.ConeGeometry(0.028, 0.07, 12), teethMat);
  fangMesh.position.set(f.x, f.y, f.z);
  fangMesh.rotation.x = f.rx;
  mouthGroup.add(fangMesh);
});
slimeImpGroup.add(mouthGroup);

// 4. OJOS SALTONES (Visibles si se quitan las gafas)
const eyesGroup = new THREE.Group();
const eyeWhiteMat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.1 });
const pupilMat = new THREE.MeshBasicMaterial({ color: 0x052e16 });
[-0.14, 0.14].forEach(x => {
  const eyeBall = new THREE.Mesh(new THREE.SphereGeometry(0.08, 16, 16), eyeWhiteMat);
  eyeBall.position.set(x, 0.72, 0.32);
  const pupil = new THREE.Mesh(new THREE.SphereGeometry(0.038, 12, 12), pupilMat);
  pupil.position.set(x, 0.72, 0.38);
  eyesGroup.add(eyeBall, pupil);
});
slimeImpGroup.add(eyesGroup);

// 5. GAFAS CAT-EYE FUTURISTAS (Puntas hacia arriba como en la foto)
const glassesGroup = new THREE.Group();
glassesGroup.position.set(0, 0.73, 0.38);

const frameMat = new THREE.MeshStandardMaterial({
  color: 0x0b2618, // Verde oscuro casi negro brillante
  roughness: 0.15,
  metalness: 0.40
});
const lensMat = new THREE.MeshStandardMaterial({
  color: 0x166534, // Lente verde joya reflectante
  roughness: 0.08,
  metalness: 0.80
});

// Montura izquierda y derecha anguladas hacia arriba en diagonal (Cat-Eye)
function createCatEyeFrame(isLeft) {
  const sign = isLeft ? -1 : 1;
  const wing = new THREE.Group();
  // Aro exterior triangular orientado hacia las orejas
  const rim = new THREE.Mesh(new THREE.BoxGeometry(0.20, 0.11, 0.04), frameMat);
  rim.rotation.z = sign * 0.32; // Apunta hacia arriba hacia la oreja
  rim.position.set(sign * 0.15, 0.03, 0);

  // Cristal de la lente
  const lens = new THREE.Mesh(new THREE.BoxGeometry(0.17, 0.08, 0.025), lensMat);
  lens.rotation.z = sign * 0.32;
  lens.position.set(sign * 0.15, 0.03, 0.015);

  wing.add(rim, lens);
  return wing;
}
const leftGlass = createCatEyeFrame(true);
const rightGlass = createCatEyeFrame(false);
// Puente nasal
const bridge = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.03, 0.03), frameMat);
bridge.position.set(0, 0.01, 0.01);
glassesGroup.add(leftGlass, rightGlass, bridge);
slimeImpGroup.add(glassesGroup);

// 6. BRAZOS REGORDETES Y 3 GARRAS/DEDOS
const armsGroup = new THREE.Group();
function createSlimeArm(isLeft) {
  const arm = new THREE.Group();
  const sign = isLeft ? -1 : 1;
  // Hombro y brazo cayendo naturalmente hacia los costados
  const bicep = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.07, 0.30, 16), slimeMat);
  bicep.position.set(sign * 0.38, 0.40, 0.04);
  bicep.rotation.z = sign * 0.35; // Caída hacia abajo
  bicep.rotation.x = 0.15;

  // Manita con 3 dedos puntiagudos
  const hand = new THREE.Mesh(new THREE.SphereGeometry(0.065, 12, 12), slimeMat);
  hand.position.set(sign * 0.44, 0.22, 0.12);
  arm.add(bicep, hand);

  for (let c = -1; c <= 1; c++) {
    const claw = new THREE.Mesh(new THREE.ConeGeometry(0.020, 0.055, 8), slimeMat);
    claw.position.set(sign * 0.44 + c * 0.022, 0.16, 0.15);
    claw.rotation.x = Math.PI / 4;
    arm.add(claw);
  }
  return arm;
}
const slimeLeftArm = createSlimeArm(true);
const slimeRightArm = createSlimeArm(false);
armsGroup.add(slimeLeftArm, slimeRightArm);
slimeImpGroup.add(armsGroup);

// 7. PATITAS CORTAS Y PIES CON 2 DEDOS
const legsGroup = new THREE.Group();
[-0.15, 0.15].forEach(x => {
  const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.08, 0.20, 16), slimeMat);
  leg.position.set(x, 0.10, 0);

  // Pie con 2 dedos redondeados
  const foot = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.06, 0.16), slimeMat);
  foot.position.set(x, 0.03, 0.04);
  legsGroup.add(leg, foot);
});
slimeImpGroup.add(legsGroup);

// 8. ACCESORIOS MONETIZABLES (Sombreros y Ropa Freemium)
const accessoriesGroup = new THREE.Group();

// A. Gorra deportiva (Hacia atrás)
const capGroup = new THREE.Group();
capGroup.position.set(0, 0.88, -0.04);
const capDome = new THREE.Mesh(new THREE.SphereGeometry(0.25, 16, 16), new THREE.MeshStandardMaterial({ color: 0xef4444 }));
capDome.scale.set(1.0, 0.5, 1.0);
const capVisor = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.02, 0.20), new THREE.MeshStandardMaterial({ color: 0xb91c1c }));
capVisor.position.set(0, -0.04, -0.22);
capVisor.rotation.x = 0.15;
capGroup.add(capDome, capVisor);
capGroup.visible = false;

// B. Corona Real Dorada
const crownGroup = new THREE.Group();
crownGroup.position.set(0, 0.94, 0);
const crownBase = new THREE.Mesh(
  new THREE.CylinderGeometry(0.18, 0.16, 0.14, 8),
  new THREE.MeshStandardMaterial({ color: 0xfacc15, metalness: 0.9, roughness: 0.2 })
);
crownGroup.add(crownBase);
crownGroup.visible = false;

// C. Chaleco Táctico SWAT
const vestGroup = new THREE.Group();
vestGroup.position.set(0, 0.44, 0.06);
const vestFront = new THREE.Mesh(
  new THREE.BoxGeometry(0.56, 0.36, 0.42),
  new THREE.MeshStandardMaterial({ color: 0x1e293b, roughness: 0.6 })
);
vestGroup.add(vestFront);
vestGroup.visible = false;

// D. Flotador Patito
const duckFloatGroup = new THREE.Group();
duckFloatGroup.position.set(0, 0.32, 0);
const duckTorus = new THREE.Mesh(
  new THREE.TorusGeometry(0.48, 0.12, 16, 32),
  new THREE.MeshStandardMaterial({ color: 0xfacc15, roughness: 0.2 })
);
duckTorus.rotation.x = Math.PI / 2;
const duckHead = new THREE.Mesh(
  new THREE.SphereGeometry(0.12, 16, 16),
  new THREE.MeshStandardMaterial({ color: 0xfacc15, roughness: 0.2 })
);
duckHead.position.set(0, 0.16, 0.48);
const duckBeak = new THREE.Mesh(
  new THREE.ConeGeometry(0.06, 0.12, 12),
  new THREE.MeshStandardMaterial({ color: 0xf97316 })
);
duckBeak.rotation.x = Math.PI / 2;
duckBeak.position.set(0, 0.14, 0.60);
duckFloatGroup.add(duckTorus, duckHead, duckBeak);
duckFloatGroup.visible = false;

accessoriesGroup.add(capGroup, crownGroup, vestGroup, duckFloatGroup);
slimeImpGroup.add(accessoriesGroup);

scene.add(slimeImpGroup);

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
    camera.position.set(-4.2, 3.2, 3.8);
    controls.target.set(0.2, -0.3, -0.2);
  } else if (type === 'pool-waterline') {
    camera.position.set(-2.6, 0.15, 1.6);
    controls.target.set(0, -0.15, -0.2);
  } else if (type === 'pool-underwater') {
    camera.position.set(0, -0.6, 1.8);
    controls.target.set(0, -0.7, 0);
  } else if (type === 'pool-top') {
    camera.position.set(0, 6.2, 0.01);
    controls.target.set(0, 0, 0);
  } else if (type === 'slime-front') {
    camera.position.set(0, 0.70, 2.2);
    controls.target.set(0, 0.52, 0);
  } else if (type === 'slime-face') {
    camera.position.set(0, 0.68, 1.2);
    controls.target.set(0, 0.62, 0);
  } else if (type === 'slime-angle') {
    camera.position.set(-1.2, 0.90, 1.8);
    controls.target.set(0, 0.52, 0);
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
  } else if (tab === 'tab-character') {
    bar.innerHTML = `
      <button class="cam-btn" onclick="setCameraView('slime-front')">👾 Frontal Slime</button>
      <button class="cam-btn" onclick="setCameraView('slime-face')">🕶️ Gafas & Rostro</button>
      <button class="cam-btn" onclick="setCameraView('slime-angle')">📐 Perspectiva 3D</button>
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

  waterMaterial.opacity = 0.38 + (1.0 - clarity) * 0.30;
  waterMaterial.metalness = reflect * 0.30;
  waterMaterial.roughness = 0.04 + (1.0 - reflect) * 0.20;
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

let currentActiveTab = 'tab-cover';

function switchTab(tabId) {
  const btnCover = document.getElementById('btn-tab-cover');
  const btnMap = document.getElementById('btn-tab-map');
  const btnWater = document.getElementById('btn-tab-water');
  const btnChar = document.getElementById('btn-tab-character');
  const panelCover = document.getElementById('tab-cover');
  const panelMap = document.getElementById('tab-map');
  const panelWater = document.getElementById('tab-water');
  const panelChar = document.getElementById('tab-character');

  [btnCover, btnMap, btnWater, btnChar].forEach(b => b && b.classList.remove('active'));
  [panelCover, panelMap, panelWater, panelChar].forEach(p => p && p.classList.remove('active'));

  currentActiveTab = tabId;

  if (tabId === 'tab-map') {
    if (btnMap) btnMap.classList.add('active');
    if (panelMap) panelMap.classList.add('active');

    // Atmósfera de Cyberpunk / Gran Salón Arcoíris (54m x 54m)
    scene.background = new THREE.Color(0x060913);
    sunLight.intensity = 1.6;
    sunLight.color.setHex(0xe0f2fe);
    sunLight.position.set(10, 18, 12);
    ambientLight.color.setHex(0x1e293b);
    ambientLight.intensity = 1.4;

    coverGroup.visible = false;
    slimeImpGroup.visible = false;
    poolGroup.visible = false;
    patioFloor.visible = true;
    gridHelper.visible = true;
    mapGroup.visible = true;

    gridHelper.scale.set(3, 1, 3);
    patioFloor.scale.set(3, 1, 3);

    transformControl.enabled = true;
    camera.position.set(-8, 9, 14);
    controls.target.set(0, 1.5, 0);
  } else if (tabId === 'tab-water') {
    if (btnWater) btnWater.classList.add('active');
    if (panelWater) panelWater.classList.add('active');

    // Cambiar a iluminación y atmósfera equilibrada de resort soleado
    scene.background = new THREE.Color(0x38bdf8); // Cielo azul caribeño
    sunLight.intensity = 1.3;
    sunLight.color.setHex(0xfff7ed);
    sunLight.position.set(6, 10, 8);
    ambientLight.color.setHex(0x7dd3fc);
    ambientLight.intensity = 0.7;

    coverGroup.visible = false;
    slimeImpGroup.visible = false;
    patioFloor.visible = false;
    gridHelper.visible = false;
    mapGroup.visible = false;
    poolGroup.visible = true;
    transformControl.detach();
    transformControl.enabled = false;

    updateCameraButtons('tab-water');
    setCameraView('pool-resort');
  } else if (tabId === 'tab-character') {
    if (btnChar) btnChar.classList.add('active');
    if (panelChar) panelChar.classList.add('active');

    scene.background = new THREE.Color(0x0b1329);
    sunLight.intensity = 1.4;
    sunLight.color.setHex(0xffffff);
    sunLight.position.set(3, 7, 5);
    ambientLight.color.setHex(0x94a3b8);
    ambientLight.intensity = 0.9;

    coverGroup.visible = false;
    poolGroup.visible = false;
    mapGroup.visible = false;
    patioFloor.visible = true;
    gridHelper.visible = true;
    gridHelper.scale.set(1, 1, 1);
    patioFloor.scale.set(1, 1, 1);
    slimeImpGroup.visible = true;
    transformControl.detach();
    transformControl.enabled = false;

    updateCameraButtons('tab-character');
    setCameraView('slime-front');
  } else {
    if (btnCover) btnCover.classList.add('active');
    if (panelCover) panelCover.classList.add('active');

    scene.background = new THREE.Color(0x070a0f);
    sunLight.intensity = 2.2;
    sunLight.color.setHex(0xfff7e6);
    sunLight.position.set(4, 8, 5);
    ambientLight.color.setHex(0x334455);
    ambientLight.intensity = 1.6;

    coverGroup.visible = true;
    slimeImpGroup.visible = false;
    patioFloor.visible = true;
    gridHelper.visible = true;
    gridHelper.scale.set(1, 1, 1);
    patioFloor.scale.set(1, 1, 1);
    poolGroup.visible = false;
    mapGroup.visible = false;
    transformControl.detach();
    transformControl.enabled = false;

    updateCameraButtons('tab-cover');
    setCameraView('side');
  }
}

// ----------------------------------------------------
// CONTROLADORES DE PERSONALIZACIÓN SLIME IMP (FREEMIUM)
// ----------------------------------------------------
let currentSlimeCustom = {
  skin: 'classic',
  glasses: 'cateye',
  hat: 'none',
  outfit: 'none',
  chubby: 1.15,
  ears: 1.0,
  smile: 1.0
};

function setSlimeSkin(skin) {
  currentSlimeCustom.skin = skin;
  if (skin === 'classic') {
    slimeMat.color.setHex(0x4ade80); // Verde lima vivo
    slimeDarkMat.color.setHex(0x15803d);
    tongueMat.color.setHex(0x22c55e);
    slimeMat.metalness = 0.08;
    slimeMat.roughness = 0.28;
  } else if (skin === 'toxic') {
    slimeMat.color.setHex(0xa855f7); // Neón púrpura veneno
    slimeDarkMat.color.setHex(0x6b21a8);
    tongueMat.color.setHex(0xec4899);
    slimeMat.metalness = 0.15;
    slimeMat.roughness = 0.22;
  } else if (skin === 'magma') {
    slimeMat.color.setHex(0xf97316); // Naranja fuego
    slimeDarkMat.color.setHex(0x9a3412);
    tongueMat.color.setHex(0xeab308);
    slimeMat.metalness = 0.20;
    slimeMat.roughness = 0.25;
  } else if (skin === 'gold') {
    slimeMat.color.setHex(0xfacc15); // Oro VIP pulido
    slimeDarkMat.color.setHex(0xa16207);
    tongueMat.color.setHex(0xf59e0b);
    slimeMat.metalness = 0.88;
    slimeMat.roughness = 0.18;
  }
}

function setSlimeGlasses(type) {
  currentSlimeCustom.glasses = type;
  if (type === 'none') {
    glassesGroup.visible = false;
  } else if (type === 'cateye') {
    glassesGroup.visible = true;
    frameMat.color.setHex(0x0c281a);
    lensMat.color.setHex(0x166534);
    lensMat.metalness = 0.85;
  } else if (type === 'cyber') {
    glassesGroup.visible = true;
    frameMat.color.setHex(0x00e5ff);
    lensMat.color.setHex(0xff007f);
    lensMat.metalness = 0.95;
  } else if (type === 'retro') {
    glassesGroup.visible = true;
    frameMat.color.setHex(0xfacc15);
    lensMat.color.setHex(0x0284c7);
    lensMat.metalness = 0.60;
  }
}

function setSlimeHat(hat) {
  currentSlimeCustom.hat = hat;
  capGroup.visible = (hat === 'cap');
  crownGroup.visible = (hat === 'crown');
}

function setSlimeOutfit(outfit) {
  currentSlimeCustom.outfit = outfit;
  vestGroup.visible = (outfit === 'vest');
  duckFloatGroup.visible = (outfit === 'float');
}

function updateSlimeMorph() {
  const chubby = parseFloat(document.getElementById('slimeChubby').value);
  const ears = parseFloat(document.getElementById('slimeEars').value);
  const smile = parseFloat(document.getElementById('slimeSmile').value);

  document.getElementById('val-slimeChubby').textContent = chubby.toFixed(2) + 'x';
  document.getElementById('val-slimeEars').textContent = ears.toFixed(2) + 'x';
  document.getElementById('val-slimeSmile').textContent = smile.toFixed(2) + 'x';

  currentSlimeCustom.chubby = chubby;
  currentSlimeCustom.ears = ears;
  currentSlimeCustom.smile = smile;

  bellyMesh.scale.set(1.15 * chubby, 1.05 * chubby, 1.10 * chubby);
  earsGroup.scale.set(ears, ears, ears);
  mouthGroup.scale.set(smile, smile, smile);
}

async function exportCharacterPreset() {
  const payload = {
    ...currentSlimeCustom,
    timestamp: new Date().toISOString()
  };

  try {
    const res = await fetch('/api/presets/save-character', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const data = await res.json();
    const badge = document.getElementById('status-character');
    badge.textContent = '✅ ' + (data.message || 'Configuración guardada en presets/');
    badge.style.display = 'block';
    setTimeout(() => { badge.style.display = 'none'; }, 4000);
  } catch (err) {
    alert('Error al guardar personaje: ' + err.message);
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
// 7. BUCLE DE RENDER & ANIMACIÓN ONDULATORIA Y FÍSICAS DE FLOTACIÓN
// ----------------------------------------------------
const posAttr = waterGeometry.attributes.position;
const originalPositions = posAttr.array.slice();

function animate() {
  requestAnimationFrame(animate);
  controls.update();

  // Animación ondulatoria del agua viva y físicas acuáticas
  if (poolGroup.visible) {
    const time = performance.now() * 0.002 * parseFloat(document.getElementById('waterSpeed').value);
    const waveAmp = parseFloat(document.getElementById('waterWaves').value) * 1.5;

    // 1. Deformación vertex de la superficie del agua
    for (let i = 0; i < posAttr.count; i++) {
      const u = originalPositions[i * 3];
      const v = originalPositions[i * 3 + 1];
      const zWave = Math.sin(u * 2.5 + time) * Math.cos(v * 2.2 + time * 0.8) * waveAmp;
      posAttr.setZ(i, zWave);
    }
    posAttr.needsUpdate = true;

    // 2. Flotador salvavidas: cabeceo y balanceo sobre olas
    lifeBuoyGroup.position.y = -0.07 + Math.sin(time * 1.2) * 0.025;
    lifeBuoyGroup.rotation.z = Math.sin(time * 0.8) * 0.05;

    // 3. Pelota de playa: flotabilidad y rotación en deriva
    beachBallMesh.position.y = -0.05 + Math.sin(time * 1.4 + 1.2) * 0.028;
    beachBallMesh.rotation.y += 0.006;
    beachBallMesh.rotation.x = Math.sin(time * 0.6) * 0.08;

    // 4. Boyas de carril: oscilación individual según posición X
    buoysList.forEach(buoy => {
      buoy.position.y = -0.06 + Math.sin(buoy.position.x * 2.5 + time) * waveAmp;
    });

    // 5. Burbujas subacuáticas ascendentes
    bubblesList.forEach(b => {
      b.position.y += b.userData.speedY;
      b.position.x = b.userData.baseX + Math.sin(time * 3.2 + b.userData.wobblePhase) * 0.025;
      if (b.position.y > -0.05) {
        b.position.y = -1.25;
      }
    });
  }

  // 6. Animación viva de respiración del Slime Imp (Squash & Stretch orgánico)
  if (slimeImpGroup.visible) {
    const time = performance.now() * 0.003;
    const breath = Math.sin(time);
    slimeBodyGroup.scale.y = 1.0 + breath * 0.025;
    slimeBodyGroup.scale.x = 1.0 - breath * 0.012;
    slimeLeftEar.rotation.z = -0.42 + Math.sin(time * 0.8) * 0.04;
    slimeRightEar.rotation.z = 0.42 - Math.sin(time * 0.8) * 0.04;
    slimeLeftArm.rotation.x = 0.25 + Math.sin(time) * 0.03;
    slimeRightArm.rotation.x = 0.25 - Math.sin(time) * 0.03;
  }

  renderer.render(scene, camera);
}

window.addEventListener('resize', () => {
  camera.aspect = container.clientWidth / container.clientHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(container.clientWidth, container.clientHeight);
});

// ====================================================
// 🗺️ MOTOR UGC: EDITOR DE MAPAS & ESCENARIOS (ROBLOX / FORTNITE CREATIVE)
// ====================================================
const mapGroup = new THREE.Group();
mapGroup.visible = false;
scene.add(mapGroup);

let mapPropsList = [];
let selectedMapProp = null;
let currentSnapValue = 0.5; // 0.5m por defecto

// Raycaster para selección táctil o con mouse
const mapRaycaster = new THREE.Raycaster();
const mapMouse = new THREE.Vector2();

function setGizmoMode(mode) {
  transformControl.setMode(mode);
  ['gizmo-translate', 'gizmo-rotate', 'gizmo-scale'].forEach(id => {
    const btn = document.getElementById(id);
    if (btn) btn.style.borderColor = 'rgba(255,255,255,0.1)';
  });
  const activeBtn = document.getElementById(`gizmo-${mode}`);
  if (activeBtn) activeBtn.style.borderColor = 'var(--accent-cyan)';
}

function toggleGridSnap() {
  const btn = document.getElementById('snap-toggle');
  if (currentSnapValue === 0.5) {
    currentSnapValue = 1.0;
    transformControl.setTranslationSnap(1.0);
    transformControl.setRotationSnap(THREE.MathUtils.degToRad(15));
    if (btn) btn.innerText = '🧲 Snap: 1.0m';
  } else if (currentSnapValue === 1.0) {
    currentSnapValue = 0.0;
    transformControl.setTranslationSnap(null);
    transformControl.setRotationSnap(null);
    if (btn) btn.innerText = '🧲 Snap: Libre';
  } else {
    currentSnapValue = 0.5;
    transformControl.setTranslationSnap(0.5);
    transformControl.setRotationSnap(THREE.MathUtils.degToRad(45));
    if (btn) btn.innerText = '🧲 Snap: 0.5m';
  }
}
toggleGridSnap(); // Iniciar configurando 0.5m

function createPropMesh(type, colorHex) {
  const group = new THREE.Group();
  group.userData.propType = type;
  group.userData.colorHex = colorHex || 0x00e5ff;

  const matNeon = new THREE.MeshStandardMaterial({
    color: group.userData.colorHex,
    emissive: group.userData.colorHex,
    emissiveIntensity: 0.95,
    roughness: 0.1,
    metalness: 0.2
  });
  const matMetal = new THREE.MeshStandardMaterial({
    color: 0x1f2937,
    roughness: 0.35,
    metalness: 0.8
  });

  if (type === 'neon_post') {
    // Poste de Neón táctico de 3.8m
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.35, 0.45, 0.2, 16), matMetal);
    base.position.y = 0.1;
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 3.4, 16), matMetal);
    pole.position.y = 1.8;
    const lantern = new THREE.Mesh(new THREE.BoxGeometry(0.48, 0.65, 0.48), matNeon);
    lantern.position.y = 3.6;
    lantern.name = 'neonPart';
    const cap = new THREE.Mesh(new THREE.ConeGeometry(0.45, 0.25, 4), matMetal);
    cap.position.y = 4.05;
    cap.rotation.y = Math.PI / 4;
    group.add(base, pole, lantern, cap);
  } else if (type === 'rainbow_cabin') {
    // Cabaña de Cobertura Táctica (3.6m x 3.6m x 3.2m)
    for (let x of [-1.6, 1.6]) {
      for (let z of [-1.6, 1.6]) {
        const post = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.09, 3.0, 12), matMetal);
        post.position.set(x, 1.5, z);
        group.add(post);
      }
    }
    const roof = new THREE.Mesh(new THREE.BoxGeometry(3.6, 0.18, 3.6), matMetal);
    roof.position.y = 3.05;
    const roofTrim = new THREE.Mesh(new THREE.BoxGeometry(3.66, 0.08, 3.66), matNeon);
    roofTrim.position.y = 3.16;
    roofTrim.name = 'neonPart';
    const halfWall = new THREE.Mesh(new THREE.BoxGeometry(3.2, 1.15, 0.15), matMetal);
    halfWall.position.set(0, 0.58, -1.6);
    group.add(roof, roofTrim, halfWall);
  } else if (type === 'mirror_panel') {
    // Escudo/Panel de Espejo Reflectante
    const frame = new THREE.Mesh(new THREE.BoxGeometry(1.8, 2.4, 0.12), matMetal);
    frame.position.y = 1.2;
    const glass = new THREE.Mesh(
      new THREE.BoxGeometry(1.6, 2.2, 0.04),
      new THREE.MeshStandardMaterial({ color: 0xe0f2fe, roughness: 0.02, metalness: 0.98 })
    );
    glass.position.set(0, 1.2, 0.05);
    const border = new THREE.Mesh(new THREE.BoxGeometry(1.84, 0.06, 0.14), matNeon);
    border.position.y = 2.42;
    border.name = 'neonPart';
    group.add(frame, glass, border);
  } else if (type === 'block_low') {
    const box = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.70, 2.4), matMetal);
    box.position.y = 0.35;
    const trim = new THREE.Mesh(new THREE.BoxGeometry(2.46, 0.06, 2.46), matNeon);
    trim.position.y = 0.71;
    trim.name = 'neonPart';
    group.add(box, trim);
  } else if (type === 'block_mid') {
    const box = new THREE.Mesh(new THREE.BoxGeometry(2.8, 1.40, 2.8), matMetal);
    box.position.y = 0.70;
    const trim = new THREE.Mesh(new THREE.BoxGeometry(2.86, 0.06, 2.86), matNeon);
    trim.position.y = 1.41;
    trim.name = 'neonPart';
    group.add(box, trim);
  } else if (type === 'block_high') {
    const box = new THREE.Mesh(new THREE.BoxGeometry(4.2, 2.80, 4.2), matMetal);
    box.position.y = 1.40;
    const trim = new THREE.Mesh(new THREE.BoxGeometry(4.28, 0.08, 4.28), matNeon);
    trim.position.y = 2.82;
    trim.name = 'neonPart';
    group.add(box, trim);
  } else if (type === 'water_patch') {
    const puddle = new THREE.Mesh(
      new THREE.CylinderGeometry(2.2, 2.2, 0.04, 32),
      new THREE.MeshStandardMaterial({ color: 0x0ea5e9, roughness: 0.02, metalness: 0.85, transparent: true, opacity: 0.82 })
    );
    puddle.position.y = 0.02;
    group.add(puddle);
  } else if (type === 'bot_spawner') {
    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(1.1, 0.08, 8, 32),
      new THREE.MeshStandardMaterial({ color: 0xff0055, emissive: 0xff0055, emissiveIntensity: 1.0 })
    );
    ring.rotation.x = Math.PI / 2;
    ring.position.y = 0.04;
    const core = new THREE.Mesh(
      new THREE.OctahedronGeometry(0.35),
      new THREE.MeshStandardMaterial({ color: 0xff0055, emissive: 0xff0055, emissiveIntensity: 1.2 })
    );
    core.position.y = 0.65;
    group.add(ring, core);
  } else if (type === 'base_alpha') {
    const pad = new THREE.Mesh(
      new THREE.CylinderGeometry(2.0, 2.2, 0.15, 32),
      new THREE.MeshStandardMaterial({ color: 0xfef08a, emissive: 0xffd600, emissiveIntensity: 0.85 })
    );
    pad.position.y = 0.08;
    group.add(pad);
  } else if (type === 'base_omega') {
    const pad = new THREE.Mesh(
      new THREE.CylinderGeometry(2.0, 2.2, 0.15, 32),
      new THREE.MeshStandardMaterial({ color: 0xa855f7, emissive: 0x9333ea, emissiveIntensity: 0.85 })
    );
    pad.position.y = 0.08;
    group.add(pad);
  }

  // Activar sombras en todos los hijos
  group.traverse(child => {
    if (child.isMesh) {
      child.castShadow = true;
      child.receiveShadow = true;
      child.userData.parentPropGroup = group;
    }
  });

  return group;
}

function spawnMapProp(type, x = 0, z = 0, colorHex = 0x00e5ff) {
  const prop = createPropMesh(type, colorHex);
  prop.position.set(x, 0, z);
  mapGroup.add(prop);
  mapPropsList.push(prop);
  selectProp(prop);
  updateMapStats();
}

function selectProp(propGroup) {
  selectedMapProp = propGroup;
  if (propGroup) {
    transformControl.attach(propGroup);
    document.getElementById('prop-color-row').style.display = 'flex';
  } else {
    transformControl.detach();
    document.getElementById('prop-color-row').style.display = 'none';
  }
  updateSelectedPropInfo();
}

function updateSelectedPropInfo() {
  const info = document.getElementById('selected-prop-info');
  if (!selectedMapProp) {
    info.innerHTML = 'Ningún objeto seleccionado. Haz clic en un prop en el visor 3D.';
    return;
  }
  const pos = selectedMapProp.position;
  const rot = selectedMapProp.rotation;
  const type = selectedMapProp.userData.propType;
  info.innerHTML = `
    <div style="color: var(--accent-cyan); font-weight: 600;">Prop: ${type}</div>
    <div>Pos: X=${pos.x.toFixed(2)}m, Y=${pos.y.toFixed(2)}m, Z=${pos.z.toFixed(2)}m</div>
    <div>Rot: Y=${(THREE.MathUtils.radToDeg(rot.y)).toFixed(0)}°</div>
  `;
}

function setPropColor(colorHex) {
  if (!selectedMapProp) return;
  selectedMapProp.userData.colorHex = colorHex;
  selectedMapProp.traverse(child => {
    if (child.name === 'neonPart' && child.material) {
      child.material.color.setHex(colorHex);
      child.material.emissive.setHex(colorHex);
    }
  });
}

function duplicateSelectedProp() {
  if (!selectedMapProp) return;
  const type = selectedMapProp.userData.propType;
  const col = selectedMapProp.userData.colorHex;
  const newProp = createPropMesh(type, col);
  newProp.position.copy(selectedMapProp.position).add(new THREE.Vector3(1.0, 0, 1.0));
  newProp.rotation.copy(selectedMapProp.rotation);
  newProp.scale.copy(selectedMapProp.scale);
  mapGroup.add(newProp);
  mapPropsList.push(newProp);
  selectProp(newProp);
  updateMapStats();
}

function deleteSelectedProp() {
  if (!selectedMapProp) return;
  transformControl.detach();
  mapGroup.remove(selectedMapProp);
  mapPropsList = mapPropsList.filter(p => p !== selectedMapProp);
  selectedMapProp = null;
  updateSelectedPropInfo();
  updateMapStats();
}

function clearCustomMap() {
  transformControl.detach();
  selectedMapProp = null;
  mapPropsList.forEach(p => mapGroup.remove(p));
  mapPropsList = [];
  updateSelectedPropInfo();
  updateMapStats();
}

function updateMapStats() {
  const count = mapPropsList.length;
  const header = document.querySelector('#tab-map h3');
  if (header) {
    header.innerHTML = `🎯 Herramientas de Gizmo 3D <span style="font-size:11px; color:var(--text-muted); float:right;">Props: ${count}</span>`;
  }
}

function loadOfficialRainbowMap() {
  clearCustomMap();
  // 4 Cabañas en las esquinas
  spawnMapProp('rainbow_cabin', -12.5, 32.0, 0xff007f);
  spawnMapProp('rainbow_cabin',  12.5, 32.0, 0x00e676);
  spawnMapProp('rainbow_cabin', -12.5, 56.0, 0x00e5ff);
  spawnMapProp('rainbow_cabin',  12.5, 56.0, 0xa855f7);

  // 4 Postes Neón cerca a cabañas
  spawnMapProp('neon_post', -14.5, 29.0, 0xff007f);
  spawnMapProp('neon_post',  14.5, 29.0, 0x00e676);
  spawnMapProp('neon_post', -14.5, 58.0, 0x00e5ff);
  spawnMapProp('neon_post',  14.5, 58.0, 0xa855f7);

  // Pasarelas y bloques de parkour centrales
  spawnMapProp('block_low', 0, 24, 0xff5252);
  spawnMapProp('block_mid', -3.6, 28, 0xff7b00);
  spawnMapProp('block_mid',  3.6, 28, 0xffd600);
  spawnMapProp('block_high', 0, 45, 0x9333ea);
  spawnMapProp('block_mid',  0, 62, 0xff007f);

  // Espejos tácticos
  spawnMapProp('mirror_panel', -5.0, 36, 0x00e5ff);
  spawnMapProp('mirror_panel',  5.0, 36, 0x00e5ff);

  // Bases Alpha y Omega
  spawnMapProp('base_alpha', 0, 19, 0xffd600);
  spawnMapProp('base_omega', 0, 68, 0xa855f7);

  // Charcos reflectantes
  spawnMapProp('water_patch', -7.0, 42, 0x00e5ff);
  spawnMapProp('water_patch',  7.0, 42, 0x00e5ff);

  selectProp(null);
}

function saveCustomMap() {
  const mapData = {
    version: '2.1',
    name: 'SalonRainbow_Custom',
    propsCount: mapPropsList.length,
    props: mapPropsList.map(p => ({
      type: p.userData.propType,
      position: [p.position.x, p.position.y, p.position.z],
      rotation: [p.rotation.x, p.rotation.y, p.rotation.z],
      scale: [p.scale.x, p.scale.y, p.scale.z],
      colorHex: p.userData.colorHex
    }))
  };

  fetch('/api/save-map', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(mapData)
  })
  .then(res => res.json())
  .then(data => {
    const badge = document.getElementById('status-map');
    badge.innerText = data.message || '✅ ¡Mapa guardado en el servidor!';
    badge.style.display = 'block';
    setTimeout(() => { badge.style.display = 'none'; }, 3500);
  })
  .catch(err => {
    // Si corre offline sin server.py, descargar como archivo JSON
    const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(mapData, null, 2));
    const downloadAnchor = document.createElement('a');
    downloadAnchor.setAttribute("href", dataStr);
    downloadAnchor.setAttribute("download", "custom_map.json");
    document.body.appendChild(downloadAnchor);
    downloadAnchor.click();
    downloadAnchor.remove();
  });
}

// Clic para seleccionar prop en la escena
container.addEventListener('pointerdown', (event) => {
  if (currentActiveTab !== 'tab-map') return;
  // Si estamos haciendo clic sobre el gizmo de transformación, ignorar
  if (transformControl.dragging) return;

  const rect = renderer.domElement.getBoundingClientRect();
  mapMouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
  mapMouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

  mapRaycaster.setFromCamera(mapMouse, camera);
  const intersects = mapRaycaster.intersectObjects(mapGroup.children, true);

  if (intersects.length > 0) {
    let topPropGroup = intersects[0].object;
    while (topPropGroup.parent && topPropGroup.parent !== mapGroup) {
      topPropGroup = topPropGroup.parent;
    }
    selectProp(topPropGroup);
  } else if (!event.target.closest('#sidebar')) {
    // Clic en suelo vacío deselecciona
    selectProp(null);
  }
});

// Atajos de teclado en el editor
window.addEventListener('keydown', (e) => {
  if (currentActiveTab !== 'tab-map') return;
  if (e.target.tagName === 'INPUT') return;

  switch (e.key.toLowerCase()) {
    case 'w': setGizmoMode('translate'); break;
    case 'e': setGizmoMode('rotate'); break;
    case 'r': setGizmoMode('scale'); break;
    case 'd':
      if (selectedMapProp) duplicateSelectedProp();
      break;
    case 'delete':
    case 'backspace':
      if (selectedMapProp) deleteSelectedProp();
      break;
    case 'escape':
      selectProp(null);
      break;
  }
});

// =========================================================================
// 👾 MATERIALES PBR & PERSONALIZACIÓN DE ENEMIGOS (METAL RAY TRACING)
// =========================================================================
let currentMaterialSubject = 'npc';
const materialPresets = {
  npc: { reflect: 0.04, roughness: 0.72, emission: 0.5, color: 0xeb2e56 },
  fotofago: { reflect: 0.04, roughness: 0.85, emission: 0.3, color: 0x050508 },
  player: { reflect: 0.05, roughness: 0.65, emission: 0.2, color: 0x14d1ad }
};

function selectMaterialSubject(subj) {
  currentMaterialSubject = subj;
  document.querySelectorAll('#tab-character .preset-btn[id^="btn-subj-"]').forEach(btn => {
    btn.classList.toggle('active', btn.id === `btn-subj-${subj}`);
  });
  const data = materialPresets[subj];
  if (data) {
    document.getElementById('matReflect').value = data.reflect;
    document.getElementById('val-matReflect').innerText = data.reflect.toFixed(2);
    document.getElementById('matRoughness').value = data.roughness;
    document.getElementById('val-matRoughness').innerText = data.roughness.toFixed(2);
    document.getElementById('matEmission').value = data.emission;
    document.getElementById('val-matEmission').innerText = data.emission.toFixed(1) + 'x';
    applyMaterialToScene(data);
  }
}

function updateEnemyMaterial() {
  const reflect = parseFloat(document.getElementById('matReflect').value);
  const roughness = parseFloat(document.getElementById('matRoughness').value);
  const emission = parseFloat(document.getElementById('matEmission').value);

  document.getElementById('val-matReflect').innerText = reflect.toFixed(2);
  document.getElementById('val-matRoughness').innerText = roughness.toFixed(2);
  document.getElementById('val-matEmission').innerText = emission.toFixed(1) + 'x';

  materialPresets[currentMaterialSubject].reflect = reflect;
  materialPresets[currentMaterialSubject].roughness = roughness;
  materialPresets[currentMaterialSubject].emission = emission;

  applyMaterialToScene({ reflect, roughness, emission });
}

function applyMaterialPreset(presetName) {
  let reflect = 0.04;
  let roughness = 0.75;
  let emission = 0.4;

  if (presetName === 'matte') {
    reflect = 0.04;
    roughness = 0.75;
    emission = 0.3;
  } else if (presetName === 'vantablack') {
    reflect = 0.02;
    roughness = 0.90;
    emission = 0.1;
  } else if (presetName === 'polymer') {
    reflect = 0.08;
    roughness = 0.60;
    emission = 0.5;
  } else if (presetName === 'chrome') {
    reflect = 0.85;
    roughness = 0.08;
    emission = 0.8;
  }

  document.getElementById('matReflect').value = reflect;
  document.getElementById('val-matReflect').innerText = reflect.toFixed(2);
  document.getElementById('matRoughness').value = roughness;
  document.getElementById('val-matRoughness').innerText = roughness.toFixed(2);
  document.getElementById('matEmission').value = emission;
  document.getElementById('val-matEmission').innerText = emission.toFixed(1) + 'x';

  updateEnemyMaterial();
}

function applyMaterialToScene(pbr) {
  armorMat.metalness = pbr.reflect;
  armorMat.roughness = pbr.roughness;

  suitMat.metalness = pbr.reflect * 0.8;
  suitMat.roughness = pbr.roughness;

  scubaTankMat.metalness = pbr.reflect;
  scubaTankMat.roughness = Math.max(0.4, pbr.roughness - 0.1);

  visorMat.emissiveIntensity = pbr.emission;

  if (typeof slimeMat !== 'undefined') {
    slimeMat.metalness = pbr.reflect;
    slimeMat.roughness = pbr.roughness;
  }
}

async function saveEnemyMaterials() {
  const payload = {
    presets: materialPresets,
    activeSubject: currentMaterialSubject,
    timestamp: Date.now()
  };

  try {
    const res = await fetch('/api/save-materials', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const result = await res.json();
    const badge = document.getElementById('status-materials');
    badge.innerText = `✅ ${result.message || 'Materiales sincronizados'}`;
    badge.style.display = 'block';
    setTimeout(() => { badge.style.display = 'none'; }, 4000);
  } catch (err) {
    console.error('Error guardando materiales:', err);
    alert('Materiales configurados localmente (inicia server.py para persistir en disco)');
  }
}

// Inicializar estado inicial
updatePose();
updateRock();
updateWater();
animate();
