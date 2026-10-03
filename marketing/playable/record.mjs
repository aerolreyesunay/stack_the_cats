// Records the self-playing demo as a 1080x1920 video ad, with the game's
// music and sounds: dist/stack-the-cats-video.mp4
//
// Needs Chrome and ffmpeg. Run build.mjs first, then:
//   node marketing/playable/record.mjs
// (Set CHROME or FFMPEG if they aren't in the usual places.)

import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dist = join(here, 'dist');
const audio = join(here, '../../assets/audio');
const CHROME = process.env.CHROME ?? 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const FFMPEG = process.env.FFMPEG ?? 'ffmpeg';
const FPS = 30;
const PORT = 9333;

const work = mkdtempSync(join(tmpdir(), 'stc-video-'));
const frames = join(work, 'frames');
mkdirSync(frames);

const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${join(work, 'profile')}`,
  '--hide-scrollbars', '--mute-audio', '--allow-file-access-from-files', 'about:blank',
], { stdio: 'ignore' });

try {
  const page = await connect();
  await page.send('Page.enable');
  await page.send('Emulation.setDeviceMetricsOverride', {
    width: 360, height: 640, deviceScaleFactor: 3, mobile: true,
  });
  const url = pathToFileURL(join(dist, 'preview.html')).href + '?demo&record';
  await page.send('Page.navigate', { url });
  for (let i = 0; !(await page.eval('typeof window.__advance === "function"')); i++) {
    if (i > 100) throw new Error('The demo did not start (a script error in the page?)');
    await sleep(100);
  }

  let frame = 0;
  let lastScore = 0;
  for (; frame < FPS * 60; frame++) {
    const done = await page.eval(`__advance(${1 / FPS})`);
    const shot = await page.send('Page.captureScreenshot', { format: 'png' });
    writeFileSync(join(frames, `${String(frame).padStart(5, '0')}.png`), Buffer.from(shot.data, 'base64'));
    const s = await page.eval('__state()');
    if (s.score !== lastScore && (s.score % 10 === 0 || s.stability < 0.6)) {
      console.log(`${s.clock.toFixed(1)}s  ${s.score} cats  stability ${Math.round(s.stability * 100)}%  treats ${s.treats}`);
      lastScore = s.score;
    }
    if (done) break;
  }
  const duration = (frame + 1) / FPS;
  const sounds = await page.eval('__sounds()');
  console.log(`${frame + 1} frames, ${duration.toFixed(1)}s, ${sounds.length} sounds`);

  // The soundtrack: the game music under every sound, each at its moment.
  const inputs = ['-framerate', String(FPS), '-i', join(frames, '%05d.png'),
    '-i', join(audio, 'in_game_music.mp3')];
  const filters = [`[1:a]volume=0.35,atrim=0:${duration},afade=t=out:st=${duration - 1.5}:d=1.5[m]`];
  const mix = ['[m]'];
  sounds.forEach((s, i) => {
    inputs.push('-i', join(audio, `${s.name}.mp3`));
    const ms = Math.max(0, Math.round(s.t * 1000));
    filters.push(`[${i + 2}:a]adelay=${ms}|${ms}[s${i}]`);
    mix.push(`[s${i}]`);
  });
  filters.push(`${mix.join('')}amix=inputs=${mix.length}:normalize=0:duration=first[a]`);

  const out = join(dist, 'stack-the-cats-video.mp4');
  const ff = spawnSync(FFMPEG, [
    '-y', '-v', 'error', ...inputs,
    '-filter_complex', filters.join(';'),
    '-map', '0:v', '-map', '[a]',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p',
    '-c:a', 'aac', '-b:a', '160k', '-movflags', '+faststart', '-shortest', out,
  ], { stdio: 'inherit' });
  if (ff.status !== 0) throw new Error('ffmpeg failed');
  console.log(`Wrote ${out}`);
  await page.close();
} finally {
  chrome.kill();
  await sleep(500);
  rmSync(work, { recursive: true, force: true, maxRetries: 5 });
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

/** Connects to the headless Chrome tab over the DevTools protocol. */
async function connect() {
  let target;
  for (let i = 0; i < 100 && !target; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      target = list.find((t) => t.type === 'page');
    } catch { /* not up yet */ }
    if (!target) await sleep(100);
  }
  if (!target) throw new Error('Chrome did not start');
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  let id = 0;
  const waiting = new Map();
  ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    const w = waiting.get(msg.id);
    if (!w) return;
    waiting.delete(msg.id);
    msg.error ? w.reject(new Error(msg.error.message)) : w.resolve(msg.result);
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    waiting.set(++id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });
  return {
    send,
    async eval(expression) {
      const r = await send('Runtime.evaluate', { expression, returnByValue: true });
      if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? 'eval failed');
      return r.result.value;
    },
    close: () => ws.close(),
  };
}
