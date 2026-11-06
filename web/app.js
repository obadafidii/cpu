// KCPU workbench. Talks to the Zig emulator compiled to cpu.wasm (src/wasm.zig).

const OPS = {
  0x10: { m: 'LOAD', words: 3 },
  0x11: { m: 'MOV', words: 3 },
  0x30: { m: 'ADD', words: 3 },
  0x31: { m: 'SUB', words: 3 },
  0x01: { m: 'HLT', words: 1 },
  0x40: { m: 'JMP', words: 2 },
  0x41: { m: 'JZ', words: 2 },
  0x42: { m: 'JNZ', words: 2 },
};
const ROM_SIZE = 0x1000;
const RAM_START = 0x1000;
const RAM_SIZE = 0xE000;
const SPEEDS = [1, 2, 4, 10, 30, Infinity];
const SPEED_LABELS = ['1/s', '2/s', '4/s', '10/s', '30/s', 'Max'];

const EXAMPLES = [
  {
    name: 'Add two numbers',
    src: `; Add two numbers and leave the result in R0.
.text
    LOAD R0, 3        ; R0 <- 3
    LOAD R1, 5        ; R1 <- 5
    ADD  R0, R1       ; R0 <- R0 + R1
    HLT
`,
  },
  {
    name: 'Flags: zero, negative, carry',
    src: `; Watch Z, C and N change after every ADD and SUB.
    LOAD R0, 10
    LOAD R1, 10
    SUB  R0, R1       ; 10 - 10 = 0, sets Z
    LOAD R2, 1
    SUB  R0, R2       ; 0 - 1 wraps to 0xFFFFFFFF, sets N and C
    ADD  R0, R2       ; 0xFFFFFFFF + 1 wraps to 0, sets Z and C
    HLT
`,
  },
  {
    name: 'Swap two registers',
    src: `; Swap R1 and R2 using R3 as a temporary.
    LOAD R1, 0xCAFE
    LOAD R2, 0xBEEF
    MOV  R3, R1       ; R3 <- R1
    MOV  R1, R2       ; R1 <- R2
    MOV  R2, R3       ; R2 <- R3
    HLT
`,
  },
  {
    name: 'Fibonacci, unrolled',
    src: `; Fill R0..R9 with the Fibonacci sequence.
; Each step copies a register, then adds the one before it.
    LOAD R0, 0
    LOAD R1, 1
    MOV  R2, R1
    ADD  R2, R0       ; 1
    MOV  R3, R2
    ADD  R3, R1       ; 2
    MOV  R4, R3
    ADD  R4, R2       ; 3
    MOV  R5, R4
    ADD  R5, R3       ; 5
    MOV  R6, R5
    ADD  R6, R4       ; 8
    MOV  R7, R6
    ADD  R7, R5       ; 13
    MOV  R8, R7
    ADD  R8, R6       ; 21
    MOV  R9, R8
    ADD  R9, R7       ; 34
    HLT
`,
  },
  {
    name: 'Data section',
    src: `; Variables live in RAM, starting at 0x1000.
; LOAD puts a variable's address into a register.
.data
count:  .word 42
bytes:  .byte 1, 2, 3, 4
name:   .asciiz "KCPU"
buffer: .space 8

.text
    LOAD R1, count    ; R1 <- 0x1000
    LOAD R2, name     ; R2 <- 0x1008
    LOAD R3, buffer
    SUB  R3, R1       ; bytes between buffer and count
    HLT
`,
  },
  {
    name: 'Blank program',
    src: `; Instructions: LOAD rd, imm | MOV rd, rs | ADD rd, rs | SUB rd, rs | HLT
.text
    HLT
`,
  },
];

// ------------------------------------------------------------------ helpers
const $ = (id) => document.getElementById(id);
const hex = (n, w = 8) => '0x' + (n >>> 0).toString(16).toUpperCase().padStart(w, '0');
const hexByte = (n) => n.toString(16).toUpperCase().padStart(2, '0');
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* storage unavailable */ } },
};

function fmtImm(n) {
  n >>>= 0;
  return n < 10000 ? String(n) : hex(n, n > 0xFFFF ? 8 : 4);
}

// register value as HTML; in hex the leading zeros are dimmed so the
// significant digits stand out
function fmtReg(n, fmt) {
  if (fmt === 'dec') return String(n >>> 0);
  if (fmt === 'sdec') return String(n | 0);
  const digits = (n >>> 0).toString(16).toUpperCase().padStart(8, '0');
  const lead = digits.match(/^0*/)[0].slice(0, 7);
  return `<span class="lz">${lead}</span>${digits.slice(lead.length)}`;
}

function fmtRegAlt(n, fmt) {
  return fmt === 'hex' ? String(n >>> 0) : hex(n);
}

function instrText(op, a, b) {
  const info = OPS[op];
  if (!info) return `?? ${hex(op, 2)}`;
  switch (op) {
    case 0x10: return `LOAD R${a}, ${fmtImm(b)}`;
    case 0x11: case 0x30: case 0x31: return `${info.m} R${a}, R${b}`;
    case 0x01: return 'HLT';
    default: return info.m;
  }
}

// ------------------------------------------------------------------ wasm
async function loadWasm() {
  const url = new URL('cpu.wasm', import.meta.url);
  let result;
  try {
    result = await WebAssembly.instantiateStreaming(fetch(url));
  } catch {
    const bytes = await (await fetch(url)).arrayBuffer();
    result = await WebAssembly.instantiate(bytes);
  }
  const e = result.instance.exports;
  e.init();
  return e;
}

let wasm;
// views must be re-created after every call that may grow memory
const u8 = (ptr, len) => new Uint8Array(wasm.memory.buffer, ptr, len);
const u32 = (ptr, len) => new Uint32Array(wasm.memory.buffer, ptr, len);
const str = (ptr, len) => new TextDecoder().decode(u8(ptr, len));

function wasmAssemble(src) {
  const bytes = new TextEncoder().encode(src);
  if (bytes.length > wasm.source_capacity()) {
    return { ok: false, line: 0, column: 0, message: 'Source is larger than 64 KiB.' };
  }
  u8(wasm.source_ptr(), bytes.length).set(bytes);
  if (wasm.assemble(bytes.length) !== 0) {
    return { ok: false, line: wasm.error_line(), column: wasm.error_column(), message: str(wasm.error_ptr(), wasm.error_len()) };
  }
  const text = Uint32Array.from(u32(wasm.text_ptr(), wasm.text_words()));
  const mapRaw = u32(wasm.source_map_ptr(), wasm.source_map_count() * 2);
  const sourceMap = [];
  for (let i = 0; i < mapRaw.length; i += 2) sourceMap.push({ address: mapRaw[i], line: mapRaw[i + 1] });
  const symbols = str(wasm.symbols_ptr(), wasm.symbols_bytes())
    .split('\n').filter(Boolean)
    .map((row) => { const [name, kind, address, size] = row.split('\t'); return { name, kind, address: +address, size: +size }; });
  return { ok: true, text, sourceMap, symbols, dataLen: wasm.data_bytes() };
}

function machineState() {
  const flags = wasm.flags();
  return {
    regs: Array.from(u32(wasm.registers_ptr(), 16)),
    pc: wasm.pc(),
    sp: wasm.sp(),
    z: !!(flags & 1), c: !!(flags & 2), n: !!(flags & 4),
    halted: wasm.halted() === 1,
    cycles: wasm.cycles(),
  };
}

function lastInstruction() {
  if (!wasm.has_last()) return null;
  return {
    pc: wasm.last_pc(), op: wasm.last_opcode(), r1: wasm.last_r1(), r2: wasm.last_r2(),
    imm: wasm.last_immediate(), len: wasm.last_length(),
  };
}

// ------------------------------------------------------------------ state
const S = {
  program: null,      // last good assembly
  error: null,        // current assembly error
  addrToLine: new Map(),
  lineToAddr: new Map(),
  breakpoints: new Set(),
  fmt: store.get('kcpu.fmt') || 'hex',
  speed: 2,
  running: false,
  status: 'ready',    // ready | paused | running | halted | fault
  fault: '',
  trace: [],
  prev: null,         // machine state before the last step
  memBase: 0,
  tab: 'listing',
  timers: [],
};

const ta = $('source');

// ------------------------------------------------------------------ assembling
let assembleTimer = 0;
function scheduleAssemble() {
  clearTimeout(assembleTimer);
  $('asm-state').textContent = 'Assembling…';
  assembleTimer = setTimeout(assemble, 250);
}

function assemble() {
  pause();
  const src = ta.value;
  store.set('kcpu.source', src);
  const res = wasmAssemble(src);
  if (!res.ok) {
    S.error = res;
    $('asm-state').textContent = 'Fix the error to run';
  } else {
    S.error = null;
    S.program = res;
    S.addrToLine = new Map(res.sourceMap.map((e) => [e.address, e.line]));
    S.lineToAddr = new Map(res.sourceMap.map((e) => [e.line, e.address]));
    for (const line of [...S.breakpoints]) if (!S.lineToAddr.has(line)) S.breakpoints.delete(line);
    const n = res.sourceMap.length;
    $('asm-state').textContent = `${n} instruction${n === 1 ? '' : 's'}, ${res.text.length * 4} bytes`;
    resetMachine();
    return;
  }
  renderAll();
}

function resetMachine() {
  pause();
  wasm.reset();
  S.trace = [];
  S.prev = null;
  S.fault = '';
  S.status = 'ready';
  S.memBase = 0;
  clearPipeline();
  renderAll();
}

// ------------------------------------------------------------------ execution
function canRun() {
  return !!S.program && !S.error && S.status !== 'halted' && S.status !== 'fault';
}

// runs one instruction; returns the wasm status (0 running, 1 halted, 2 fault)
function stepOnce() {
  const before = machineState();
  const status = wasm.step();
  const after = machineState();
  const last = lastInstruction();

  if (status === 2) {
    S.status = 'fault';
    const textEnd = S.program ? S.program.text.length * 4 : 0;
    S.fault = after.pc >= textEnd
      ? `The CPU ran past the last instruction at ${hex(after.pc, 4)}. End your program with HLT.`
      : str(wasm.error_ptr(), wasm.error_len());
  } else if (after.cycles !== before.cycles && last) {
    S.trace.unshift({ n: after.cycles, last, before, after });
    if (S.trace.length > 500) S.trace.pop();
    S.status = status === 1 ? 'halted' : S.running ? 'running' : 'paused';
  }
  S.prev = before;
  return status;
}

function step() {
  if (!canRun()) return;
  pause();
  const status = stepOnce();
  renderAll();
  animatePipeline(status, true);
}

function run() {
  if (S.running) { pause(); renderAll(); return; }
  if (!canRun()) return;
  S.running = true;
  S.status = 'running';
  let lastTime = performance.now();
  let budget = 1; // first instruction runs right away
  const tick = (now) => {
    if (!S.running) return;
    const speed = SPEEDS[S.speed];
    let steps = speed === Infinity ? 5000 : 0;
    if (speed !== Infinity) {
      budget += ((now - lastTime) / 1000) * speed;
      steps = Math.floor(budget);
      budget -= steps;
    }
    lastTime = now;
    let status = 0;
    let ran = 0;
    for (; ran < steps; ran++) {
      status = stepOnce();
      if (status !== 0) break;
      const line = S.addrToLine.get(wasm.pc());
      if (line && S.breakpoints.has(line)) { status = 'bp'; ran++; break; }
    }
    if (ran > 0) {
      renderAll();
      animatePipeline(status, speed <= 4);
    }
    if (status === 'bp') {
      S.running = false;
      S.status = 'paused';
      renderControls();
      setStatus(`Paused at the breakpoint on line ${S.addrToLine.get(wasm.pc())}.`);
      return;
    }
    if (status !== 0) { S.running = false; renderAll(); return; }
    requestAnimationFrame(tick);
  };
  renderControls();
  requestAnimationFrame(tick);
}

function pause() {
  if (!S.running) return;
  S.running = false;
  if (S.status === 'running') S.status = 'paused';
}

// ------------------------------------------------------------------ pipeline
const stages = [...document.querySelectorAll('.stage')];

function clearPipeline() {
  S.timers.forEach(clearTimeout);
  S.timers = [];
  stages.forEach((s) => s.classList.remove('lit', 'filled', 'halt', 'fault'));
  $('st-pc').textContent = hex(0, 4);
  $('st-fetch').textContent = 'Waiting for the first step';
  for (const id of ['st-decode', 'st-execute', 'st-write']) $(id).textContent = '';
}

function renderPipeline() {
  const t = S.trace[0];
  if (S.status === 'fault') {
    stages.forEach((s) => s.classList.add('filled'));
    stages[1].classList.add('fault');
    $('st-fetch').innerHTML = `<span class="v">fault</span><br><span class="k">${esc(hex(wasm.pc(), 4))}</span>`;
    return;
  }
  if (!t) return;
  const { last, before, after } = t;
  const info = OPS[last.op];
  const words = u32(wasm.memory_ptr() + last.pc, last.len / 4);
  const wordText = Array.from(words, (w) => w.toString(16).toUpperCase().padStart(2, '0')).join(' ');

  $('st-pc').innerHTML = `${hex(last.pc, 4)}<br><span class="k">next</span> <span class="v">${hex(after.pc, 4)}</span>`;
  $('st-fetch').innerHTML = `<span class="k">read ${last.len} bytes</span><br><span class="bytes">${esc(wordText)}</span>`;

  let decode = `<span class="k">opcode</span> <span class="v">${hex(last.op, 2)}</span> ${info.m}`;
  let execute = '';
  let write = '';
  const ra = before.regs[last.r1] >>> 0;
  const rb = before.regs[last.r2] >>> 0;
  const res = after.regs[last.r1] >>> 0;
  const flagText = `<br><span class="k">Z</span>${+after.z} <span class="k">C</span>${+after.c} <span class="k">N</span>${+after.n}`;
  switch (last.op) {
    case 0x10:
      decode += `<br><span class="k">rd</span> R${last.r1} <span class="k">imm</span> ${fmtImm(last.imm)}`;
      execute = `pass the immediate<br><span class="v">${fmtImm(last.imm)}</span>`;
      write = `R${last.r1} <span class="k">←</span> <span class="v">${fmtImm(res)}</span>`;
      break;
    case 0x11:
      decode += `<br><span class="k">rd</span> R${last.r1} <span class="k">rs</span> R${last.r2}`;
      execute = `copy R${last.r2}<br><span class="v">${fmtImm(rb)}</span>`;
      write = `R${last.r1} <span class="k">←</span> <span class="v">${fmtImm(res)}</span>`;
      break;
    case 0x30:
    case 0x31: {
      const sign = last.op === 0x30 ? '+' : '−';
      decode += `<br><span class="k">rd</span> R${last.r1} <span class="k">rs</span> R${last.r2}`;
      execute = `${fmtImm(ra)} ${sign} ${fmtImm(rb)}<br><span class="k">=</span> <span class="v">${fmtImm(res)}</span>`;
      write = `R${last.r1} <span class="k">←</span> <span class="v">${fmtImm(res)}</span>${flagText}`;
      break;
    }
    case 0x01:
      decode += '<br><span class="k">no operands</span>';
      execute = 'stop the clock';
      write = '<span class="v">halted</span>';
      break;
  }
  $('st-decode').innerHTML = decode;
  $('st-execute').innerHTML = execute;
  $('st-write').innerHTML = write;
}

function animatePipeline(status, animate) {
  S.timers.forEach(clearTimeout);
  S.timers = [];
  renderPipeline();
  if (status === 2) return;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  stages.forEach((s) => s.classList.remove('lit', 'halt'));
  if (!animate || reduce) {
    stages.forEach((s) => s.classList.add('filled'));
    if (S.status === 'halted') stages[4].classList.add('halt');
    return;
  }
  // the signal walks through the datapath, one stage at a time
  stages.forEach((s) => s.classList.remove('filled'));
  stages.forEach((s, i) => {
    S.timers.push(setTimeout(() => {
      s.classList.add('lit', 'filled');
      if (i > 0) stages[i - 1].classList.remove('lit');
    }, i * 85));
  });
  S.timers.push(setTimeout(() => {
    stages[4].classList.remove('lit');
    if (S.status === 'halted') stages[4].classList.add('halt');
  }, stages.length * 85 + 220));
}

// ------------------------------------------------------------------ rendering
function setStatus(text, isError = false) {
  const el = $('status');
  el.classList.toggle('is-error', isError);
  el.innerHTML = text;
}

function renderStatus() {
  if (S.error) {
    const where = S.error.line ? `<strong>Line ${S.error.line}</strong>` : '';
    setStatus(`${where}<span>${esc(S.error.message)}</span>`, true);
    return;
  }
  if (S.status === 'fault') { setStatus(`<strong>Stopped</strong><span>${esc(S.fault)}</span>`, true); return; }
  const st = machineState();
  const n = st.cycles;
  const plural = n === 1 ? '' : 's';
  switch (S.status) {
    case 'ready': setStatus('Ready. Press Step to run one instruction, or Run to go to the end.'); break;
    case 'running': setStatus('Running…'); break;
    case 'paused': setStatus(`Paused after ${n} instruction${plural}.`); break;
    case 'halted': setStatus(`Halted after ${n} instruction${plural}. Press Reset to run it again.`); break;
  }
}

function renderControls() {
  const ok = canRun();
  $('btn-step').disabled = !ok || S.running;
  $('btn-run').disabled = !ok && !S.running;
  $('btn-run').textContent = S.running ? 'Pause' : 'Run';
  $('btn-reset').disabled = !S.program || !!S.error;
}

function currentLine() {
  if (!S.program || S.error || S.status === 'halted' || S.status === 'fault') return 0;
  return S.addrToLine.get(wasm.pc()) || 0;
}

const TOKEN_RE = /(;.*$|\/\/.*$)|("(?:[^"\\]|\\.)*"?)|('(?:[^'\\]|\\.)')|(\.[A-Za-z_]\w*)|(\$?\b[Rr](?:1[0-5]|[0-9])\b)|(#?-?\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*)\b)|(\b[A-Za-z_]\w*\s*:)|(\b(?:LOAD|LDI|LD|MOV|ADD|SUB|HLT|HALT|JMP|JZ|JNZ)\b)/gi;
const TOKEN_CLASS = [null, 't-com', 't-str', 't-num', 't-dir', 't-reg', 't-num', 't-lbl', 't-op'];

function highlightLine(line) {
  let out = '';
  let last = 0;
  line.replace(TOKEN_RE, (m, ...groups) => {
    const offset = groups[groups.length - 2];
    out += esc(line.slice(last, offset));
    const g = groups.findIndex((x, i) => i < 8 && x !== undefined);
    out += `<span class="${TOKEN_CLASS[g + 1]}">${esc(m)}</span>`;
    last = offset + m.length;
    return m;
  });
  return out + esc(line.slice(last));
}

function renderEditor() {
  const lines = ta.value.split('\n');
  const cur = currentLine();
  const errLine = S.error ? S.error.line : 0;
  $('hl').innerHTML = lines.map((l, i) => {
    const n = i + 1;
    const cls = ['l'];
    if (n === cur) cls.push('cur');
    let body = highlightLine(l) || ' ';
    if (n === errLine) {
      cls.push('err');
      const col = Math.max(0, (S.error.column || 1) - 1);
      const tok = l.slice(col).match(/^("[^"]*"?|[^\s,]+)/);
      body = tok && col < l.length
        ? `${highlightLine(l.slice(0, col))}<span class="e">${esc(tok[0])}</span>${highlightLine(l.slice(col + tok[0].length))}`
        : `<span class="e">${body}</span>`;
    }
    return `<div class="${cls.join(' ')}">${body}</div>`;
  }).join('');

  const gutter = lines.map((_, i) => {
    const n = i + 1;
    const isInstr = S.lineToAddr.has(n) && !S.error;
    const cls = [S.breakpoints.has(n) ? 'bp' : '', n === cur ? 'cur' : ''].join(' ');
    const label = isInstr ? `Toggle breakpoint on line ${n}` : `Line ${n}`;
    return `<button type="button" class="${cls}" data-line="${n}" ${isInstr ? '' : 'tabindex="-1"'} aria-label="${label}">${n}</button>`;
  }).join('');
  $('gutter').innerHTML = `<div class="gutter-inner" id="gutter-inner">${gutter}</div>`;
  syncScroll();
}

function syncScroll() {
  $('hl').scrollTop = ta.scrollTop;
  $('hl').scrollLeft = ta.scrollLeft;
  const inner = $('gutter-inner');
  if (inner) inner.style.transform = `translateY(${-ta.scrollTop}px)`;
}

function renderRegisters() {
  const st = machineState();
  const t = S.trace[0];
  const fresh = t && t.n === st.cycles ? t.last : null;
  const reads = new Set();
  let wrote = -1;
  if (fresh && S.status !== 'fault') {
    if (fresh.op === 0x10) wrote = fresh.r1;
    if (fresh.op === 0x11) { wrote = fresh.r1; reads.add(fresh.r2); }
    if (fresh.op === 0x30 || fresh.op === 0x31) { wrote = fresh.r1; reads.add(fresh.r1); reads.add(fresh.r2); }
  }
  $('regs').innerHTML = st.regs.map((v, i) => {
    const cls = ['reg'];
    if (v === 0) cls.push('zero');
    if (i === wrote) cls.push('wrote');
    else if (reads.has(i)) cls.push('read');
    const tip = `R${i} = ${hex(v)} = ${v >>> 0} (signed ${v | 0})`;
    return `<div class="${cls.join(' ')}" title="${tip}"><span class="reg-name">R${i}</span><span class="reg-val">${fmtReg(v, S.fmt)}</span><span class="reg-alt">${fmtRegAlt(v, S.fmt)}</span></div>`;
  }).join('');
  $('r-pc').textContent = hex(st.pc);
  $('r-sp').textContent = hex(st.sp);
  const prev = S.prev;
  for (const [id, key] of [['f-z', 'z'], ['f-c', 'c'], ['f-n', 'n']]) {
    const el = $(id);
    el.classList.toggle('on', st[key]);
    el.classList.toggle('changed', !!(fresh && prev && prev[key] !== st[key]));
    el.setAttribute('aria-label', `${el.title.split(':')[0]} flag ${st[key] ? 'set' : 'clear'}`);
  }
  $('cycle-count').textContent = `${st.cycles} instruction${st.cycles === 1 ? '' : 's'} executed`;

  // next instruction preview
  const next = $('next-instr');
  if (!S.program || S.error) next.textContent = 'fix the source to load a program';
  else if (S.status === 'halted') next.textContent = 'nothing, the CPU is halted';
  else if (S.status === 'fault') next.textContent = 'nothing, the CPU stopped on an error';
  else {
    const w = u32(wasm.memory_ptr() + st.pc, 3);
    next.textContent = `${hex(st.pc, 4)}  ${instrText(w[0], w[1], w[2])}`;
  }
}

function regionOf(addr) {
  return addr < RAM_START ? 0 : addr < 0xF000 ? 1 : 2;
}

function renderMemory() {
  const st = machineState();
  const textBytes = S.program ? S.program.text.length * 4 : 0;
  const dataLen = S.program ? S.program.dataLen : 0;
  if ($('follow').checked && S.status !== 'ready' && (st.pc < S.memBase || st.pc >= S.memBase + 256)) {
    S.memBase = Math.floor(st.pc / 256) * 256;
  }
  const base = S.memBase;
  const mem = u8(wasm.memory_ptr() + base, 256);

  // bytes belonging to the next instruction
  let curStart = -1;
  let curEnd = -1;
  const opStarts = new Set(S.program ? S.program.sourceMap.map((e) => e.address) : []);
  if (S.program && !S.error && S.status !== 'halted' && S.status !== 'fault') {
    const op = u32(wasm.memory_ptr() + st.pc, 1)[0];
    const words = OPS[op] ? OPS[op].words : 1;
    curStart = st.pc; curEnd = st.pc + words * 4;
  }

  let html = '';
  for (let row = 0; row < 16; row++) {
    const addr = base + row * 16;
    let bytes = '';
    let ascii = '';
    for (let col = 0; col < 16; col++) {
      const a = addr + col;
      const b = mem[row * 16 + col];
      const cls = ['hx-b'];
      if (a < textBytes) cls.push('code');
      else if (a >= RAM_START && a < RAM_START + dataLen) cls.push('data');
      if (b === 0) cls.push('z');
      if (a >= curStart && a < curEnd) cls.push('cur');
      if (opStarts.has(a)) cls.push('op');
      bytes += `<span class="${cls.join(' ')}" title="${hex(a, 4)} = ${b}">${hexByte(b)}</span>`;
      ascii += b >= 32 && b < 127 ? esc(String.fromCharCode(b)) : '.';
    }
    html += `<div class="hx-row" role="row"><span class="hx-addr">${hex(addr, 4).slice(2)}</span><span class="hx-bytes">${bytes}</span><span class="hx-ascii">${ascii}</span></div>`;
  }
  $('hexdump').innerHTML = html;
  if (document.activeElement !== $('mem-addr')) $('mem-addr').value = hex(base, 4);

  // memory map
  $('mm-text').style.width = `${(textBytes / ROM_SIZE) * 100}%`;
  $('mm-data').style.width = dataLen ? `max(2px, ${(dataLen / RAM_SIZE) * 100}%)` : '0';
  const pcMark = $('mm-pc');
  pcMark.style.display = st.pc < ROM_SIZE ? '' : 'none';
  pcMark.style.left = `${(st.pc / ROM_SIZE) * 100}%`;
  const region = regionOf(base);
  document.querySelectorAll('.mm-seg').forEach((s, i) => s.classList.toggle('is-on', i === region));
}

function renderListing() {
  const pane = $('pane-listing');
  if (!S.program || !S.program.sourceMap.length) {
    pane.innerHTML = '<div class="empty">Write an instruction in the source to see its machine code here.</div>';
    return;
  }
  const srcLines = ta.value.split('\n');
  const pc = wasm.pc();
  const { text, sourceMap } = S.program;
  const done = S.status === 'halted' ? Infinity : pc;
  const rows = sourceMap.map((e, i) => {
    const end = i + 1 < sourceMap.length ? sourceMap[i + 1].address : text.length * 4;
    const words = Array.from(text.slice(e.address / 4, end / 4), (w) => hex(w).slice(2)).join(' ');
    const cls = e.address === pc && S.status !== 'halted' && S.status !== 'fault' ? 'cur' : e.address < done ? 'done' : '';
    const src = (srcLines[e.line - 1] || '').replace(/(;|\/\/).*$/, '').trim();
    return `<tr class="${cls}"><td>${hex(e.address, 4)}</td><td>${words}</td><td class="muted">${e.line}</td><td class="wide">${esc(src)}</td></tr>`;
  }).join('');
  pane.innerHTML = `<table class="grid"><thead><tr><th>Address</th><th>Words</th><th>Line</th><th>Source</th></tr></thead><tbody>${rows}</tbody></table>`;
}

function renderSymbols() {
  const pane = $('pane-symbols');
  const syms = S.program ? S.program.symbols : [];
  if (!syms.length) {
    pane.innerHTML = '<div class="empty">No labels or variables yet. Add a <code>.data</code> section with something like <code>count: .word 42</code>.</div>';
    return;
  }
  const rows = syms.map((s) => `<tr data-addr="${s.address}" title="Show ${esc(s.name)} in memory"><td>${esc(s.name)}</td><td class="muted">${s.kind === 'var' ? 'variable' : 'label'}</td><td>${hex(s.address, 4)}</td><td>${s.kind === 'var' ? `${s.size} B` : ''}</td></tr>`).join('');
  pane.innerHTML = `<table class="grid"><thead><tr><th>Name</th><th>Kind</th><th>Address</th><th>Size</th></tr></thead><tbody>${rows}</tbody></table>`;
}

function renderTrace() {
  const pane = $('pane-trace');
  if (!S.trace.length) {
    pane.innerHTML = '<div class="empty">Every instruction the CPU runs is logged here, newest first.</div>';
    return;
  }
  const rows = S.trace.map(({ n, last, after }) => {
    const text = instrText(last.op, last.r1, last.op === 0x10 ? last.imm : last.r2);
    let effect = '';
    if (last.op === 0x01) effect = 'halted';
    else effect = `R${last.r1} = ${hex(after.regs[last.r1])}`;
    if (last.op === 0x30 || last.op === 0x31) {
      const f = [after.z && 'Z', after.c && 'C', after.n && 'N'].filter(Boolean).join(' ');
      if (f) effect += `, flags ${f}`;
    }
    return `<tr><td class="muted">${n}</td><td>${hex(last.pc, 4)}</td><td>${esc(text)}</td><td class="wide">${effect}</td></tr>`;
  }).join('');
  pane.innerHTML = `<table class="grid"><thead><tr><th>#</th><th>Address</th><th>Instruction</th><th>Result</th></tr></thead><tbody>${rows}</tbody></table>`;
}

function renderTabs() {
  if (S.tab === 'listing') renderListing();
  if (S.tab === 'symbols') renderSymbols();
  if (S.tab === 'trace') renderTrace();
}

function renderAll() {
  document.querySelector('.machine').classList.toggle('is-stale', !!S.error);
  renderEditor();
  renderRegisters();
  renderMemory();
  renderTabs();
  renderControls();
  renderStatus();
  if (!S.trace.length && S.status !== 'fault') clearPipelineText();
}

function clearPipelineText() {
  stages.forEach((s) => s.classList.remove('filled', 'lit', 'halt', 'fault'));
  $('st-pc').textContent = hex(wasm.pc(), 4);
  $('st-fetch').textContent = S.program && !S.error ? 'Waiting for the first step' : 'No program loaded';
  for (const id of ['st-decode', 'st-execute', 'st-write']) $(id).textContent = '';
}

// ------------------------------------------------------------------ events
function bind() {
  const select = $('examples');
  select.innerHTML = EXAMPLES.map((ex, i) => `<option value="${i}">${esc(ex.name)}</option>`).join('');
  select.addEventListener('change', () => {
    ta.value = EXAMPLES[+select.value].src;
    S.breakpoints.clear();
    assemble();
    ta.focus();
  });

  ta.addEventListener('input', () => { renderEditor(); scheduleAssemble(); });
  ta.addEventListener('scroll', syncScroll);
  ta.addEventListener('keydown', (ev) => {
    if (ev.key === 'Tab' && !ev.shiftKey) {
      ev.preventDefault();
      ta.setRangeText('    ', ta.selectionStart, ta.selectionEnd, 'end');
      ta.dispatchEvent(new Event('input'));
    }
  });

  $('gutter').addEventListener('click', (ev) => {
    const btn = ev.target.closest('button[data-line]');
    if (!btn) return;
    const line = +btn.dataset.line;
    if (!S.lineToAddr.has(line)) return;
    if (S.breakpoints.has(line)) S.breakpoints.delete(line); else S.breakpoints.add(line);
    renderEditor();
  });
  $('gutter').addEventListener('wheel', (ev) => { ta.scrollTop += ev.deltaY; }, { passive: true });

  $('btn-step').addEventListener('click', step);
  $('btn-run').addEventListener('click', run);
  $('btn-reset').addEventListener('click', resetMachine);

  const speed = $('speed');
  const savedSpeed = store.get('kcpu.speed');
  if (savedSpeed !== null) speed.value = savedSpeed;
  const applySpeed = () => {
    S.speed = +speed.value;
    $('speed-out').textContent = SPEED_LABELS[S.speed];
    store.set('kcpu.speed', speed.value);
  };
  speed.addEventListener('input', applySpeed);
  applySpeed();

  document.querySelectorAll('.seg-btn').forEach((b) => {
    b.addEventListener('click', () => {
      S.fmt = b.dataset.fmt;
      store.set('kcpu.fmt', S.fmt);
      document.querySelectorAll('.seg-btn').forEach((x) => {
        x.classList.toggle('is-on', x === b);
        x.setAttribute('aria-pressed', String(x === b));
      });
      renderRegisters();
    });
  });
  document.querySelectorAll('.seg-btn').forEach((x) => {
    x.classList.toggle('is-on', x.dataset.fmt === S.fmt);
    x.setAttribute('aria-pressed', String(x.dataset.fmt === S.fmt));
  });

  const goTo = (addr) => {
    S.memBase = Math.max(0, Math.min(0xFF00, Math.floor(addr / 16) * 16));
    $('follow').checked = S.memBase < ROM_SIZE && $('follow').checked;
    renderMemory();
  };
  document.querySelectorAll('.mm-seg').forEach((s) => s.addEventListener('click', () => {
    if (s.dataset.addr !== '0x0000') $('follow').checked = false;
    goTo(parseInt(s.dataset.addr, 16));
  }));
  $('mem-prev').addEventListener('click', () => { $('follow').checked = false; goTo(S.memBase - 256); });
  $('mem-next').addEventListener('click', () => { $('follow').checked = false; goTo(S.memBase + 256); });
  $('mem-addr').addEventListener('change', (ev) => {
    const v = ev.target.value.trim();
    const n = /^0x/i.test(v) ? parseInt(v, 16) : /^[0-9a-f]+$/i.test(v) && /[a-f]/i.test(v) ? parseInt(v, 16) : parseInt(v, 10);
    if (Number.isFinite(n)) { $('follow').checked = false; goTo(n); }
    else ev.target.value = hex(S.memBase, 4);
  });
  $('follow').addEventListener('change', renderMemory);

  document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => {
    S.tab = t.dataset.tab;
    document.querySelectorAll('.tab').forEach((x) => {
      x.classList.toggle('is-on', x === t);
      x.setAttribute('aria-selected', String(x === t));
    });
    for (const name of ['listing', 'symbols', 'trace']) $(`pane-${name}`).hidden = name !== S.tab;
    renderTabs();
  }));
  $('pane-symbols').addEventListener('click', (ev) => {
    const row = ev.target.closest('tr[data-addr]');
    if (row) { $('follow').checked = false; goTo(+row.dataset.addr); }
  });

  document.addEventListener('keydown', (ev) => {
    if (ev.key === 'F10') { ev.preventDefault(); step(); }
    if (ev.key === 'F8') { ev.preventDefault(); run(); }
    if (ev.key === 'Escape' && S.running) { pause(); renderAll(); }
  });
}

// ------------------------------------------------------------------ boot
async function boot() {
  try {
    wasm = await loadWasm();
  } catch (err) {
    document.querySelector('main').innerHTML = `<div class="fatal"><h2>cpu.wasm did not load</h2>
      <p>Build it with <code>zig build web</code>, then serve the output folder over HTTP, for example
      <code>python3 -m http.server -d zig-out/web</code>. Browsers block WebAssembly on <code>file://</code> pages.</p>
      <p class="hint">${esc(String(err))}</p></div>`;
    return;
  }
  bind();
  ta.value = store.get('kcpu.source') || EXAMPLES[0].src;
  const match = EXAMPLES.findIndex((ex) => ex.src === ta.value);
  $('examples').value = match >= 0 ? String(match) : '0';
  assemble();
}

boot();
