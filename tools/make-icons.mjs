// Génère les icônes PNG de l'app sans dépendance externe (zlib natif de Node).
// Usage : node tools/make-icons.mjs
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const OUT = resolve(import.meta.dirname, '..', 'web', 'icons');
mkdirSync(OUT, { recursive: true });

const crcTable = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();
const crc32 = buf => {
  let c = -1;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
};
const chunk = (type, data) => {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
};
function png(size, rgb) {              // rgb: Buffer de size*size*3
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; ihdr[9] = 2;            // 8 bits, truecolor RGB
  const raw = Buffer.alloc(size * (size * 3 + 1));
  for (let y = 0; y < size; y++) {
    raw[y * (size * 3 + 1)] = 0;       // filter none
    rgb.copy(raw, y * (size * 3 + 1) + 1, y * size * 3, (y + 1) * size * 3);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// Silhouette : tête + épaules, en coordonnées normalisées 0..1
const figure = (x, y, cx) => {
  const dx = x - cx, dy = y - 0.33;
  if (dx * dx + dy * dy < 0.115 * 0.115) return true;          // tête
  if (y >= 0.50 && y <= 0.85 && Math.abs(dx) < 0.16 + (y - 0.50) * 0.42) return true; // épaules
  return false;
};

function render(size) {
  const buf = Buffer.alloc(size * size * 3);
  const SS = 4, inv = 1 / (SS * SS);
  for (let py = 0; py < size; py++) {
    for (let px = 0; px < size; px++) {
      let solid = 0, ghost = 0;
      for (let sy = 0; sy < SS; sy++) for (let sx = 0; sx < SS; sx++) {
        const x = (px + (sx + 0.5) / SS) / size;
        const y = (py + (sy + 0.5) / SS) / size;
        if (figure(x, y, 0.44)) solid++;
        else if (figure(x - 0.13, y - 0.03, 0.44)) ghost++;    // le "guide" décalé
      }
      // fond noir, guide gris, silhouette blanche
      const v = Math.min(255, Math.round(255 * solid * inv + 105 * ghost * inv));
      const i = (py * size + px) * 3;
      buf[i] = buf[i + 1] = buf[i + 2] = v;
    }
  }
  return buf;
}

for (const size of [180, 512, 1024]) {
  const file = resolve(OUT, `icon-${size}.png`);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, png(size, render(size)));
  console.log('écrit', file);
}
