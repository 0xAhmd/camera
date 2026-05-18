// PhoneCam Desktop Renderer
// Handles: frame rendering, QR generation, status updates, controls

const canvas = document.getElementById('preview');
const ctx = canvas.getContext('2d');
const overlay = document.getElementById('preview-overlay');
const statsOverlay = document.getElementById('stats-overlay');
const statusDot = document.getElementById('status-dot');
const qrIp = document.getElementById('qr-ip');
const fpsStat = document.getElementById('fps-stat');
const kbpsStat = document.getElementById('kbps-stat');
const vcamBadge = document.getElementById('vcam-badge');
const warnVcam = document.getElementById('warn-vcam');
const btnFlip = document.getElementById('btn-flip');
const mjpegUrl = document.getElementById('mjpeg-url');

let isConnected = false;
let qrGenerated = false;

// ── Init ────────────────────────────────────────────────────────────────────

window.phonecam.on('ready', ({ ip, port, virtualCamAvailable }) => {
  const connectionStr = `phonecam://${ip}:${port}`;

  qrIp.textContent = `${ip}:${port}`;
  mjpegUrl.textContent = `http://${ip}:8080/stream`;

  // Generate QR code
  if (!qrGenerated) {
    qrGenerated = true;
    new QRCode(document.getElementById('qr-canvas'), {
      text: connectionStr,
      width: 96,
      height: 96,
      colorDark: '#000000',
      colorLight: '#ffffff',
      correctLevel: QRCode.CorrectLevel.M,
    });
  }

  // Show virtual cam status
  if (virtualCamAvailable) {
    vcamBadge.textContent = 'Virtual cam active';
    vcamBadge.className = 'badge badge--on';
    vcamBadge.classList.remove('hidden');
    warnVcam.classList.add('hidden');
  } else {
    vcamBadge.textContent = 'No virtual cam';
    vcamBadge.className = 'badge badge--off';
    vcamBadge.classList.remove('hidden');
    warnVcam.classList.remove('hidden');
  }
});

// ── Connection events ────────────────────────────────────────────────────────

window.phonecam.on('phone:connected', (info) => {
  isConnected = true;
  statusDot.classList.add('connected');
  overlay.classList.add('hidden');
  statsOverlay.classList.remove('hidden');
  btnFlip.disabled = false;
  console.log('Phone connected:', info);
});

window.phonecam.on('phone:disconnected', () => {
  isConnected = false;
  statusDot.classList.remove('connected');
  overlay.classList.remove('hidden');
  statsOverlay.classList.add('hidden');
  btnFlip.disabled = true;
  fpsStat.textContent = '0 fps';
  kbpsStat.textContent = '0 kb/s';

  // Clear canvas
  ctx.clearRect(0, 0, canvas.width, canvas.height);
});

// ── Frame rendering ──────────────────────────────────────────────────────────

// Buffer for latest frame to avoid race conditions
let pendingFrame = null;
let renderScheduled = false;

window.phonecam.on('frame', (jpegBuffer) => {
  // jpegBuffer is a Buffer (Uint8Array) of raw JPEG bytes
  pendingFrame = jpegBuffer;
  if (!renderScheduled) {
    renderScheduled = true;
    requestAnimationFrame(renderFrame);
  }
});

function renderFrame() {
  renderScheduled = false;
  if (!pendingFrame) return;

  const buffer = pendingFrame;
  pendingFrame = null;

  // Convert Buffer to Blob → URL → Image → draw on canvas
  const blob = new Blob([buffer], { type: 'image/jpeg' });
  const url = URL.createObjectURL(blob);
  const img = new Image();

  img.onload = () => {
    // Resize canvas to match image if needed
    if (canvas.width !== img.naturalWidth || canvas.height !== img.naturalHeight) {
      canvas.width = img.naturalWidth;
      canvas.height = img.naturalHeight;
    }
    ctx.drawImage(img, 0, 0);
    URL.revokeObjectURL(url);
  };

  img.onerror = () => URL.revokeObjectURL(url);
  img.src = url;
}

// ── Stats ────────────────────────────────────────────────────────────────────

window.phonecam.on('stats', ({ fps, kbps }) => {
  fpsStat.textContent = `${fps} fps`;
  kbpsStat.textContent = `${kbps} kb/s`;
});

// ── Controls ─────────────────────────────────────────────────────────────────

btnFlip.addEventListener('click', () => {
  window.phonecam.sendControl({ cmd: 'switch_camera' });
});

// Resolution buttons
document.querySelectorAll('.res-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.res-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    window.phonecam.sendControl({ cmd: 'set_resolution', value: btn.dataset.res });
  });
});

// FPS buttons
document.querySelectorAll('.fps-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.fps-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    window.phonecam.sendControl({ cmd: `set_fps_${btn.dataset.fps}` });
  });
});

// OBS install link
document.getElementById('obs-link')?.addEventListener('click', (e) => {
  e.preventDefault();
  window.open('https://obsproject.com/download');
});

// ── Initial status fetch ─────────────────────────────────────────────────────

window.phonecam.getStatus().then((status) => {
  if (status.connected) {
    // Already connected (e.g. window was hidden and re-shown)
    window.phonecam.on('phone:connected', () => {}); // re-trigger
  }
});
