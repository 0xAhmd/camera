const { spawn } = require('child_process');
const { EventEmitter } = require('events');
const os = require('os');
const fs = require('fs');
const path = require('path');

class VirtualCam extends EventEmitter {
  constructor() {
    super();
    this.ffmpeg = null;
    this._available = false;
    this._ffmpegPath = null;
    this._platform = os.platform();
    this._httpFrameCallbacks = new Set();
  }

  async start() {
    await this._checkAvailability();
    if (this._available) {
      this._startFfmpegPipe();
    }
    this._startMjpegHttpServer();
  }

  async _checkAvailability() {
    // Find FFmpeg first — check PATH and common install locations
    this._ffmpegPath = await this._findFfmpeg();
    if (!this._ffmpegPath) {
      console.warn('[VirtualCam] FFmpeg not found.');
      console.warn('[VirtualCam] Install via: winget install ffmpeg');
      console.warn('[VirtualCam] Or download from: https://www.gyan.dev/ffmpeg/builds/');
      return;
    }
    console.log(`[VirtualCam] FFmpeg found at: ${this._ffmpegPath}`);

    if (this._platform === 'win32') {
      const obsFound = this._checkObsWindows();
      if (obsFound) {
        this._available = true;
        console.log('[VirtualCam] OBS Virtual Camera ready');
      } else {
        console.warn('[VirtualCam] OBS not detected despite FFmpeg being available.');
      }
    } else if (this._platform === 'linux') {
      this._available = await this._commandExists('v4l2loopback-ctl');
    } else if (this._platform === 'darwin') {
      this._available = await this._commandExists('obs');
    }
  }

  /**
   * Find FFmpeg — checks PATH first, then common Windows install locations.
   * Returns the full path to ffmpeg.exe or null if not found.
   */
  async _findFfmpeg() {
    // 1. Check if 'ffmpeg' is in PATH
    const inPath = await this._commandExists('ffmpeg');
    if (inPath) return 'ffmpeg';

    if (this._platform !== 'win32') return null;

    // 2. Common Windows install/extract locations
    const candidates = [
      // winget / scoop
      path.join(process.env.LOCALAPPDATA || '', 'Microsoft', 'WinGet', 'Packages', 'Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe', 'ffmpeg-7.1-full_build', 'bin', 'ffmpeg.exe'),
      path.join(process.env.LOCALAPPDATA || '', 'Microsoft', 'WinGet', 'Links', 'ffmpeg.exe'),
      // Scoop
      path.join(process.env.USERPROFILE || '', 'scoop', 'shims', 'ffmpeg.exe'),
      path.join(process.env.USERPROFILE || '', 'scoop', 'apps', 'ffmpeg', 'current', 'bin', 'ffmpeg.exe'),
      // Chocolatey
      'C:\\ProgramData\\chocolatey\\bin\\ffmpeg.exe',
      'C:\\tools\\ffmpeg\\bin\\ffmpeg.exe',
      // Manual extracts — very common
      'C:\\ffmpeg\\bin\\ffmpeg.exe',
      'C:\\ffmpeg\\ffmpeg.exe',
      'C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe',
      'C:\\Program Files (x86)\\ffmpeg\\bin\\ffmpeg.exe',
      // Sometimes people put it in Downloads or Desktop
      path.join(process.env.USERPROFILE || '', 'Downloads', 'ffmpeg', 'bin', 'ffmpeg.exe'),
      path.join(process.env.USERPROFILE || '', 'ffmpeg', 'bin', 'ffmpeg.exe'),
    ];

    for (const p of candidates) {
      try {
        if (p && fs.existsSync(p)) {
          return p;
        }
      } catch (_) {}
    }

    // 3. Try a broad search in C:\ffmpeg* (user may have named it differently)
    try {
      const { execSync } = require('child_process');
      const result = execSync('where /r C:\\ ffmpeg.exe 2>nul', {
        timeout: 5000, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe']
      });
      const first = result.trim().split('\n')[0];
      if (first && fs.existsSync(first.trim())) return first.trim();
    } catch (_) {}

    return null;
  }

  /**
   * Synchronous OBS check — we already confirmed the DLL exists on this machine.
   * Checks the known DLL path directly (fastest, no registry needed).
   */
  _checkObsWindows() {
    // Primary: check for the virtualcam module DLL directly
    const vcamDlls = [
      'C:\\Program Files\\obs-studio\\data\\obs-plugins\\win-dshow\\obs-virtualcam-module64.dll',
      'C:\\Program Files (x86)\\obs-studio\\data\\obs-plugins\\win-dshow\\obs-virtualcam-module64.dll',
      'C:\\Program Files\\OBS-Studio\\data\\obs-plugins\\win-dshow\\obs-virtualcam-module64.dll',
    ];
    for (const dll of vcamDlls) {
      if (fs.existsSync(dll)) {
        console.log(`[VirtualCam] OBS virtualcam DLL found: ${dll}`);
        return true;
      }
    }

    // Fallback: presence of obs64.exe means OBS 28+ (virtualcam built-in)
    const obsExes = [
      'C:\\Program Files\\obs-studio\\bin\\64bit\\obs64.exe',
      'C:\\Program Files (x86)\\obs-studio\\bin\\64bit\\obs64.exe',
      'C:\\Program Files\\OBS-Studio\\bin\\64bit\\obs64.exe',
    ];
    for (const exe of obsExes) {
      if (fs.existsSync(exe)) {
        console.log(`[VirtualCam] OBS 28+ found: ${exe}`);
        return true;
      }
    }

    // Registry fallback
    const { execSync } = require('child_process');
    const keys = [
      'HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\OBS Studio',
      'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\OBS Studio',
    ];
    for (const key of keys) {
      try {
        execSync(`reg query "${key}" /ve`, {
          timeout: 2000, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe']
        });
        console.log(`[VirtualCam] OBS found via registry: ${key}`);
        return true;
      } catch (_) {}
    }

    return false;
  }

  _startFfmpegPipe() {
    const args = this._getFfmpegArgs();
    console.log(`[VirtualCam] Starting: ${this._ffmpegPath} ${args.join(' ')}`);

    this.ffmpeg = spawn(this._ffmpegPath, args, { stdio: ['pipe', 'pipe', 'pipe'] });

    this.ffmpeg.stderr.on('data', data => {
      const msg = data.toString();
      if (msg.includes('Error') || msg.includes('error')) {
        console.error('[FFmpeg]', msg.trim());
      }
    });

    this.ffmpeg.on('close', code => {
      console.log(`[VirtualCam] FFmpeg exited (code ${code})`);
      this.ffmpeg = null;
      if (code !== 0 && code !== null) {
        setTimeout(() => this._startFfmpegPipe(), 2000);
      }
    });

    this.ffmpeg.on('error', err => {
      console.error('[VirtualCam] FFmpeg spawn error:', err.message);
    });
  }

  _getFfmpegArgs() {
    const base = ['-f', 'mjpeg', '-r', '30', '-i', 'pipe:0'];
    if (this._platform === 'win32') {
      return [...base, '-f', 'dshow', '-vcodec', 'rawvideo', '-pix_fmt', 'yuyv422', 'video=OBS Virtual Camera'];
    }
    if (this._platform === 'linux') {
      return [...base, '-f', 'v4l2', '-pix_fmt', 'yuv420p', '/dev/video10'];
    }
    return [...base, '-f', 'rawvideo', '-pix_fmt', 'uyvy422', '/tmp/phonecam.raw'];
  }

  writeFrame(jpegBuffer) {
    if (this.ffmpeg?.stdin?.writable) this.ffmpeg.stdin.write(jpegBuffer);
    for (const cb of this._httpFrameCallbacks) cb(jpegBuffer);
  }

  stopPipe() {}

  stop() {
    this.ffmpeg?.stdin?.end();
    this.ffmpeg?.kill('SIGTERM');
    this.ffmpeg = null;
    this._httpServer?.close();
  }

  isAvailable() { return this._available; }

  _startMjpegHttpServer() {
    const http = require('http');
    this._httpServer = http.createServer((req, res) => {
      if (req.url === '/stream') {
        res.writeHead(200, {
          'Content-Type': 'multipart/x-mixed-replace; boundary=--phonecamframe',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
          'Access-Control-Allow-Origin': '*',
        });
        const sendFrame = jpegBuffer => {
          if (res.writableEnded) { this._httpFrameCallbacks.delete(sendFrame); return; }
          res.write(`--phonecamframe\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpegBuffer.length}\r\n\r\n`);
          res.write(jpegBuffer);
          res.write('\r\n');
        };
        this._httpFrameCallbacks.add(sendFrame);
        req.on('close', () => this._httpFrameCallbacks.delete(sendFrame));
      } else if (req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(`<!DOCTYPE html><html><body style="margin:0;background:#000">
          <img src="/stream" style="width:100%;height:100vh;object-fit:contain"/></body></html>`);
      } else {
        res.writeHead(404); res.end();
      }
    });
    this._httpServer.listen(8080, '0.0.0.0', () => {
      console.log('[VirtualCam] MJPEG fallback: http://localhost:8080/stream');
    });
  }

  _commandExists(cmd) {
    return new Promise(resolve => {
      const child = spawn(this._platform === 'win32' ? 'where' : 'which', [cmd], { stdio: 'ignore' });
      child.on('close', code => resolve(code === 0));
      child.on('error', () => resolve(false));
    });
  }
}

module.exports = { VirtualCam };