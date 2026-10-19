// Content script: drawing overlay + vertical Epic-Pen-style toolbar.
//
// UI spec (from the reference image), top to bottom:
//   detached round nib logo  (drag handle; click collapses)
//   [1] eye + cursor      pointer / click-through          (selected = cyan)
//   [2] circle + slash    shapes flyout                    (corner triangle)
//   [3] highlighter       highlighter flyout               (corner triangle)
//   [4] pen               pen flyout       (colour dot)    (corner triangle)
//   [5] eraser            eraser
//   [6] filled dot        size + opacity flyout
//   [7] undo arrow        undo             (flyout: redo)
//   [8] bin               clear all
//   [9] monitor           board + record   (colour dot)    (corner triangle)
//   [10] camera           screenshot flyout
//   [11] clipboard        copy to clipboard
//   colour palette        2x2 quick blocks + large current-colour block
//
// Rendering: `strokeCanvas` holds committed strokes and redraws only on change;
// `liveCanvas` clears every frame for the in-progress stroke, the laser trail
// and the capture selection. Points are stored in PAGE coordinates
// (client + scroll) so annotations stay anchored while scrolling.

(() => {
  if (window.__myAnnotatorLoaded) return;
  window.__myAnnotatorLoaded = true;
  const strokeRenderer = globalThis.MagicPenStrokeRenderer;

  // Quick blocks shown in the 2x2 grid, then the wider palette in flyouts.
  const QUICK = ['#000000', '#ffffff', '#ec008c', '#00aeef'];
  const PALETTE = [
    '#000000', '#ffffff', '#e8352a', '#ff8a00', '#fff200',
    '#17a969', '#00aeef', '#007aff', '#ec008c', '#9930f2'
  ];

  const TOOLS = {
    pointer:     { label: 'Pointer',     shape: null,      noPaint: true },
    pen:         { label: 'Pen',         shape: 'free',    color: '#ec008c', width: 3,  alpha: 1 },
    highlighter: { label: 'Highlighter', shape: 'free',    color: '#fff200', width: 18, alpha: 0.35 },
    eraser:      { label: 'Eraser',      shape: null,      color: '#000000', width: 20, alpha: 1 },
    line:        { label: 'Line',        shape: 'line',    color: '#000000', width: 3,  alpha: 1 },
    rect:        { label: 'Rectangle',   shape: 'rect',    color: '#000000', width: 3,  alpha: 1 },
    ellipse:     { label: 'Ellipse',     shape: 'ellipse', color: '#000000', width: 3,  alpha: 1 },
    text:        { label: 'Text',        shape: 'text',    color: '#000000', width: 5,  alpha: 1 },
    laser:       { label: 'Laser',       shape: null,      color: '#e8352a', width: 8,  alpha: 1 }
  };

  // Bundled images: logo mark, pointer arrow, and the eye (show/hide) icon.
  const IMAGES = {
    logo: chrome.runtime.getURL('src/icons/logo.png'),
    arrow: chrome.runtime.getURL('src/icons/arrow.webp'),
    eye: chrome.runtime.getURL('src/icons/eye.png')
  };

  const ICONS = {
    // [2] square + circle + triangle
    shapes:
      '<svg viewBox="0 0 24 24" fill="none" stroke="#111" stroke-width="1.7" stroke-linejoin="round">' +
      '<circle cx="16.2" cy="7" r="5.2"/>' +
      '<rect x="2" y="5.9" width="9.6" height="9.6" rx="0.6"/>' +
      '<path d="M12 12.1l6.7 9.6H5.3z"/></svg>',
    // [3] yellow highlighter, grey grip and wedge nib
    highlighter:
      '<svg viewBox="0 0 24 24"><g transform="rotate(-45 12 12)" stroke="#111" ' +
      'stroke-width="1.2" stroke-linejoin="round">' +
      '<rect x="6.6" y="2.4" width="10.8" height="12.4" rx="1.6" fill="#ffcc00"/>' +
      '<rect x="9.6" y="5" width="4.8" height="6.6" rx="2.2" fill="#bcc3c9"/>' +
      '<path d="M6.6 14.8h10.8l-2.6 4.2H9.2z" fill="#bcc3c9"/>' +
      '<path d="M9.2 19h5.6l-1.5 2.9h-2.6z" fill="#ffcc00"/></g></svg>',
    // [4] black fountain pen with a gold nib
    pen:
      '<svg viewBox="0 0 24 24"><g transform="rotate(-45 12 12)">' +
      '<rect x="8.4" y="1.8" width="7.2" height="5.2" rx="2.4" fill="#1b1b1b"/>' +
      '<rect x="8.4" y="6.2" width="7.2" height="1.7" fill="#f7941e"/>' +
      '<rect x="8.4" y="7.6" width="7.2" height="7.6" fill="#2c2c2c"/>' +
      '<rect x="10.1" y="3.2" width="1.1" height="11.4" fill="#8f8f8f" opacity=".85"/>' +
      '<rect x="8.1" y="8.4" width="7.8" height="1.9" fill="#f2a03c"/>' +
      '<rect x="9.3" y="15.2" width="5.4" height="1.5" fill="#3a3a3a"/>' +
      '<path d="M12 22.6l-2.5-5.9h5z" fill="#f9a825"/>' +
      '<circle cx="12" cy="18.7" r="0.85" fill="#1b1b1b"/></g></svg>',
    // [5] yellow-and-red eraser with a pale tip
    eraser:
      '<svg viewBox="0 0 24 24"><g transform="rotate(-28 12 12)" stroke="#1a1a1a" ' +
      'stroke-width="1.3" stroke-linejoin="round">' +
      '<rect x="1.6" y="8.4" width="20.8" height="8" rx="2.6" fill="#eceef0"/>' +
      '<path d="M7.2 8.4h12.6a2.6 2.6 0 0 1 2.6 2.6v2.8a2.6 2.6 0 0 1-2.6 2.6H7.2z" fill="#ef4b34"/>' +
      '<path d="M9.4 8.4h10.4a2.6 2.6 0 0 1 2.6 2.6v1.6H9.4z" fill="#ffd21e"/></g></svg>',
    // [6] solid dot — stroke size
    dot: '<circle cx="12" cy="12" r="5.6" fill="currentColor" stroke="none"/>',
    // [7] undo
    undo:
      '<path d="M9.6 5.4L5.2 9.8l4.4 4.4"/>' +
      '<path d="M5.2 9.8h8.4a5.4 5.4 0 0 1 0 10.8H8.4"/>',
    // [8] bin
    bin:
      '<path d="M3.6 6.4h16.8"/><path d="M9 6.4V4.2h6v2.2"/>' +
      '<path d="M5.8 6.4L7 20.8h10l1.2-14.4"/><path d="M10.4 10v7M13.6 10v7"/>',
    // [9] whiteboard on a tripod
    monitor:
      '<svg viewBox="0 0 24 24" fill="none" stroke="#111" stroke-width="1.5" ' +
      'stroke-linecap="round" stroke-linejoin="round">' +
      '<rect x="9.6" y="1.2" width="4.8" height="1.8" rx="0.5" fill="#111"/>' +
      '<rect x="1.4" y="3" width="21.2" height="12.6" rx="0.6"/>' +
      '<rect x="3.4" y="4.8" width="17.2" height="9" rx="0.4"/>' +
      '<path d="M12 15.6L7.6 22.6M12 15.6l4.4 7"/></svg>',
    // [10] camera inside focus brackets, pink-to-blue gradient
    camera:
      '<svg viewBox="0 0 24 24" fill="none" stroke-linecap="round" stroke-linejoin="round">' +
      '<defs><linearGradient id="agShot" x1="0" y1="0" x2="1" y2="1">' +
      '<stop offset="0" stop-color="#ec3fb8"/><stop offset=".55" stop-color="#8b5cf6"/>' +
      '<stop offset="1" stop-color="#5b8def"/></linearGradient></defs>' +
      '<g stroke="url(#agShot)" stroke-width="2.2">' +
      '<path d="M2.2 7.4V4a1.8 1.8 0 0 1 1.8-1.8h3.2"/>' +
      '<path d="M21.8 7.4V4a1.8 1.8 0 0 0-1.8-1.8h-3.2"/>' +
      '<path d="M2.2 16.6V20a1.8 1.8 0 0 0 1.8 1.8h3.2"/>' +
      '<path d="M21.8 16.6V20a1.8 1.8 0 0 1-1.8 1.8h-3.2"/>' +
      '<rect x="5.4" y="8.6" width="13.2" height="8.4" rx="1.8"/>' +
      '<path d="M9.6 8.6l1.1-1.9h2.6l1.1 1.9"/>' +
      '<circle cx="12" cy="12.9" r="2.6"/></g></svg>',
    // [11] clipboard on an orange disc
    clipboard:
      '<svg viewBox="0 0 24 24">' +
      '<circle cx="12" cy="12" r="11.6" fill="#ff6b35"/>' +
      '<rect x="6.4" y="5" width="11.2" height="14.6" rx="1.6" fill="#eef1f4" ' +
      'stroke="#23272b" stroke-width="1.3"/>' +
      '<rect x="9.3" y="3.1" width="5.4" height="3.4" rx="1.1" fill="#dfe4e9" ' +
      'stroke="#23272b" stroke-width="1.3"/>' +
      '<g stroke="#23272b" stroke-width="1.1" stroke-linecap="round">' +
      '<path d="M8.8 10.2h6.4M8.8 12.6h6.4M8.8 15h6.4M8.8 17.4h4"/></g></svg>',
    // flyout-only glyphs
    line:    '<path d="M4 20L20 4"/>',
    rect:    '<rect x="4" y="6.5" width="16" height="11" rx="1"/>',
    ellipse: '<ellipse cx="12" cy="12" rx="8" ry="5.8"/>',
    laser:   '<circle cx="12" cy="12" r="3"/><path d="M12 3.5v3M12 17.5v3M3.5 12h3M17.5 12h3M6 6l2.1 2.1M15.9 15.9L18 18M18 6l-2.1 2.1M8.1 15.9L6 18"/>',
    text:    '<text x="1" y="16.5" font-size="12.5" font-family="Helvetica, Arial, sans-serif" fill="currentColor" stroke="none">ab</text><path d="M15.5 20.5l5.5-5.5 2 2-5.5 5.5h-2z"/>',
    redo:    '<path d="M14.4 5.4l4.4 4.4-4.4 4.4"/><path d="M18.8 9.8h-8.4a5.4 5.4 0 0 0 0 10.8h5.2"/>',
    record:
      '<svg viewBox="0 0 24 24" fill="none">' +
      '<g stroke="#111" stroke-width="2.4">' +
      '<path d="M2.2 7.6V2.2h5.4"/><path d="M21.8 7.6V2.2h-5.4"/>' +
      '<path d="M2.2 16.4v5.4h5.4"/><path d="M21.8 16.4v5.4h-5.4"/></g>' +
      '<circle cx="12" cy="9.2" r="3.5" stroke="#d9463c" stroke-width="2.7"/>' +
      '<text x="12" y="20.2" font-size="6.4" font-weight="700" text-anchor="middle" ' +
      'fill="#111" font-family="Helvetica, Arial, sans-serif">REC</text></svg>',
    shade:
      '<svg viewBox="0 0 24 24" fill="none" stroke="#111" stroke-width="1.5" ' +
      'stroke-linecap="round" stroke-linejoin="round">' +
      '<rect x="9.6" y="1.2" width="4.8" height="1.8" rx="0.5" fill="#111"/>' +
      '<rect x="1.4" y="3" width="21.2" height="12.6" rx="0.6"/>' +
      '<rect x="3.4" y="4.8" width="17.2" height="9" rx="0.4"/>' +
      '<path d="M12 15.6L7.6 22.6M12 15.6l4.4 7"/></svg>',
    save:    '<path d="M4 4h11.5L20 8.5V20H4z"/><path d="M8 4v5.5h7V4"/><path d="M7.5 20v-6h9v6"/>',
    restore: '<path d="M4 10a8 8 0 1 1 1.6 6"/><path d="M3.6 4.6V10h5.4"/>',
    region:  '<path d="M3 8V3h5M16 3h5v5M21 16v5h-5M8 21H3v-5"/>',
    full:    '<rect x="3" y="4.5" width="18" height="15" rx="1.5"/>'
  };

  const LASER_FADE_MS = 700;

  let active = false;
  let collapsed = false;
  let tool = 'pen';
  let strokes = [];
  let undone = [];
  let current = null;
  let activePointerId = null;
  let laserPoints = [];
  let selection = null;
  let rafId = null;
  let recording = false;
  let annotationsVisible = true;
  let shadeOn = false;
  let openFlyout = null;

  // ---------------------------------------------------------------- elements
  const shade = document.createElement('div');
  shade.id = 'annotator-shade';

  const strokeCanvas = document.createElement('canvas');
  const liveCanvas = document.createElement('canvas');
  strokeCanvas.className = 'annotator-canvas';
  liveCanvas.className = 'annotator-canvas';
  const sctx = strokeCanvas.getContext('2d');
  const lctx = liveCanvas.getContext('2d');

  function sizeCanvases() {
    const dpr = window.devicePixelRatio || 1;
    for (const [cv, ctx] of [[strokeCanvas, sctx], [liveCanvas, lctx]]) {
      cv.width = Math.floor(window.innerWidth * dpr);
      cv.height = Math.floor(window.innerHeight * dpr);
      cv.style.width = window.innerWidth + 'px';
      cv.style.height = window.innerHeight + 'px';
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    redraw();
  }

  // -------------------------------------------------------------- draw logic
  function drawStroke(ctx, s) {
    if (!s.points.length) return;
    ctx.globalAlpha = s.alpha;
    ctx.strokeStyle = s.color;
    ctx.fillStyle = s.color;
    ctx.lineWidth = s.width;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    const a = s.points[0];
    const b = s.points[s.points.length - 1];

    if (s.shape === 'text') {
      ctx.font = `${s.size}px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif`;
      ctx.textBaseline = 'top';
      ctx.fillText(s.text, a.x, a.y);
      ctx.globalAlpha = 1;
      return;
    }

    if (s.shape === 'free') {
      strokeRenderer.draw(ctx, s);
      ctx.globalAlpha = 1;
      return;
    }

    ctx.beginPath();
    if (s.shape === 'line') {
      ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y);
    } else if (s.shape === 'rect') {
      ctx.rect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y));
    } else if (s.shape === 'ellipse') {
      ctx.ellipse((a.x + b.x) / 2, (a.y + b.y) / 2,
        Math.abs(b.x - a.x) / 2, Math.abs(b.y - a.y) / 2, 0, 0, Math.PI * 2);
    }
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  function redraw() {
    sctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
    sctx.save();
    sctx.translate(-window.scrollX, -window.scrollY);
    for (const s of strokes) drawStroke(sctx, s);
    sctx.restore();
  }

  function drawLive() {
    lctx.clearRect(0, 0, window.innerWidth, window.innerHeight);

    if (current) {
      lctx.save();
      lctx.translate(-window.scrollX, -window.scrollY);
      drawStroke(lctx, current);
      lctx.restore();
    }

    if (selection) {
      lctx.save();
      lctx.fillStyle = 'rgba(0,0,0,.35)';
      lctx.fillRect(0, 0, window.innerWidth, window.innerHeight);
      lctx.clearRect(selection.x, selection.y, selection.w, selection.h);
      lctx.strokeStyle = '#00aeef';
      lctx.lineWidth = 1.5;
      lctx.setLineDash([5, 4]);
      lctx.strokeRect(selection.x, selection.y, selection.w, selection.h);
      lctx.restore();
    }

    if (laserPoints.length > 1) {
      const now = performance.now();
      const cfg = TOOLS.laser;
      lctx.save();
      lctx.lineCap = 'round';
      lctx.shadowColor = cfg.color;
      lctx.shadowBlur = 12;
      for (let i = 1; i < laserPoints.length; i++) {
        const p = laserPoints[i];
        const life = 1 - (now - p.t) / LASER_FADE_MS;
        if (life <= 0) continue;
        lctx.globalAlpha = life;
        lctx.strokeStyle = cfg.color;
        lctx.lineWidth = cfg.width * life;
        lctx.beginPath();
        lctx.moveTo(laserPoints[i - 1].x, laserPoints[i - 1].y);
        lctx.lineTo(p.x, p.y);
        lctx.stroke();
      }
      lctx.restore();
      lctx.globalAlpha = 1;
    }
  }

  function tick() {
    laserPoints = laserPoints.filter((p) => p.t > performance.now() - LASER_FADE_MS);
    drawLive();
    rafId = (current || laserPoints.length || selection) ? requestAnimationFrame(tick) : null;
  }
  function pump() { if (rafId === null) rafId = requestAnimationFrame(tick); }

  function eraseAt(px, py) {
    const r = TOOLS.eraser.width;
    const n = strokes.length;
    strokes = strokes.filter((s) => !s.points.some((p) => Math.hypot(p.x - px, p.y - py) < r));
    if (strokes.length !== n) redraw();
  }

  // ------------------------------------------------------------- text tool
  function startText(clientX, clientY) {
    const cfg = TOOLS.text;
    const size = cfg.width * 4;
    const input = document.createElement('input');
    input.className = 'annotator-text-input';
    input.style.left = (clientX + window.scrollX) + 'px';
    input.style.top = (clientY + window.scrollY) + 'px';
    input.style.color = cfg.color;
    input.style.fontSize = size + 'px';
    document.body.appendChild(input);
    input.focus();

    let done = false;
    const commit = () => {
      if (done) return;
      done = true;
      const value = input.value.trim();
      input.remove();
      if (!value) return;
      strokes.push({
        shape: 'text', text: value, size,
        color: cfg.color, alpha: cfg.alpha, width: cfg.width,
        points: [{ x: clientX + window.scrollX, y: clientY + window.scrollY }]
      });
      undone = [];
      redraw();
    };
    input.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Enter') { e.preventDefault(); commit(); }
      if (e.key === 'Escape') { done = true; input.remove(); }
    });
    input.addEventListener('blur', commit);
  }

  // ---------------------------------------------------------------- pointers
  const pageXY = (e) => ({ x: e.clientX + window.scrollX, y: e.clientY + window.scrollY });
  const appendPointerSamples = (event) => strokeRenderer.appendSamples(current, event,
    { x: window.scrollX, y: window.scrollY });

  liveCanvas.addEventListener('pointerdown', (e) => {
    if (!active || tool === 'pointer' || e.button !== 0 || e.isPrimary === false || activePointerId !== null) return;
    e.preventDefault();
    closeFlyout();
    activePointerId = e.pointerId;
    liveCanvas.setPointerCapture(e.pointerId);

    if (tool === 'shot') {
      selection = { x: e.clientX, y: e.clientY, w: 0, h: 0, ox: e.clientX, oy: e.clientY };
      pump(); return;
    }
    if (tool === 'text') { startText(e.clientX, e.clientY); return; }
    if (tool === 'laser') return;
    if (tool === 'eraser') {
      const p = pageXY(e); eraseAt(p.x, p.y);
      current = { eraser: true, points: [] };
      return;
    }

    const cfg = TOOLS[tool];
    current = { shape: cfg.shape, color: cfg.color, width: cfg.width, alpha: cfg.alpha,
      points: [], pressures: [] };
    appendPointerSamples(e);
    pump();
  });

  liveCanvas.addEventListener('pointermove', (e) => {
    if (!active || tool === 'pointer') return;

    if (tool === 'laser') {
      laserPoints.push({ x: e.clientX, y: e.clientY, t: performance.now() });
      pump(); return;
    }
    if (e.pointerId !== activePointerId) return;

    if (tool === 'shot') {
      if (!selection) return;
      selection.x = Math.min(selection.ox, e.clientX);
      selection.y = Math.min(selection.oy, e.clientY);
      selection.w = Math.abs(e.clientX - selection.ox);
      selection.h = Math.abs(e.clientY - selection.oy);
      pump(); return;
    }
    if (!current) return;
    if (current.eraser) { const p = pageXY(e); eraseAt(p.x, p.y); return; }
    appendPointerSamples(e);
    pump();
  });

  async function endStroke(event) {
    if (event.pointerId !== activePointerId) return;
    activePointerId = null;
    if (tool === 'shot' && selection) {
      const region = (selection.w > 4 && selection.h > 4) ? { ...selection } : null;
      selection = null; drawLive();
      await captureScreenshot(region);
      return;
    }
    if (current && !current.eraser && current.points.length) {
      if (event.type === 'pointerup') appendPointerSamples(event);
      strokes.push(current); undone = []; redraw();
    }
    current = null; drawLive();
  }
  liveCanvas.addEventListener('pointerup', endStroke);
  liveCanvas.addEventListener('pointercancel', endStroke);
  liveCanvas.addEventListener('lostpointercapture', endStroke);

  window.addEventListener('resize', sizeCanvases);
  window.addEventListener('scroll', redraw, { passive: true });

  // ------------------------------------------------------------- screenshot
  async function grabVisible() {
    host.style.visibility = 'hidden';
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
    const res = await chrome.runtime.sendMessage({ type: 'CAPTURE_TAB' });
    host.style.visibility = '';
    if (!res || !res.ok) { setNote((res && res.error) || 'Capture failed'); return null; }
    const img = new Image();
    img.src = res.dataUrl;
    await img.decode();
    return img;
  }

  function cropToCanvas(img, region) {
    // captureVisibleTab returns device pixels; our coords are CSS pixels.
    const scale = img.width / window.innerWidth;
    const c = document.createElement('canvas');
    const ctx = c.getContext('2d');
    if (region) {
      c.width = Math.round(region.w * scale);
      c.height = Math.round(region.h * scale);
      ctx.drawImage(img, region.x * scale, region.y * scale,
        region.w * scale, region.h * scale, 0, 0, c.width, c.height);
    } else {
      c.width = img.width; c.height = img.height;
      ctx.drawImage(img, 0, 0);
    }
    return c;
  }

  async function captureScreenshot(region) {
    setNote('Capturing…');
    const img = await grabVisible();
    if (!img) return;
    const out = await chrome.runtime.sendMessage({
      type: 'SAVE_IMAGE', dataUrl: cropToCanvas(img, region).toDataURL('image/png')
    });
    setNote(out && out.ok ? 'Screenshot saved' : 'Save failed');
  }

  async function copyScreenshot() {
    setNote('Copying…');
    const img = await grabVisible();
    if (!img) return;
    try {
      const blob = await new Promise((r) => cropToCanvas(img, null).toBlob(r, 'image/png'));
      await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]);
      setNote('Copied to clipboard');
    } catch (err) {
      setNote('Copy failed: ' + (err.message || err));
    }
  }

  // ------------------------------------------------------------ persistence
  const pageKey = () => 'strokes:' + location.origin + location.pathname;

  function saveAnnotations() {
    chrome.storage.local.set({ [pageKey()]: strokes }, () => {
      setNote(`Saved ${strokes.length} annotation${strokes.length === 1 ? '' : 's'}`);
    });
  }
  function restoreAnnotations(onlyIfEmpty = false) {
    chrome.storage.local.get(pageKey(), (data) => {
      const saved = data && data[pageKey()];
      if (!saved || !saved.length) return;
      if (onlyIfEmpty && strokes.length) return;   // never clobber unsaved work
      strokes = saved; undone = []; redraw(); setNote('Restored');
    });
  }

  function doUndo() { if (strokes.length) { undone.push(strokes.pop()); redraw(); } }
  function doRedo() { if (undone.length) { strokes.push(undone.pop()); redraw(); } }

  // ---------------------------------------------------------------- toolbar
  const host = document.createElement('div');
  host.id = 'annotator-toolbar-host';
  const shadow = host.attachShadow({ mode: 'open' });

  // Full-colour icons are complete <svg> documents; monochrome ones are inner
  // markup that inherits the cell's text colour.
  const svg = (name) => {
    const art = ICONS[name] || '';
    return art.startsWith('<svg') ? art
      : `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"
           stroke-linecap="round" stroke-linejoin="round">${art}</svg>`;
  };

  // id, icon, tooltip, has-flyout, colour-dot source tool
  // an icon of the form 'img:name' renders IMAGES[name] as an <img> instead of an svg
  const CELLS = [
    ['pointer',   'img:arrow',   'Pointer — click through to the page', false, null],
    ['eye',       'img:eye',     'Show / hide all annotations',         false, null],
    ['highlighter','highlighter','Highlighter',                         true,  'highlighter'],
    ['shapes',    'shapes',      'Shapes, text and laser',              true,  null],
    ['eraser',    'eraser',      'Eraser',                              false, null],
    ['pen',       'pen',         'Pen',                                 true,  'pen'],
    ['size',      'dot',         'Stroke size and opacity',             true,  null],
    ['undo',      'undo',        'Undo — corner for redo',              true,  null],
    ['clear',     'bin',         'Clear all',                           false, null],
    ['board',     'monitor',     'Board, record, save',                 true,  'board'],
    ['camera',    'camera',      'Screenshot',                          true,  null],
    ['copy',      'clipboard',   'Copy screenshot to clipboard',        false, null]
  ];

  shadow.innerHTML = `
    <style>
      :host { all: initial; }
      * { box-sizing: border-box; }
      .outer {
        position: relative; display: flex; flex-direction: column; align-items: center;
        font: 12px/1.4 -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        color: #17171a;
      }
      .logo {
        all: unset; width: 38px; height: 38px; cursor: grab; color: #17171a;
        display: flex; align-items: center; justify-content: center;
        filter: drop-shadow(0 2px 6px rgba(0,0,0,.35));
        -webkit-user-select: none; user-select: none;
      }
      .logo svg { width: 38px; height: 38px; }
      .logo img {
        width: 38px; height: 38px; object-fit: contain; border-radius: 50%;
        background: #101427; -webkit-user-drag: none; user-drag: none;
        -webkit-user-select: none; user-select: none; pointer-events: none;
      }
      .strip {
        margin-top: 3px; width: 44px; background: #fff;
        border: 1px solid #d9d9de; border-radius: 8px; overflow: hidden;
        box-shadow: 0 4px 16px rgba(0,0,0,.22);
      }
      .cell {
        position: relative; height: 37px; display: flex;
        align-items: center; justify-content: center; cursor: pointer;
      }
      .cell + .cell { border-top: 1px solid #f0f0f3; }
      .cell svg { width: 26px; height: 26px; }
      .cell-img { width: 24px; height: 24px; object-fit: contain; }
      .cell:hover { background: #f4f4f7; }
      .cell[data-on='true'] { background: #29abe2; }
      .cell[data-on='true']:hover { background: #21a0d6; }
      /* corner triangle marks a flyout, as in the reference */
      .cell.fly::after {
        content: ''; position: absolute; right: 1px; bottom: 1px;
        border-left: 6px solid transparent; border-bottom: 6px solid #17171a;
      }
      /* small colour badge on pen / board */
      .badge {
        position: absolute; right: 3px; top: 3px;
        width: 7px; height: 7px; border-radius: 50%;
        box-shadow: 0 0 0 1px rgba(0,0,0,.25);
      }

      /* colour palette: 2x2 quick blocks, then the large current colour */
      .quad { display: grid; grid-template-columns: 1fr 1fr; border-top: 1px solid #f0f0f3; }
      .quad div { height: 17px; cursor: pointer; }
      .cur { height: 26px; cursor: pointer; border-top: 1px solid #f0f0f3; }

      .flyout {
        position: absolute; left: 50px; background: #fff;
        border: 1px solid #d9d9de; border-radius: 8px; padding: 7px;
        box-shadow: 0 4px 16px rgba(0,0,0,.22); width: 166px;
      }
      /* icon-only panels (shapes, undo, board, camera) - only as wide as the icons */
      .flyout.flyout--compact { width: auto; }
      /* flips to the toolbar's left side when there's no room to the right,
         e.g. the toolbar has been dragged to the right edge of the screen */
      .flyout.flyout--left { left: auto; right: 50px; }
      .flyout[hidden] { display: none; }
      .fgrid { display: flex; flex-direction: column; align-items: stretch; gap: 4px; }
      .fbtn {
        all: unset; box-sizing: border-box; height: 32px; border-radius: 5px; cursor: pointer; width: 100%;
        display: flex; align-items: center; justify-content: center; gap: 8px; padding: 0 10px; color: #17171a;
      }
      .fbtn svg { width: 20px; height: 20px; }
      .fbtn:hover { background: #f0f0f3; }
      .fbtn[data-on='true'] { background: #29abe2; }
      /* colour swatches stack vertically, one per row */
      .fsw { display: flex; flex-direction: column; align-items: flex-start; gap: 3px; margin: 4px 0; }
      .fsw div { width: 22px; height: 22px; border-radius: 4px; cursor: pointer; box-shadow: inset 0 0 0 1px rgba(0,0,0,.18); }
      .fsw div[data-on='true'] { box-shadow: 0 0 0 2px #29abe2; }
      .frow { height: 26px; display: flex; align-items: center; gap: 5px; }
      .frow .lbl { width: 40px; font-size: 10px; opacity: .65; }
      .frow input { width: 60px; flex: none; accent-color: #29abe2; }
      .frow .val { width: 28px; font-size: 11px; opacity: .6; text-align: right; }

      .status {
        margin-top: 4px; background: #17171a; color: #f4f4f6; border-radius: 5px;
        padding: 3px 7px; font-size: 10px; max-width: 180px; text-align: center;
        box-shadow: 0 3px 12px rgba(0,0,0,.3);
      }
      .status:empty { display: none; }
      [hidden] { display: none !important; }
    </style>

    <div class="outer">
      <button class="logo" id="logo" title="Drag to move — click to collapse"><img src="${IMAGES.logo}" alt="" draggable="false"></button>
      <div class="strip" id="strip">
        <div id="cells"></div>
        <div class="quad" id="quad"></div>
        <div class="cur" id="cur" title="Current colour — click for the full palette"></div>
      </div>
      <div class="flyout" id="flyout" hidden></div>
      <div class="status" id="note"></div>
    </div>
  `;

  const $ = (s) => shadow.querySelector(s);
  const setNote = (t) => { $('#note').textContent = t; };

  // ------------------------------------------------------------- build cells
  for (const [id, icon, title, hasFly, badgeFor] of CELLS) {
    const c = document.createElement('div');
    c.className = 'cell' + (hasFly ? ' fly' : '');
    c.dataset.cell = id;
    c.title = title;
    const art = icon.startsWith('img:')
      ? `<img class="cell-img" src="${IMAGES[icon.slice(4)]}" alt="">`
      : svg(icon);
    c.innerHTML = art + (badgeFor ? '<span class="badge" data-badge="' + badgeFor + '"></span>' : '');
    c.addEventListener('click', (e) => { e.stopPropagation(); onCell(id, c, e); });
    $('#cells').appendChild(c);
  }

  for (const col of QUICK) {
    const d = document.createElement('div');
    d.style.background = col;
    d.title = col;
    d.addEventListener('click', () => setColor(col));
    $('#quad').appendChild(d);
  }
  $('#cur').addEventListener('click', () => toggleFlyout('palette', $('#cur')));

  // The tool a colour click should apply to — the last paint tool used.
  let lastPaintTool = 'pen';
  function setColor(col) {
    const cfg = TOOLS[lastPaintTool];
    if (cfg && !cfg.noPaint) { cfg.color = col; save(); }
    syncUI();
  }
  function currentColor() {
    const cfg = TOOLS[lastPaintTool];
    return (cfg && cfg.color) || '#000000';
  }

  function selectTool(name) {
    tool = name;
    if (TOOLS[name] && !TOOLS[name].noPaint && name !== 'eraser') lastPaintTool = name;
    selection = null;
    syncUI();
  }

  // ----------------------------------------------------------- cell actions
  // The corner triangle opens the submenu; the rest of the cell runs the
  // primary action. Cells with no primary action always open their flyout.
  function inCorner(el, e) {
    const r = el.getBoundingClientRect();
    return e.clientX > r.right - 12 && e.clientY > r.bottom - 12;
  }

  function onCell(id, el, e) {
    const corner = inCorner(el, e);
    switch (id) {
      case 'pointer':     closeFlyout(); selectTool('pointer'); break;
      case 'eye':
        closeFlyout();
        annotationsVisible = !annotationsVisible;
        setNote(annotationsVisible ? 'Annotations shown' : 'Annotations hidden');
        syncUI();
        break;
      case 'eraser':      closeFlyout(); selectTool('eraser'); break;
      case 'clear':       closeFlyout(); strokes = []; undone = []; redraw(); setNote('Cleared'); break;
      case 'copy':        closeFlyout(); copyScreenshot(); break;

      case 'highlighter':
        if (corner) toggleFlyout('highlighter', el);
        else { closeFlyout(); selectTool('highlighter'); }
        break;
      case 'pen':
        if (corner) toggleFlyout('pen', el);
        else { closeFlyout(); selectTool('pen'); }
        break;
      case 'undo':
        if (corner) toggleFlyout('undo', el);
        else { closeFlyout(); doUndo(); }
        break;
      case 'camera':
        if (corner) toggleFlyout('camera', el);
        else { closeFlyout(); selectTool('shot'); setNote('Drag a region on the page'); }
        break;

      // no single primary action — these always open their panel
      case 'shapes':      toggleFlyout('shapes', el); break;
      case 'size':        toggleFlyout('size', el); break;
      case 'board':       toggleFlyout('board', el); break;
    }
  }

  // -------------------------------------------------------------- flyouts
  function closeFlyout() { openFlyout = null; $('#flyout').hidden = true; }

  function toggleFlyout(name, anchorEl) {
    if (openFlyout === name) return closeFlyout();
    openFlyout = name;
    const fly = $('#flyout');
    fly.hidden = false;
    fly.innerHTML = flyoutHTML(name);
    wireFlyout(name);
    fly.classList.toggle('flyout--compact', COMPACT_FLYOUTS.includes(name));
    // align the panel with the cell that opened it
    const stripRect = $('#strip').getBoundingClientRect();
    const top = anchorEl.getBoundingClientRect().top - stripRect.top;
    fly.style.top = ($('#strip').offsetTop + top) + 'px';
    // flip to the toolbar's left side when opening to the right would run
    // off the edge of the screen (e.g. toolbar dragged to the right side).
    // Measured from the real rendered width, since compact panels are much
    // narrower than the swatch/slider ones.
    fly.classList.remove('flyout--left');
    const opensOffscreen = fly.getBoundingClientRect().right > window.innerWidth;
    fly.classList.toggle('flyout--left', opensOffscreen);
    syncUI();
  }

  const swatchRow = (sel) => '<div class="fsw">' + PALETTE.map(
    (c) => `<div data-col="${c}" data-on="${String(c === sel)}" style="background:${c}"></div>`
  ).join('') + '</div>';

  // panels whose flyout is a plain icon list - sized to the icons, not the
  // wider swatch/slider panels (pen, highlighter, size, palette)
  const COMPACT_FLYOUTS = ['shapes', 'undo', 'board', 'camera', 'palette'];

  function flyoutHTML(name) {
    if (name === 'shapes') {
      return '<div class="fgrid">' +
        ['line', 'rect', 'ellipse', 'text', 'laser'].map(
          (t) => `<button class="fbtn" data-tool="${t}" title="${TOOLS[t].label}">${svg(t)}</button>`
        ).join('') + '</div>';
    }
    if (name === 'pen' || name === 'highlighter') {
      const cfg = TOOLS[name];
      return swatchRow(cfg.color) +
        `<div class="frow"><span class="lbl">Weight</span>
           <input type="range" id="fw" min="1" max="40" step="1" value="${cfg.width}">
           <span class="val" id="fwv">${cfg.width}</span></div>
         <div class="frow"><span class="lbl">Opacity</span>
           <input type="range" id="fa" min="5" max="100" step="5" value="${Math.round(cfg.alpha * 100)}">
           <span class="val" id="fav">${Math.round(cfg.alpha * 100)}%</span></div>`;
    }
    if (name === 'size') {
      const cfg = TOOLS[lastPaintTool];
      return `<div class="frow"><span class="lbl">Weight</span>
           <input type="range" id="fw" min="1" max="40" step="1" value="${cfg.width}">
           <span class="val" id="fwv">${cfg.width}</span></div>
         <div class="frow"><span class="lbl">Opacity</span>
           <input type="range" id="fa" min="5" max="100" step="5" value="${Math.round(cfg.alpha * 100)}">
           <span class="val" id="fav">${Math.round(cfg.alpha * 100)}%</span></div>`;
    }
    if (name === 'undo') {
      return '<div class="fgrid">' +
        `<button class="fbtn" id="f-undo" title="Undo">${svg('undo')}</button>` +
        `<button class="fbtn" id="f-redo" title="Redo">${svg('redo')}</button></div>`;
    }
    if (name === 'board') {
      return '<div class="fgrid">' +
        `<button class="fbtn" id="f-shade" data-on="${shadeOn}" title="Screen shade">${svg('shade')}</button>` +
        `<button class="fbtn" id="f-rec" data-on="${recording}" title="${recording ? 'Stop recording' : 'Record screen'}">${svg('record')}</button>` +
        `<button class="fbtn" id="f-save" title="Save annotations for this page">${svg('save')}</button>` +
        `<button class="fbtn" id="f-restore" title="Restore saved annotations">${svg('restore')}</button></div>`;
    }
    if (name === 'camera') {
      return '<div class="fgrid">' +
        `<button class="fbtn" id="f-region" title="Drag a region">${svg('region')}</button>` +
        `<button class="fbtn" id="f-full" title="Whole visible page">${svg('full')}</button>` +
        `<button class="fbtn" id="f-copy" title="Copy to clipboard">${svg('clipboard')}</button></div>`;
    }
    if (name === 'palette') {
      return swatchRow(currentColor());
    }
    return '';
  }

  function wireFlyout(name) {
    const fly = $('#flyout');

    fly.querySelectorAll('[data-col]').forEach((d) => {
      d.addEventListener('click', () => {
        setColor(d.dataset.col);
        // Re-render in place so the panel stays open and the tick moves.
        fly.innerHTML = flyoutHTML(name);
        wireFlyout(name);
        syncUI();
      });
    });
    fly.querySelectorAll('[data-tool]').forEach((b) => {
      b.addEventListener('click', () => { selectTool(b.dataset.tool); closeFlyout(); });
    });

    const fw = fly.querySelector('#fw');
    const fa = fly.querySelector('#fa');
    const target = (name === 'pen' || name === 'highlighter') ? name : lastPaintTool;
    if (fw) fw.addEventListener('input', (e) => {
      TOOLS[target].width = Number(e.target.value);
      fly.querySelector('#fwv').textContent = e.target.value;
      save(); syncUI();
    });
    if (fa) fa.addEventListener('input', (e) => {
      TOOLS[target].alpha = Number(e.target.value) / 100;
      fly.querySelector('#fav').textContent = e.target.value + '%';
      save(); syncUI();
    });

    const on = (sel, fn) => { const el = fly.querySelector(sel); if (el) el.addEventListener('click', fn); };
    on('#f-undo', doUndo);
    on('#f-redo', doRedo);
    on('#f-shade', () => { shadeOn = !shadeOn; setNote(shadeOn ? 'Screen shade on' : 'Screen shade off'); toggleFlyout('board', shadow.querySelector('[data-cell=board]')); });
    on('#f-save', () => { saveAnnotations(); closeFlyout(); });
    on('#f-restore', () => { restoreAnnotations(); closeFlyout(); });
    on('#f-rec', async () => {
      closeFlyout();
      if (recording) { setNote('Saving…'); await chrome.runtime.sendMessage({ type: 'STOP_RECORDING' }); return; }
      setNote('Choose a screen…');
      const res = await chrome.runtime.sendMessage({ type: 'START_RECORDING' });
      if (res && res.ok) { recording = true; setNote('Recording…'); } else setNote((res && res.error) || 'Could not start');
      syncUI();
    });
    on('#f-region', () => { selectTool('shot'); closeFlyout(); setNote('Drag a region on the page'); });
    on('#f-full', () => { closeFlyout(); captureScreenshot(null); });
    on('#f-copy', () => { closeFlyout(); copyScreenshot(); });
  }

  // ------------------------------------------------------------------ sync
  function syncUI() {
    const onCellId = {
      pointer: 'pointer', pen: 'pen', highlighter: 'highlighter', eraser: 'eraser'
    }[tool];
    shadow.querySelectorAll('.cell').forEach((c) => {
      let on = c.dataset.cell === onCellId;
      if (c.dataset.cell === 'shapes') on = ['line', 'rect', 'ellipse', 'text', 'laser'].includes(tool);
      if (c.dataset.cell === 'camera') on = tool === 'shot';
      if (c.dataset.cell === 'eye') on = !annotationsVisible;
      if (c.dataset.cell === 'board') on = shadeOn || recording;
      c.dataset.on = String(on);
    });

    shadow.querySelectorAll('[data-badge]').forEach((b) => {
      b.style.background = b.dataset.badge === 'board'
        ? (recording ? '#e8352a' : '#ec008c')
        : TOOLS[b.dataset.badge].color;
    });

    $('#cur').style.background = currentColor();
    $('#strip').hidden = collapsed;
    if (collapsed) closeFlyout();

    const drawing = active && tool !== 'pointer';
    liveCanvas.classList.toggle('annotator-canvas--active', drawing);
    strokeCanvas.classList.toggle('annotator-canvas--hidden', !annotationsVisible);
    liveCanvas.classList.toggle('annotator-canvas--hidden', !annotationsVisible);
    shade.style.background = shadeOn ? 'rgba(255,255,255,.94)' : 'transparent';
  }

  // ------------------------------------------- logo: drag to move, click to collapse
  (() => {
    const logo = $('#logo');
    // Reading offsetLeft/offsetTop inside pointermove forces a synchronous
    // layout on every event (we just wrote style.left/top moments before) -
    // that layout thrashing is what made dragging feel laggy. Capture the
    // starting position once on pointerdown and do pure arithmetic after.
    let startX = 0, startY = 0, originLeft = 0, originTop = 0, dragging = false, moved = false;
    logo.addEventListener('pointerdown', (e) => {
      e.preventDefault(); // also blocks the native image drag-ghost
      dragging = true; moved = false;
      logo.setPointerCapture(e.pointerId);
      startX = e.clientX; startY = e.clientY;
      originLeft = host.offsetLeft; originTop = host.offsetTop;
    });
    logo.addEventListener('pointermove', (e) => {
      if (!dragging) return;
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      if (!moved && (Math.abs(dx) > 2 || Math.abs(dy) > 2)) moved = true;
      host.style.left = (originLeft + dx) + 'px';
      host.style.top = (originTop + dy) + 'px';
    });
    logo.addEventListener('pointerup', () => {
      dragging = false;
      if (!moved) { collapsed = !collapsed; syncUI(); }
    });
  })();

  // clicking anywhere else on the page dismisses an open flyout
  window.addEventListener('pointerdown', (e) => {
    if (openFlyout && !e.composedPath().includes(host)) closeFlyout();
  }, true);

  // ---------------------------------------------------------------- activate
  function setActive(on) {
    active = on;
    if (on) {
      document.documentElement.append(shade, strokeCanvas, liveCanvas, host);
      sizeCanvases(); syncUI(); restoreAnnotations(true);
    } else {
      activePointerId = null;
      current = null;
      selection = null;
      shade.remove(); strokeCanvas.remove(); liveCanvas.remove(); host.remove();
    }
  }

  document.addEventListener('keydown', (e) => {
    if (!active) return;
    if (e.key === 'Escape') { if (openFlyout) closeFlyout(); else setActive(false); }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
      e.preventDefault();
      e.shiftKey ? doRedo() : doUndo();
    }
  });

  // ---------------------------------------------------------------- storage
  function save() {
    try { chrome.storage.local.set({ tools: TOOLS }); } catch { /* nicety only */ }
  }
  chrome.storage.local.get('tools', (data) => {
    if (!data || !data.tools) return;
    for (const k of Object.keys(TOOLS)) if (data.tools[k]) Object.assign(TOOLS[k], data.tools[k]);
    if (active) syncUI();
  });

  // ---------------------------------------------------------------- messages
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === 'ANNOTATOR_TOGGLE') setActive(!active);
    if (msg.type === 'ANNOTATOR_RECORDING_STATE') {
      recording = msg.recording;
      if (msg.saved) setNote('Saved to disk');
      if (msg.error) setNote(msg.error);
      syncUI();
    }
  });
})();
