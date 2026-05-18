const { contextBridge, ipcRenderer } = require('electron');

// Expose a safe API to the renderer (no raw Node access)
contextBridge.exposeInMainWorld('phonecam', {
  // Get current status
  getStatus: () => ipcRenderer.invoke('get-status'),

  // Listen for events from main process
  on: (channel, callback) => {
    const allowed = ['ready', 'phone:connected', 'phone:disconnected', 'frame', 'stats'];
    if (allowed.includes(channel)) {
      ipcRenderer.on(channel, (event, ...args) => callback(...args));
    }
  },

  // Remove listener
  off: (channel, callback) => {
    ipcRenderer.removeListener(channel, callback);
  },

  // Send control command to phone (switch camera, etc.)
  sendControl: (cmd) => ipcRenderer.send('send-control', cmd),
});
