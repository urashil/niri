// Draws the film for the island: the WebGL scene plus the captions / title / terminal inserts painted onto a 2D canvas
// (the site does those as HTML), JPEG-encoded and POSTed to ~/.local/bin/still-film, which hands the frames to the shell.
// The page keeps its own clock: window.setClock(t, playing) sets it, it advances by itself while playing.
import { openingTitleOpacity } from './opening.js';
import { terminalFrame } from './terminal-script.js';
import { Film } from './film.js';
import { chapters, subtitles } from './timeline.js';

const canvas = document.getElementById('scene');
const film = new Film(canvas);
const names = { mitch: 'Mitch', andreas: 'Andreas', officer: 'Officer', agent: 'FBI', robot: 'Assistant' };
const out = document.createElement('canvas');
const ctx = out.getContext('2d', { willReadFrequently: true });
const grab = document.createElement('canvas');
const gctx = grab.getContext('2d', { willReadFrequently: true });
const DESIGN_W = 640;                                   // overlay sizes below are the site's, laid out for a 640 px wide frame
let W = 0, H = 0, S = 1;

const gl = film.renderer.getContext();
let pbos = [], cpu = null, pending = [], slot = 0;
function fit() {
  W = Math.round(innerWidth); H = Math.round(innerHeight); S = W / DESIGN_W;
  out.width = W; out.height = H; grab.width = W; grab.height = H;
  for (const b of pbos) gl.deleteBuffer(b);
  pbos = [0, 1, 2].map(() => { const b = gl.createBuffer(); gl.bindBuffer(gl.PIXEL_PACK_BUFFER, b); gl.bufferData(gl.PIXEL_PACK_BUFFER, W * H * 4, gl.STREAM_READ); return b; });
  gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
  cpu = new Uint8ClampedArray(W * H * 4); pending = [];
}

function wrap(text, width, font) {
  ctx.font = font;
  const lines = [];
  for (const para of String(text).split('\n')) {
    let cur = '';
    for (const word of para.split(' ')) {
      const trial = cur ? cur + ' ' + word : word;
      if (cur && ctx.measureText(trial).width > width) { lines.push(cur); cur = word; } else cur = trial;
    }
    lines.push(cur);
  }
  return lines;
}
function shadowText(text, x, y, font, color, align = 'center') {
  ctx.font = font; ctx.textAlign = align; ctx.textBaseline = 'alphabetic';
  ctx.shadowColor = '#000'; ctx.shadowBlur = 10 * S; ctx.shadowOffsetY = 2 * S; ctx.fillStyle = color;
  ctx.fillText(text, x, y);
  ctx.shadowBlur = 30 * S; ctx.fillText(text, x, y);
  ctx.shadowColor = 'transparent'; ctx.shadowBlur = 0; ctx.shadowOffsetY = 0;
}

function overlays(t, line, shot, insert) {
  const h = H / S;                                      // frame height in design pixels
  ctx.save(); ctx.scale(S, S);
  // vignette
  if (insert) { ctx.fillStyle = '#070c1499'; ctx.fillRect(0, 0, DESIGN_W, h); }
  else {
    const g = ctx.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, '#08090af0'); g.addColorStop(.13, '#08090a33'); g.addColorStop(.26, '#08090a00');
    g.addColorStop(.70, '#08090a00'); g.addColorStop(.87, '#08090a88'); g.addColorStop(1, '#08090a');
    ctx.fillStyle = g; ctx.fillRect(0, 0, DESIGN_W, h);
  }
  // opening title
  const op = openingTitleOpacity(t);
  if (op > 0.01) {
    ctx.globalAlpha = op;
    const size = Math.min(140, Math.max(42, DESIGN_W * 0.09));
    ctx.font = `800 ${size}px Arial, Helvetica, sans-serif`; ctx.letterSpacing = `${-0.065 * size}px`;
    const a = ctx.measureText('still').width, b = ctx.measureText('@').width, c = ctx.measureText('server').width;
    let x = DESIGN_W / 2 - (a + b + c) / 2; const y = h * 0.25 + size * 0.34;
    ctx.textAlign = 'left'; ctx.shadowColor = '#000c'; ctx.shadowBlur = 50;
    ctx.fillStyle = '#f0eee7'; ctx.fillText('still', x, y); x += a;
    ctx.fillStyle = '#d68d77'; ctx.fillText('@', x, y); x += b;
    ctx.fillStyle = '#f0eee7'; ctx.fillText('server', x, y);
    ctx.shadowColor = 'transparent'; ctx.shadowBlur = 0; ctx.letterSpacing = '0px'; ctx.globalAlpha = 1;
  }
  // terminal insert
  if (insert) {
    const s = terminalFrame(t, insert);
    const x = DESIGN_W * 0.07, y = h * 0.27, w = DESIGN_W * 0.86, pad = 20, maxH = h * 0.48;
    ctx.save();
    ctx.beginPath(); ctx.roundRect(x, y, w, maxH, 7); ctx.clip();
    ctx.fillStyle = '#0b141ef5'; ctx.fillRect(x, y, w, maxH);
    ctx.strokeStyle = '#7f9baa33'; ctx.lineWidth = 1; ctx.beginPath(); ctx.roundRect(x + .5, y + .5, w - 1, maxH - 1, 7); ctx.stroke();
    let cy = y + pad + 9;
    ctx.font = '9px monospace'; ctx.fillStyle = '#6e939d'; ctx.textAlign = 'left'; ctx.fillText(insert + '@server', x + pad, cy);
    ctx.textAlign = 'right'; ctx.fillText('SSH: ' + s.ssh, x + w - pad, cy);
    cy += 9; ctx.strokeStyle = '#7294a025'; ctx.beginPath(); ctx.moveTo(x + pad, cy); ctx.lineTo(x + w - pad, cy); ctx.stroke();
    cy += 22; ctx.textAlign = 'left';
    for (const l of wrap('$ ' + s.command, w - 2 * pad, '12px monospace')) { ctx.fillStyle = '#85bdc5'; ctx.fillText(l, x + pad, cy); cy += 19; }
    cy += 3;
    for (const l of wrap(s.lines.join('\n'), w - 2 * pad, '12px monospace')) { ctx.fillStyle = '#a8b9c5'; ctx.fillText(l, x + pad, cy); cy += 20.4; }
    ctx.font = '9px monospace'; ctx.fillStyle = '#d19c8c'; ctx.fillText(s.status, x + pad, cy + 10);
    ctx.restore();
  }
  // caption
  if (line) {
    const fs = Math.min(25, Math.max(17, DESIGN_W * 0.02));
    const lines = wrap(line.text, Math.min(850, DESIGN_W * 0.85), `600 ${fs}px Arial, Helvetica, sans-serif`);
    const lh = fs * 1.3;
    let y = h - 135 - (lines.length - 1) * lh;
    const speaker = shot.speaker ? names[shot.speaker] : '';
    if (speaker) {
      ctx.font = '10px monospace'; ctx.letterSpacing = '1.6px'; ctx.textAlign = 'center'; ctx.fillStyle = '#ff9f87';
      ctx.fillText(speaker.toUpperCase(), DESIGN_W / 2, y - lh + 4 - 10); ctx.letterSpacing = '0px';
    }
    for (const l of lines) { shadowText(l, DESIGN_W / 2, y, `600 ${fs}px Arial, Helvetica, sans-serif`, '#f0f0eb'); y += lh; }
  }
  ctx.restore();
}

let tr = 0, to = 0, tb = 0, td = 0, tf = 0;
window.timing = () => `film.render ${(tf / Math.max(1, count)).toFixed(1)}`;
const _unused = () => `render ${(tr / Math.max(1, count)).toFixed(1)} overlays ${(to / Math.max(1, count)).toFixed(1)} blob ${(tb / Math.max(1, count)).toFixed(1)} | film.render ${(tf / Math.max(1, count)).toFixed(1)} drawImage ${(td / Math.max(1, count)).toFixed(1)}`;
// render now, read the pixels back without stalling (pixel buffer + fence); the frame is finished a couple of ticks later
function render(t, energy) {
  const a = performance.now();
  const line = subtitles.find(s => t >= s.start && t < s.end);
  const shot = film.render(t, energy, false, true, !!line);
  tf += performance.now() - a;
  const pbo = pbos[slot++ % 3];
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  gl.bindBuffer(gl.PIXEL_PACK_BUFFER, pbo);
  gl.readPixels(0, 0, W, H, gl.RGBA, gl.UNSIGNED_BYTE, 0);
  const fence = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0);
  gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
  gl.flush();
  pending.push({ pbo, fence, t, line, shot, insert: canvas.dataset.insert });
}
function finish() {
  while (pending.length) {
    const f = pending[0];
    const st = gl.clientWaitSync(f.fence, 0, 0);
    if (st === gl.TIMEOUT_EXPIRED) return;
    pending.shift();
    gl.deleteSync(f.fence);
    gl.bindBuffer(gl.PIXEL_PACK_BUFFER, f.pbo);
    gl.getBufferSubData(gl.PIXEL_PACK_BUFFER, 0, cpu);
    gl.bindBuffer(gl.PIXEL_PACK_BUFFER, null);
    if (pending.length) continue;                         // a newer frame is ready too: skip this one
    gctx.putImageData(new ImageData(cpu, W, H), 0, 0);
    ctx.save(); ctx.translate(0, H); ctx.scale(1, -1); ctx.drawImage(grab, 0, 0); ctx.restore();   // GL rows come bottom-up
    overlays(f.t, f.line, f.shot, f.insert);
    inflight++; count++;
    out.toBlob(b => fetch('/f', { method: 'POST', body: b }).catch(() => {}).finally(() => { inflight--; }), 'image/jpeg', 0.78);
  }
}

// ---- clock and frame delivery
let anchorT = 0, anchorStamp = performance.now(), playing = false, dirty = true, env = [], energy = 0, inflight = 0, count = 0;
window.setEnv = a => { env = a; };
window.setClock = (t, p) => { anchorT = t; anchorStamp = performance.now(); playing = p; dirty = true; };
window.stats = () => count;
setInterval(() => {
  if (!W) fit();
  finish();
  if ((!playing && !dirty) || pending.length >= 2 || inflight >= 2) return;
  dirty = false;
  const t = playing ? anchorT + (performance.now() - anchorStamp) / 1000 : anchorT;
  const target = env.length ? env[Math.min(env.length - 1, Math.floor(t * 30))] : 0;
  energy += (target - energy) * 0.3;
  render(t, energy);
}, 12);
addEventListener('resize', () => { fit(); dirty = true; });
window.ready = true;
