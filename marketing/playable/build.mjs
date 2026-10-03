// Builds the playable ad from src/playable.html, with the game's sounds and
// icon inlined (ad networks allow no outside files):
//
//   dist/stack-the-cats-meta.html    Meta (Facebook, Instagram): one file
//   dist/stack-the-cats-google.zip   Google Ads / AdMob: index.html in a zip
//   dist/preview.html                open in a browser to try it
//
// Run: node marketing/playable/build.mjs

import { mkdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { crc32, deflateRawSync } from 'node:zlib';

const here = dirname(fileURLToPath(import.meta.url));
const audio = join(here, '../../assets/audio');
const dist = join(here, 'dist');

const SOUNDS = [
  'screen_tap', 'thump', 'cat_purrfect', 'cat_meow_2', 'cat_meow_3', 'cat_misses',
  'tower_tumbles', 'game_over', 'applause', 'chime_1', 'chime_2', 'chime_3', 'chime_4',
];

const sfx = SOUNDS.map((name) =>
  `${JSON.stringify(name)}:${JSON.stringify(readFileSync(join(audio, `${name}.mp3`)).toString('base64'))}`,
).join(',');
const icon = 'data:image/png;base64,' + readFileSync(join(here, 'src/icon.png')).toString('base64');

const source = readFileSync(join(here, 'src/playable.html'), 'utf8');
const page = (head) => source
  .replace('/*SFX*/', sfx)
  .replace('/*ICON*/', icon)
  .replace('<!--HEAD-->', head);

// Google's playables leave the ad through its ExitApi.
const googleHead =
  '<script type="text/javascript" src="https://tpc.googlesyndication.com/pagead/gadgets/html5/api/exitapi.js"></script>';

mkdirSync(dist, { recursive: true });
const meta = page('');
writeFileSync(join(dist, 'stack-the-cats-meta.html'), meta);
writeFileSync(join(dist, 'preview.html'), meta);
writeFileSync(join(dist, 'stack-the-cats-google.zip'), zip({ 'index.html': page(googleHead) }));

for (const f of ['stack-the-cats-meta.html', 'stack-the-cats-google.zip']) {
  console.log(`${f}  ${(statSync(join(dist, f)).size / 1024).toFixed(0)} KB`);
}

/** A minimal zip file (deflated entries). */
function zip(files) {
  const parts = [];
  const central = [];
  let offset = 0;
  for (const [name, content] of Object.entries(files)) {
    const data = Buffer.from(content);
    const packed = deflateRawSync(data, { level: 9 });
    const nameBuf = Buffer.from(name);
    const crc = crc32(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(8, 8); // deflate
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(packed.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    parts.push(local, nameBuf, packed);

    const entry = Buffer.alloc(46);
    entry.writeUInt32LE(0x02014b50, 0);
    entry.writeUInt16LE(20, 4);
    entry.writeUInt16LE(20, 6);
    entry.writeUInt16LE(8, 10);
    entry.writeUInt32LE(crc, 16);
    entry.writeUInt32LE(packed.length, 20);
    entry.writeUInt32LE(data.length, 24);
    entry.writeUInt16LE(nameBuf.length, 28);
    entry.writeUInt32LE(offset, 42);
    central.push(entry, nameBuf);
    offset += local.length + nameBuf.length + packed.length;
  }
  const centralSize = central.reduce((n, b) => n + b.length, 0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(central.length / 2, 8);
  end.writeUInt16LE(central.length / 2, 10);
  end.writeUInt32LE(centralSize, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, ...central, end]);
}
