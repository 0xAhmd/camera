const { Bonjour } = require('bonjour-service');

/**
 * Discovery
 * 
 * Uses mDNS (Bonjour/Zeroconf) to:
 * 1. Advertise the desktop app on the local network
 * 2. Find any phones advertising themselves (Mode B connection)
 * 
 * Phone can find desktop by looking for _phonecam._tcp service.
 * Desktop can find phone by looking for _phonecam-mobile._tcp service.
 */
class Discovery {
  constructor({ ip, port }) {
    this.ip = ip;
    this.port = port;
    this.bonjour = new Bonjour();
    this.service = null;
    this.browser = null;
    this.onPhoneFound = null;
  }

  start() {
    // Advertise ourselves
    this.service = this.bonjour.publish({
      name: 'PhoneCam Desktop',
      type: 'phonecam',
      protocol: 'tcp',
      port: this.port,
      txt: {
        version: '1',
        ip: this.ip,
      },
    });

    console.log(`[Discovery] Advertising PhoneCam on ${this.ip}:${this.port}`);

    // Browse for phones on the network
    this.browser = this.bonjour.find({ type: 'phonecam-mobile' }, (service) => {
      const phoneIp = service.addresses?.[0] || service.host;
      const phonePort = service.port;
      console.log(`[Discovery] Found phone at ${phoneIp}:${phonePort}`);

      if (this.onPhoneFound) {
        this.onPhoneFound({ ip: phoneIp, port: phonePort });
      }
    });
  }

  stop() {
    this.service?.stop();
    this.browser?.stop();
    this.bonjour.destroy();
  }
}

module.exports = { Discovery };
