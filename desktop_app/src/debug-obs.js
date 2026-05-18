/**
 * Run this from desktop_app folder:
 *   node src/debug-obs.js
 *
 * It will print exactly what it finds so you know why detection fails.
 */

const { execSync, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

console.log('\n=== OBS Virtual Camera Detection Debug ===\n');

// 1. Registry checks
const registryKeys = [
  'HKLM\\SOFTWARE\\Classes\\CLSID\\{A3FCE0F5-3493-419F-958A-ABA1D1C56AB8}',
  'HKLM\\SOFTWARE\\WOW6432Node\\Classes\\CLSID\\{A3FCE0F5-3493-419F-958A-ABA1D1C56AB8}',
  // OBS 28+ new virtualcam CLSID
  'HKLM\\SOFTWARE\\Classes\\CLSID\\{1F97EA12-E6E6-4E29-BEBB-36DC68D25F99}',
  'HKLM\\SOFTWARE\\WOW6432Node\\Classes\\CLSID\\{1F97EA12-E6E6-4E29-BEBB-36DC68D25F99}',
  // OBS uninstall key
  'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\OBS Studio',
  'HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\OBS Studio',
];

console.log('--- Registry ---');
for (const key of registryKeys) {
  try {
    const out = execSync(`reg query "${key}" /ve 2>nul`, {
      timeout: 3000, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe']
    });
    console.log(`✓ FOUND: ${key}`);
    console.log(`  ${out.trim().split('\n')[2] || ''}`);
  } catch (_) {
    console.log(`✗ NOT FOUND: ${key}`);
  }
}

// 2. File system checks
console.log('\n--- File System ---');
const paths = [
  'C:\\Program Files\\obs-studio',
  'C:\\Program Files (x86)\\obs-studio',
  'C:\\Program Files\\OBS-Studio',
  'C:\\Program Files\\obs-studio\\bin\\64bit\\obs64.exe',
  'C:\\Program Files\\obs-studio\\data\\obs-plugins\\win-dshow',
  'C:\\Program Files\\obs-studio\\obs-plugins\\64bit',
  'C:\\Program Files\\obs-studio\\data\\obs-plugins\\win-dshow\\obs-virtualcam-module64.dll',
  'C:\\Program Files\\obs-studio\\obs-plugins\\64bit\\win-dshow.dll',
];

for (const p of paths) {
  try {
    const exists = fs.existsSync(p);
    console.log(`${exists ? '✓' : '✗'} ${p}`);
  } catch (e) {
    console.log(`? ${p} (error: ${e.message})`);
  }
}

// 3. Find ALL obs-related files anywhere in Program Files
console.log('\n--- Searching Program Files for obs-studio folder ---');
try {
  const result = spawnSync('cmd', ['/c', 'dir', '/s', '/b', 'C:\\Program Files\\obs*'], {
    encoding: 'utf8', timeout: 5000
  });
  if (result.stdout) {
    result.stdout.split('\n').slice(0, 20).forEach(l => l.trim() && console.log(' ', l.trim()));
  } else {
    console.log('  Nothing found in C:\\Program Files\\obs*');
  }
} catch (_) {}

// 4. FFmpeg check
console.log('\n--- FFmpeg ---');
try {
  const ffmpegVersion = execSync('ffmpeg -version 2>&1', { encoding: 'utf8', timeout: 3000 });
  console.log('✓ FFmpeg found:', ffmpegVersion.split('\n')[0]);
} catch (_) {
  console.log('✗ FFmpeg NOT found in PATH');
}

// 5. FFmpeg DirectShow device list
console.log('\n--- FFmpeg DirectShow devices ---');
try {
  const result = spawnSync('ffmpeg', ['-f', 'dshow', '-list_devices', 'true', '-i', 'dummy'], {
    encoding: 'utf8', timeout: 8000
  });
  const output = (result.stderr || '') + (result.stdout || '');
  const lines = output.split('\n').filter(l => l.includes('DirectShow') || l.includes('video') || l.includes('OBS') || l.includes('@device'));
  if (lines.length > 0) {
    lines.forEach(l => console.log(' ', l.trim()));
  } else {
    console.log('  No relevant device lines found');
    console.log('  Raw output (first 20 lines):');
    output.split('\n').slice(0, 20).forEach(l => l.trim() && console.log('   ', l.trim()));
  }
} catch (e) {
  console.log('  FFmpeg dshow listing failed:', e.message);
}

console.log('\n=== Done. Paste this output so we can fix detection. ===\n');