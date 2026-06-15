#!/usr/bin/env node
/**
 * OneCode Demo GIF Generator v2
 * Pure Node.js — generates a professional-looking demo GIF
 * 800x500, cleaner UI, better typography
 */

const fs = require('fs');
const zlib = require('zlib');
const path = require('path');

// ---- GIF89a Encoder ----
class GIFEncoder {
  constructor(width, height) {
    this.width = width;
    this.height = height;
    this.frames = [];
    this.delay = 80;
  }

  addFrame(rgbaPixels) {
    this.frames.push(rgbaPixels);
  }

  quantize(frame) {
    const palette = new Uint8Array(256 * 3);
    const indexMap = new Uint8Array(this.width * this.height);
    const colorMap = new Map();
    let colorIdx = 0;
    const pixels = this.width * this.height;

    for (let i = 0; i < pixels; i++) {
      const r = frame[i * 4];
      const g = frame[i * 4 + 1];
      const b = frame[i * 4 + 2];
      const key = (r << 16) | (g << 8) | b;
      if (!colorMap.has(key)) {
        if (colorIdx < 255) {
          colorMap.set(key, colorIdx);
          palette[colorIdx * 3] = r;
          palette[colorIdx * 3 + 1] = g;
          palette[colorIdx * 3 + 2] = b;
          colorIdx++;
        } else {
          colorMap.set(key, 255);
        }
      }
      indexMap[i] = colorMap.get(key);
    }
    for (let i = colorIdx; i < 256; i++) {
      palette[i * 3] = 0; palette[i * 3 + 1] = 0; palette[i * 3 + 2] = 0;
    }
    return { palette, indexMap, colorCount: Math.max(2, colorIdx) };
  }

  lzwEncode(indices, minCodeSize) {
    const clearCode = 1 << minCodeSize;
    const eoiCode = clearCode + 1;
    let codeSize = minCodeSize + 1;
    let nextCode = eoiCode + 1;
    const codeLimit = 4096;
    const dict = new Map();
    for (let i = 0; i < clearCode; i++) dict.set(String(i), i);
    const output = [];
    let buffer = 0, bufBits = 0;
    const emit = (code) => {
      buffer |= (code << bufBits);
      bufBits += codeSize;
      while (bufBits >= 8) { output.push(buffer & 0xff); buffer >>= 8; bufBits -= 8; }
    };
    emit(clearCode);
    let current = String(indices[0]);
    for (let i = 1; i < indices.length; i++) {
      const next = String(indices[i]);
      const combined = current + ',' + next;
      if (dict.has(combined)) { current = combined; }
      else {
        emit(dict.get(current));
        if (nextCode < codeLimit) {
          dict.set(combined, nextCode); nextCode++;
          if (nextCode > (1 << codeSize)) codeSize++;
        } else {
          emit(clearCode);
          dict.clear();
          for (let j = 0; j < clearCode; j++) dict.set(String(j), j);
          nextCode = eoiCode + 1; codeSize = minCodeSize + 1;
        }
        current = next;
      }
    }
    emit(dict.get(current)); emit(eoiCode);
    if (bufBits > 0) output.push(buffer & 0xff);
    return Buffer.from(output);
  }

  encode() {
    const bufs = [];
    bufs.push(Buffer.from('GIF89a'));
    const lsd = Buffer.alloc(7);
    lsd.writeUInt16LE(this.width, 0); lsd.writeUInt16LE(this.height, 2);
    lsd[4] = 0x80 | 0x70; lsd[5] = 0; lsd[6] = 0;
    bufs.push(lsd);
    bufs.push(Buffer.from([0x21, 0xff, 0x0b]));
    bufs.push(Buffer.from('NETSCAPE2.0'));
    bufs.push(Buffer.from([0x03, 0x01]));
    const loopBuf = Buffer.alloc(2); loopBuf.writeUInt16LE(0, 0);
    bufs.push(loopBuf); bufs.push(Buffer.from([0x00]));
    const first = this.quantize(this.frames[0]);
    bufs.push(first.palette);
    for (let f = 0; f < this.frames.length; f++) {
      const quant = f === 0 ? first : this.quantize(this.frames[f]);
      const gce = Buffer.from([0x21, 0xf9, 0x04, 0x00, 0x00, Math.round(this.delay / 10), 0x00, 0x00]);
      bufs.push(gce);
      const img = Buffer.alloc(10);
      img[0] = 0x2c; img.writeUInt16LE(0, 1); img.writeUInt16LE(0, 3);
      img.writeUInt16LE(this.width, 5); img.writeUInt16LE(this.height, 7); img[9] = 0x00;
      bufs.push(img);
      bufs.push(Buffer.from([8]));
      const compressed = this.lzwEncode(quant.indexMap, 8);
      let offset = 0;
      while (offset < compressed.length) {
        const cs = Math.min(255, compressed.length - offset);
        bufs.push(Buffer.from([cs]));
        bufs.push(compressed.subarray(offset, offset + cs));
        offset += cs;
      }
      bufs.push(Buffer.from([0x00]));
    }
    bufs.push(Buffer.from([0x3b]));
    return Buffer.concat(bufs);
  }
}

// ---- Drawing ----
const W = 800, H = 500;
const createCanvas = () => ({ data: new Uint8Array(W * H * 4), width: W, height: H });
const fill = (c, r, g, b) => { const d = c.data; for (let i = 0; i < d.length; i += 4) { d[i]=r; d[i+1]=g; d[i+2]=b; d[i+3]=255; } };
const fillRect = (c, x, y, w, h, r, g, b) => {
  const d = c.data, cw = c.width;
  for (let row = y; row < y+h && row < c.height; row++)
    for (let col = x; col < x+w && col < cw; col++) {
      const i = (row*cw+col)*4; d[i]=r; d[i+1]=g; d[i+2]=b; d[i+3]=255;
    }
};

// 3x5 pixel font - compact and clean
const FONT3x5 = {
  ' ':[0,0,0,0,0],'a':[4,5,5,7,5],'b':[6,5,5,5,6],'c':[3,4,4,4,3],
  'd':[7,5,5,5,7],'e':[7,4,6,4,7],'f':[7,4,6,4,4],'g':[3,4,5,5,3],
  'h':[5,5,7,5,5],'i':[7,2,2,2,7],'j':[1,1,1,5,6],'k':[5,5,6,5,5],
  'l':[6,2,2,2,7],'m':[5,7,5,5,5],'n':[5,7,7,5,5],'o':[3,5,5,5,3],
  'p':[7,5,7,4,4],'q':[3,5,5,7,1],'r':[7,5,4,4,4],'s':[3,4,6,2,6],
  't':[7,2,2,2,2],'u':[5,5,5,5,7],'v':[5,5,5,5,2],'w':[5,5,5,7,5],
  'x':[5,5,2,5,5],'y':[5,5,7,1,6],'z':[7,1,2,4,7],
  'A':[3,5,7,5,5],'B':[6,5,6,5,6],'C':[3,4,4,4,3],'D':[6,5,5,5,6],
  'E':[7,4,6,4,7],'F':[7,4,6,4,4],'G':[3,4,5,5,3],'H':[5,5,7,5,5],
  'I':[7,2,2,2,7],'J':[7,1,1,5,3],'K':[5,5,6,5,5],'L':[4,4,4,4,7],
  'M':[5,7,7,5,5],'N':[5,7,7,7,5],'O':[3,5,5,5,3],'P':[7,5,7,4,4],
  'Q':[3,5,5,7,1],'R':[6,5,6,5,5],'S':[3,4,3,2,6],'T':[7,2,2,2,2],
  'U':[5,5,5,5,7],'V':[5,5,5,5,2],'W':[5,5,5,7,5],'X':[5,5,2,5,5],
  'Y':[5,5,2,2,2],'Z':[7,1,2,4,7],
  '0':[3,5,5,5,3],'1':[2,6,2,2,7],'2':[7,1,3,4,7],'3':[7,1,7,1,7],
  '4':[5,5,7,1,1],'5':[7,4,7,1,7],'6':[7,4,7,5,7],'7':[7,1,1,1,1],
  '8':[7,5,7,5,7],'9':[7,5,7,1,7],
  ':':[0,2,0,2,0],'/':[1,1,2,4,4],'-':[0,0,7,0,0],'.' :[0,0,0,2,0],
  '$':[7,5,7,5,7],'_':[0,0,0,0,7],'@':[3,5,7,4,3],'!':[2,2,2,0,2],
  '#':[5,7,5,7,5],'(':[2,4,4,4,2],')':[4,2,2,2,4],'|':[2,2,2,2,2],
  '<':[1,2,4,2,1],'>':[4,2,1,2,4],'?':[3,5,1,0,2],'=' :[0,7,0,7,0],
  '+':[0,2,7,2,0],'*':[5,2,7,2,5],'~':[0,3,5,2,0],'^':[2,5,0,0,0],
};

// Draw text at 3x scale (9x15 effective)
function drawText(c, x, y, text, r, g, b) {
  const d = c.data, cw = c.width;
  let cx = x;
  for (const ch of text) {
    const glyph = FONT3x5[ch] || FONT3x5['?'];
    if (glyph) {
      for (let row = 0; row < 5; row++) {
        for (let col = 0; col < 3; col++) {
          if (glyph[row] & (1 << (2 - col))) {
            for (let dy = 0; dy < 3; dy++) {
              for (let dx = 0; dx < 3; dx++) {
                const px = cx + col*3 + dx;
                const py = y + row*3 + dy;
                if (px >= 0 && px < cw && py >= 0 && py < c.height) {
                  const i = (py*cw+px)*4; d[i]=r; d[i+1]=g; d[i+2]=b; d[i+3]=255;
                }
              }
            }
          }
        }
      }
    }
    cx += 12; // 3x3=9px char + 3px gap
  }
}

// Draw text at 4x scale (12x20 effective) for headings
function drawHeading(c, x, y, text, r, g, b) {
  const d = c.data, cw = c.width;
  let cx = x;
  for (const ch of text) {
    const glyph = FONT3x5[ch] || FONT3x5['?'];
    if (glyph) {
      for (let row = 0; row < 5; row++) {
        for (let col = 0; col < 3; col++) {
          if (glyph[row] & (1 << (2 - col))) {
            for (let dy = 0; dy < 4; dy++) {
              for (let dx = 0; dx < 4; dx++) {
                const px = cx + col*4 + dx;
                const py = y + row*4 + dy;
                if (px >= 0 && px < cw && py >= 0 && py < c.height) {
                  const i = (py*cw+px)*4; d[i]=r; d[i+1]=g; d[i+2]=b; d[i+3]=255;
                }
              }
            }
          }
        }
      }
    }
    cx += 16;
  }
}

// Colors (Dracula-inspired dark theme)
const BG = [22, 22, 35];
const SIDEBAR = [28, 28, 42];
const TERM_BG = [18, 18, 28];
const GREEN = [80, 250, 123];
const CYAN = [139, 233, 253];
const YELLOW = [241, 250, 140];
const WHITE = [210, 210, 220];
const BLUE = [98, 114, 255];
const MAGENTA = [255, 121, 198];
const PURPLE = [189, 147, 249];
const ORANGE = [255, 184, 108];
const RED = [255, 85, 85];
const DIM = [80, 80, 110];
const BORDER = [55, 55, 80];
const ACCENT = [98, 114, 255];
const SEL_BG = [40, 40, 65];

function drawFrame(canvas, phase, step) {
  fill(canvas, ...BG);
  const w = canvas.width, h = canvas.height;

  // === Title Bar ===
  fillRect(canvas, 0, 0, w, 32, ...SIDEBAR);
  fillRect(canvas, 0, 32, w, 1, ...BORDER);
  drawHeading(canvas, 12, 6, 'OneCode', ...ACCENT);
  drawText(canvas, 110, 10, 'AI Native IDE', ...DIM);
  // Window dots
  fillRect(canvas, w-70, 12, 12, 12, ...RED);
  fillRect(canvas, w-52, 12, 12, 12, ...YELLOW);
  fillRect(canvas, w-34, 12, 12, 12, ...GREEN);

  // === Left Sidebar (180px) ===
  fillRect(canvas, 0, 33, 180, h-33, ...SIDEBAR);
  fillRect(canvas, 180, 33, 1, h-33, ...BORDER);

  // Files section
  drawHeading(canvas, 12, 42, 'FILES', ...CYAN);
  fillRect(canvas, 6, 68, 168, 1, ...BORDER);

  const files = ['~/workspace', '  /src', '  /app', '  /components', '  package.json', '  CLAUDE.md', '  README.md'];
  let fy = 78;
  for (const f of files) {
    const isSelected = f === '  README.md';
    if (isSelected) fillRect(canvas, 4, fy-2, 172, 15, ...SEL_BG);
    drawText(canvas, 14, fy, f, ...(isSelected ? WHITE : DIM));
    fy += 16;
  }

  // Agents section
  fillRect(canvas, 6, 210, 168, 1, ...BORDER);
  drawHeading(canvas, 12, 220, 'AGENTS', ...MAGENTA);

  const agents = [
    { name: 'CEO', color: BLUE },
    { name: 'PM', color: GREEN },
    { name: 'Des', color: PURPLE },
    { name: 'Dev', color: YELLOW },
    { name: 'Ops', color: MAGENTA },
    { name: 'QA', color: RED },
    { name: 'Data', color: CYAN },
    { name: 'Fin', color: ORANGE },
  ];
  let ay = 246;
  for (const a of agents) {
    const isActive = (phase === 'agent' || phase === 'response' || phase === 'preview') && a.name === 'Dev';
    if (isActive) fillRect(canvas, 4, ay-2, 172, 15, ...SEL_BG);
    drawText(canvas, 14, ay, isActive ? '> ' : '  ', ...a.color);
    drawText(canvas, 44, ay, '@' + a.name.toLowerCase(), ...(isActive ? a.color : DIM));
    ay += 16;
  }

  // === Main Terminal (top right) ===
  fillRect(canvas, 182, 33, w-182, 280, ...TERM_BG);
  fillRect(canvas, 182, 33, w-182, 22, ...SIDEBAR);
  drawText(canvas, 194, 38, 'Terminal', ...CYAN);
  fillRect(canvas, 182, 55, w-182, 1, ...BORDER);

  // Terminal content
  const termLines = [
    { text: '$ oc remote', color: GREEN, fromStep: 0 },
    { text: '', color: WHITE, fromStep: 0 },
    { text: 'OneCode v0.4.0 starting...', color: CYAN, fromStep: 2 },
    { text: 'Gateway: http://localhost:7681', color: GREEN, fromStep: 4 },
    { text: 'Docker container ready', color: DIM, fromStep: 5 },
    { text: '', color: WHITE, fromStep: 0 },
    { text: '$ @dev help me write a README', color: YELLOW, fromStep: 8 },
    { text: '', color: WHITE, fromStep: 0 },
  ];

  let ty = 66;
  for (const line of termLines) {
    if (line.text && step >= line.fromStep) {
      let visible = line.text;
      // Typing animation for the @dev command
      if (line.text === '$ @dev help me write a README' && step < 20) {
        const total = line.text.length;
        const typingStart = 8;
        const typingEnd = 20;
        const progress = Math.min(1, (step - typingStart) / (typingEnd - typingStart));
        visible = line.text.substring(0, Math.floor(progress * total));
      }
      drawText(canvas, 194, ty, visible, ...line.color);
    }
    ty += 16;
  }

  // Agent response
  const responseLines = [
    { text: '> Dev: I will help you write', color: ORANGE, fromStep: 22 },
    { text: '  a professional README.', color: ORANGE, fromStep: 23 },
    { text: '  Starting with structure...', color: ORANGE, fromStep: 24 },
    { text: '', color: WHITE, fromStep: 0 },
    { text: '  ## Project Overview', color: CYAN, fromStep: 26 },
    { text: '  ## Quick Start', color: CYAN, fromStep: 27 },
    { text: '  ## Features', color: CYAN, fromStep: 28 },
    { text: '  ...writing README.md', color: GREEN, fromStep: 29 },
  ];

  for (const line of responseLines) {
    if (line.text && step >= line.fromStep) {
      drawText(canvas, 194, ty, line.text, ...line.color);
    }
    ty += 16;
  }

  // Cursor
  if (step < 35) {
    const cursorOn = step % 4 < 2;
    if (cursorOn) fillRect(canvas, 194, ty, 8, 12, ...WHITE);
  }

  // === Preview Panel (bottom right) ===
  fillRect(canvas, 182, 314, w-182, h-314, ...SIDEBAR);
  fillRect(canvas, 182, 314, w-182, 22, ...SIDEBAR);
  drawText(canvas, 194, 319, 'Preview', ...PURPLE);
  fillRect(canvas, 182, 336, w-182, 1, ...BORDER);

  // Preview content
  if (step >= 30) {
    const previewProgress = Math.min(1, (step - 30) / 8);
    if (previewProgress > 0) {
      drawHeading(canvas, 200, 346, '# Hello World', ...CYAN);
      drawText(canvas, 208, 370, 'A sample project README', ...DIM);
      fillRect(canvas, 204, 386, 400, 2, ...BORDER);
    }
    if (previewProgress > 0.3) {
      drawHeading(canvas, 208, 396, 'Features', ...YELLOW);
      drawText(canvas, 212, 418, '- Fast and simple', ...WHITE);
    }
    if (previewProgress > 0.6) {
      drawText(canvas, 212, 436, '- Easy to use', ...WHITE);
    }
    if (previewProgress > 0.8) {
      drawText(canvas, 212, 454, '- Open source', ...WHITE);
    }
  }

  // === Bottom Tab Bar ===
  fillRect(canvas, 0, h-28, w, 28, ...SIDEBAR);
  fillRect(canvas, 0, h-28, w, 1, ...BORDER);
  const tabs = ['Terminal', 'Preview', 'Files', 'Agents'];
  let tx = 20;
  for (let i = 0; i < tabs.length; i++) {
    const active = (i === 0) || (i === 1 && step >= 30);
    if (active) {
      fillRect(canvas, tx-4, h-26, 84, 24, ...SEL_BG);
      fillRect(canvas, tx-4, h-28, 84, 2, ...ACCENT);
    }
    drawText(canvas, tx, h-22, tabs[i], ...(active ? CYAN : DIM));
    tx += 100;
  }
}

// ---- Main ----
async function main() {
  const outputDir = path.join(__dirname, '..', 'docs');
  if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });

  const encoder = new GIFEncoder(W, H);
  encoder.delay = 80;

  console.log('Generating OneCode demo GIF v2...');
  console.log(`Size: ${W}x${H}`);

  const totalSteps = 45;

  for (let step = 0; step < totalSteps; step++) {
    const canvas = createCanvas();
    const phase = step < 8 ? 'startup' : step < 22 ? 'agent' : step < 30 ? 'response' : 'preview';
    drawFrame(canvas, phase, step);
    encoder.addFrame(canvas.data);
  }

  // Hold final frame a bit longer (extra 10 frames)
  for (let i = 0; i < 10; i++) {
    const canvas = createCanvas();
    drawFrame(canvas, 'preview', 44);
    encoder.addFrame(canvas.data);
  }

  console.log('Encoding GIF...');
  const gifBuffer = encoder.encode();

  const outPath = path.join(outputDir, 'demo.gif');
  fs.writeFileSync(outPath, gifBuffer);
  console.log(`Done! Saved: ${outPath}`);
  console.log(`Size: ${(gifBuffer.length / 1024).toFixed(0)} KB, Frames: ${encoder.frames.length}`);
}

main().catch(console.error);
