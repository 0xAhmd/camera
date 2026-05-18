const { spawn } = require('child_process');
const { EventEmitter } = require('events');
const os = require('os');

/**
 * VirtualCam
 * 
 * Pipes JPEG frames from the phone into a virtual webcam device.
 * The OS and apps (Discord, Zoom, OBS) see it as a real webcam.
 * 
 * ─── Windows ────────────────────────────────────────────────────────────────
 * Strategy: FFmpeg → DirectShow OBS Virtual Camera
 * 
 * OBS installs a DirectShow filter called "OBS Virtual Camera".
 * FFmpeg can write to any DirectShow device.
 * OBS does NOT need to be running — just installed.
 * 
 * Install OBS: https://obsproject.com/download (one-time)
 * Install FFmpeg: https://ffmpeg.org/download.html (or: choco install ffmpeg)
 * 
 * Command:
 *   ffmpeg -f mjpeg -r 30 -i pipe:0 -f dshow "video=OBS Virtual Camera"
 * 
 * ─── Linux ──────────────────────────────────────────────────────────────────
 * Strategy: v4l2loopback kernel module + FFmpeg
 * 
 *   sudo apt install v4l2loopback-dkms ffmpeg
 *   sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="PhoneCam"
 *   ffmpeg -f mjpeg -i pipe:0 -f v4l2 /dev/video10
 * 
 * ─── macOS ──────────────────────────────────────────────────────────────────
 * Strategy: OBS + obs-mac-virtualcam
 * 
 *   brew install obs
 *   obs-mac-virtualcam plugin: https://github.com/johnboiles/obs-mac-virtualcam
 * 
 * ─── Fallback ───────────────────────────────────────────────────────────────
 * If no virtual cam is available, the app still works as a window preview.
 * We also expose an HTTP MJPEG server at http://localhost:8080/stream
 * so OBS can add it as a "Browser Source" or "Media Source (MJPEG URL)".
 */
class VirtualCam extends EventEmitter {
  constructor() {
    super();
    this.ffmpeg = null;
    this._available = false;
    this._platform = os.platform();

    // Fallback MJPEG HTTP server
    this._httpFrameCallbacks = new Set();
  }

  async start() {
    await this._checkAvailability();
    if (this._available) {
      this._startFfmpegPipe();
    }
    // Always start the fallback HTTP MJPEG server
    this._startMjpegHttpServer();
  }

  async _checkAvailability() {
    // Check if FFmpeg is in PATH
    const ffmpegAvailable = await this._commandExists('ffmpeg');
    if (!ffmpegAvailable) {
      console.warn('[VirtualCam] FFmpeg not found. Falling back to HTTP MJPEG only.');
      console.warn('[VirtualCam] Install FFmpeg: https://ffmpeg.org/download.html');
      return;
    }

    if (this._platform === 'win32') {
      // Check for OBS Virtual Camera DirectShow device
      const obsVcamAvailable = await this._checkObsVcam();
      if (obsVcamAvailable) {
        this._available = true;
        console.log('[VirtualCam] OBS Virtual Camera found — using DirectShow');
      } else {
        console.warn('[VirtualCam] OBS Virtual Camera not found.');
        console.warn('[VirtualCam] Install OBS Studio: https://obsproject.com');
      }
    } else if (this._platform === 'linux') {
      const v4l2Available = await this._commandExists('v4l2loopback');
      if (v4l2Available) {
        this._available = true;
        console.log('[VirtualCam] v4l2loopback found');
      }
    } else if (this._platform === 'darwin') {
      // macOS: check for OBS virtualcam
      this._available = await this._commandExists('obs');
    }
  }

  _startFfmpegPipe() {
    const args = this._getFfmpegArgs();
    console.log('[VirtualCam] Starting FFmpeg:', 'ffmpeg', args.join(' '));

    this.ffmpeg = spawn('ffmpeg', args, {
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    this.ffmpeg.stderr.on('data', (data) => {
      // FFmpeg logs to stderr — filter to only show errors
      const msg = data.toString();
      if (msg.includes('Error') || msg.includes('error')) {
        console.error('[FFmpeg]', msg.trim());
      }
    });

    this.ffmpeg.on('close', (code) => {
      console.log(`[VirtualCam] FFmpeg exited with code ${code}`);
      this.ffmpeg = null;
      // Restart after 2 seconds if unexpectedly closed
      if (code !== 0 && code !== null) {
        setTimeout(() => this._startFfmpegPipe(), 2000);
      }
    });

    this.ffmpeg.on('error', (err) => {
      console.error('[VirtualCam] FFmpeg spawn error:', err.message);
    });
  }

  _getFfmpegArgs() {
    const inputArgs = [
      '-f', 'mjpeg',
      '-r', '30',
      '-i', 'pipe:0',
    ];

    if (this._platform === 'win32') {
      return [
        ...inputArgs,
        '-f', 'dshow',
        '-vcodec', 'rawvideo',
        '-pix_fmt', 'yuyv422',
        'video=OBS Virtual Camera',
      ];
    } else if (this._platform === 'linux') {
      return [
        ...inputArgs,
        '-f', 'v4l2',
        '-pix_fmt', 'yuv420p',
        '/dev/video10',
      ];
    } else {
      // macOS fallback — write to a named pipe or use obs-virtualcam
      return [
        ...inputArgs,
        '-f', 'rawvideo',
        '-pix_fmt', 'uyvy422',
        '/tmp/phonecam.raw',
      ];
    }
  }

  writeFrame(jpegBuffer) {
    // Write to FFmpeg stdin (virtual cam)
    if (this.ffmpeg?.stdin?.writable) {
      this.ffmpeg.stdin.write(jpegBuffer);
    }

    // Also notify HTTP MJPEG server
    for (const cb of this._httpFrameCallbacks) {
      cb(jpegBuffer);
    }
  }

  stopPipe() {
    // Don't kill FFmpeg — just stop writing frames (phone disconnected)
    // FFmpeg will stall, which is fine
  }

  stop() {
    this.ffmpeg?.stdin?.end();
    this.ffmpeg?.kill('SIGTERM');
    this.ffmpeg = null;
    this._httpServer?.close();
  }

  isAvailable() {
    return this._available;
  }

  // ── HTTP MJPEG fallback server ─────────────────────────────────────────────
  // Accessible at http://localhost:8080/stream
  // OBS can use this as a "Media Source" with URL input

  _startMjpegHttpServer() {
    const http = require('http');
    this._httpServer = http.createServer((req, res) => {
      if (req.url === '/stream') {
        res.writeHead(200, {
          'Content-Type': 'multipart/x-mixed-replace; boundary=--phonecamframe',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        });

        const sendFrame = (jpegBuffer) => {
          if (res.writableEnded) {
            this._httpFrameCallbacks.delete(sendFrame);
            return;
          }
          res.write(`--phonecamframe\r\nContent-Type: image/jpeg\r\nContent-Length: ${jpegBuffer.length}\r\n\r\n`);
          res.write(jpegBuffer);
          res.write('\r\n');
        };

        this._httpFrameCallbacks.add(sendFrame);
        req.on('close', () => this._httpFrameCallbacks.delete(sendFrame));

      } else if (req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(`
          <!DOCTYPE html>
          <html>
          <body style="margin:0;background:#000">
          <img src="/stream" style="width:100%;height:100vh;object-fit:contain" />
          </body>
          </html>
        `);
      } else {
        res.writeHead(404);
        res.end();
      }
    });

    this._httpServer.listen(8080, '0.0.0.0', () => {
      console.log('[VirtualCam] MJPEG HTTP server at http://localhost:8080/stream');
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  _commandExists(cmd) {
    return new Promise((resolve) => {
      const which = this._platform === 'win32' ? 'where' : 'which';
      const child = spawn(which, [cmd]);
      child.on('close', (code) => resolve(code === 0));
      child.on('error', () => resolve(false));
    });
  }

  async _checkObsVcam() {
    // On Windows, check if OBS Virtual Camera DirectShow filter is registered
    // It registers itself at: HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID
    // We check by trying to list DirectShow devices with FFmpeg
    return new Promise((resolve) => {
      const child = spawn('ffmpeg', ['-f', 'dshow', '-list_devices', 'true', '-i', 'dummy'], {
        stdio: ['ignore', 'ignore', 'pipe'],
      });
      let output = '';
      child.stderr.on('data', (d) => { output += d.toString(); });
      child.on('close', () => {
        resolve(output.toLowerCase().includes('obs virtual camera'));
      });
      child.on('error', () => resolve(false));
    });
  }
}

module.exports = { VirtualCam };
