const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage } = require('electron');
const path = require('path');
const os = require('os');
const { WsReceiver } = require('./server/ws-receiver');
const { VirtualCam } = require('./server/virtual-cam');
const { Discovery } = require('./server/discovery');

let mainWindow;
let tray;
let wsReceiver;
let virtualCam;
let discovery;

// ── App setup ────────────────────────────────────────────────────────────────

app.whenReady().then(async () => {
  createWindow();
  setupTray();
  await startServices();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

app.on('before-quit', async () => {
  await stopServices();
});

// ── Window ────────────────────────────────────────────────────────────────────

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 520,
    height: 680,
    minWidth: 400,
    minHeight: 500,
    backgroundColor: '#0D0D0F',
    titleBarStyle: 'hidden',        // custom titlebar
    titleBarOverlay: {
      color: '#0D0D0F',
      symbolColor: '#EEEEEF',
      height: 40,
    },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer/index.html'));

  // Open DevTools in dev mode
  if (process.env.NODE_ENV === 'development') {
    mainWindow.webContents.openDevTools({ mode: 'detach' });
  }
}

// ── System tray ───────────────────────────────────────────────────────────────

function setupTray() {
  // Minimal 16x16 icon — replace with real icon file in production
  const icon = nativeImage.createEmpty();
  tray = new Tray(icon);
  
  const contextMenu = Menu.buildFromTemplate([
    { label: 'Open PhoneCam', click: () => mainWindow?.show() },
    { type: 'separator' },
    { label: 'Quit', click: () => app.quit() },
  ]);
  
  tray.setToolTip('PhoneCam — Waiting for phone...');
  tray.setContextMenu(contextMenu);
  tray.on('click', () => mainWindow?.show());
}

// ── Services ──────────────────────────────────────────────────────────────────

async function startServices() {
  const localIp = getLocalIp();

  // 1. WebSocket receiver — listens for phone connection on port 9001
  wsReceiver = new WsReceiver({ port: 9001 });
  
  wsReceiver.on('connected', (info) => {
    mainWindow?.webContents.send('phone:connected', info);
    tray?.setToolTip('PhoneCam — Phone connected');
  });

  wsReceiver.on('disconnected', () => {
    mainWindow?.webContents.send('phone:disconnected');
    virtualCam?.stopPipe();
    tray?.setToolTip('PhoneCam — Waiting for phone...');
  });

  wsReceiver.on('frame', (jpegBuffer) => {
    // Forward frame to virtual cam pipe
    virtualCam?.writeFrame(jpegBuffer);
    
    // Also send to renderer for preview (every 3rd frame to save IPC)
    if (frameCounter++ % 3 === 0) {
      mainWindow?.webContents.send('frame', jpegBuffer);
    }
  });

  wsReceiver.on('stats', (stats) => {
    mainWindow?.webContents.send('stats', stats);
  });

  wsReceiver.start();

  // 2. Virtual camera — FFmpeg → OS virtual webcam
  virtualCam = new VirtualCam();
  await virtualCam.start();

  // 3. mDNS discovery — broadcasts our presence on local network
  discovery = new Discovery({ ip: localIp, port: 9001 });
  discovery.start();

  // Tell renderer we're ready
  mainWindow?.webContents.once('did-finish-load', () => {
    mainWindow.webContents.send('ready', {
      ip: localIp,
      port: 9001,
      virtualCamAvailable: virtualCam.isAvailable(),
    });
  });
}

async function stopServices() {
  wsReceiver?.stop();
  virtualCam?.stop();
  discovery?.stop();
}

// ── IPC handlers ──────────────────────────────────────────────────────────────

let frameCounter = 0;

// Renderer asking for current status
ipcMain.handle('get-status', () => ({
  ip: getLocalIp(),
  port: 9001,
  virtualCamAvailable: virtualCam?.isAvailable() ?? false,
  connected: wsReceiver?.isConnected() ?? false,
}));

// Renderer sends control command to phone
ipcMain.on('send-control', (event, cmd) => {
  wsReceiver?.sendControl(cmd);
});

// ── Helpers ───────────────────────────────────────────────────────────────────

function getLocalIp() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return '127.0.0.1';
}
