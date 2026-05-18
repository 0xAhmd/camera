const { EventEmitter } = require('events');
const { WebSocketServer } = require('ws');

/**
 * WsReceiver
 * 
 * Listens on a port for incoming WebSocket connections from the phone.
 * Phone connects to desktop (desktop is server, phone is client).
 * 
 * Wait — isn't the phone the server in the mobile code?
 * 
 * ARCHITECTURE NOTE:
 * We support both modes:
 * Mode A (QR connect): Desktop shows QR → phone scans → phone connects to desktop WS
 * Mode B (auto-discover): Desktop finds phone via mDNS → desktop connects to phone WS
 * 
 * This file implements Mode A (desktop as WS server).
 * The Discovery module handles Mode B (desktop connects to phone).
 * Both feed frames into the same pipeline.
 */
class WsReceiver extends EventEmitter {
  constructor({ port = 9001 } = {}) {
    super();
    this.port = port;
    this.wss = null;
    this.client = null;  // one phone at a time
    this._connected = false;

    // FPS tracking
    this._frameCount = 0;
    this._fpsTimer = Date.now();
    this._fps = 0;
    this._byteCount = 0;
  }

  start() {
    this.wss = new WebSocketServer({ port: this.port });
    console.log(`[WsReceiver] Listening on port ${this.port}`);

    this.wss.on('connection', (ws, req) => {
      // Only allow one connection at a time
      if (this.client) {
        console.log('[WsReceiver] Second phone tried to connect — rejecting');
        ws.close(1008, 'Already connected');
        return;
      }

      const remoteIp = req.socket.remoteAddress;
      console.log(`[WsReceiver] Phone connected from ${remoteIp}`);

      this.client = ws;
      this._connected = true;

      this.emit('connected', { ip: remoteIp, port: this.port });

      ws.on('message', (data, isBinary) => {
        if (isBinary) {
          // Binary = JPEG frame
          this._frameCount++;
          this._byteCount += data.length;
          
          // FPS tracking
          const now = Date.now();
          if (now - this._fpsTimer >= 1000) {
            this._fps = this._frameCount;
            this._frameCount = 0;
            this._fpsTimer = now;
            
            const kbps = Math.round(this._byteCount / 1024);
            this._byteCount = 0;

            this.emit('stats', { fps: this._fps, kbps });
          }

          this.emit('frame', data);
        } else {
          // Text = control message from phone (e.g. camera switched)
          try {
            const msg = JSON.parse(data.toString());
            this.emit('control', msg);
          } catch (_) {}
        }
      });

      ws.on('close', () => {
        console.log('[WsReceiver] Phone disconnected');
        this.client = null;
        this._connected = false;
        this.emit('disconnected');
      });

      ws.on('error', (err) => {
        console.error('[WsReceiver] WS error:', err.message);
        this.client = null;
        this._connected = false;
        this.emit('disconnected');
      });

      // Heartbeat ping every 5 seconds to detect dead connections
      const pingInterval = setInterval(() => {
        if (ws.readyState === ws.OPEN) {
          ws.ping();
        } else {
          clearInterval(pingInterval);
        }
      }, 5000);

      ws.on('pong', () => {
        // Phone is alive
      });
    });

    this.wss.on('error', (err) => {
      console.error('[WsReceiver] Server error:', err.message);
    });
  }

  sendControl(cmd) {
    if (this.client?.readyState === 1) { // OPEN
      this.client.send(JSON.stringify(cmd));
    }
  }

  isConnected() {
    return this._connected;
  }

  stop() {
    this.client?.close();
    this.wss?.close();
  }
}

module.exports = { WsReceiver };
