const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const sandbox = {};
vm.runInNewContext(fs.readFileSync(path.join(root, 'src/stroke-renderer.js'), 'utf8'), sandbox);
const renderer = sandbox.MagicPenStrokeRenderer;

function context() {
  const commands = [];
  const ctx = { commands };
  for (const name of ['beginPath', 'moveTo', 'bezierCurveTo', 'arc', 'closePath', 'stroke', 'fill', 'lineTo']) {
    ctx[name] = (...args) => { commands.push({ name, args }); };
  }
  return ctx;
}

test('an eight-sample circle stays round between samples and uses continuous curves', () => {
  const points = Array.from({ length: 9 }, (_, i) => ({
    x: 100 * Math.cos(i * Math.PI / 4), y: 100 * Math.sin(i * Math.PI / 4)
  }));
  const ctx = context();
  renderer.draw(ctx, { points, width: 3 });
  let start = points[0];
  const curves = ctx.commands.filter(({ name }) => name === 'bezierCurveTo');
  assert.equal(curves.length, 8);
  assert.equal(ctx.commands.some(({ name }) => name === 'lineTo'), false);
  for (const { args: [x1, y1, x2, y2, x, y] } of curves) {
    for (let step = 0; step <= 20; step++) {
      const t = step / 20, u = 1 - t;
      const px = u ** 3 * start.x + 3 * u ** 2 * t * x1 + 3 * u * t ** 2 * x2 + t ** 3 * x;
      const py = u ** 3 * start.y + 3 * u ** 2 * t * y1 + 3 * u * t ** 2 * y2 + t ** 3 * y;
      assert.ok(Math.abs(Math.hypot(px, py) - 100) < 1, 'circle deviates by less than one pixel');
    }
    start = { x, y };
  }
});

test('variable pressure keeps smooth edges and fills translucent strokes once', () => {
  const ctx = context();
  renderer.draw(ctx, {
    points: [{ x: 0, y: 0 }, { x: 20, y: 12 }, { x: 45, y: 5 }, { x: 70, y: 20 }],
    pressures: [0.1, 0.4, 1, 0.6], width: 18
  });
  assert.ok(ctx.commands.some(({ name }) => name === 'bezierCurveTo'));
  assert.equal(ctx.commands.some(({ name }) => name === 'lineTo'), false);
  assert.equal(ctx.commands.filter(({ name }) => name === 'fill').length, 1);
  assert.equal(ctx.commands.filter(({ name }) => name === 'arc').length, 2);
  for (const { args } of ctx.commands) {
    for (const value of args) if (typeof value === 'number') assert.ok(Number.isFinite(value));
  }
});

test('stationary input produces one rounded dot without degenerate curves', () => {
  const ctx = context();
  renderer.draw(ctx, { points: [{ x: 5, y: 9 }, { x: 5, y: 9 }], pressures: [0.2, 0.8], width: 10 });
  assert.equal(ctx.commands.filter(({ name }) => name === 'arc').length, 1);
  assert.equal(ctx.commands.filter(({ name }) => name === 'bezierCurveTo').length, 0);
});

test('coalesced movement samples retain their order, pressure and page coordinates', () => {
  const stroke = { points: [], pressures: [] };
  renderer.appendSamples(stroke, {
    type: 'pointermove', pointerType: 'pen', clientX: 30, clientY: 40, pressure: 0.8,
    getCoalescedEvents: () => [
      { clientX: 10, clientY: 20, pressure: 0.2 },
      { clientX: 20, clientY: 30, pressure: 0.5 },
      { clientX: 30, clientY: 40, pressure: 0.8 }
    ]
  }, { x: 100, y: 200 });
  assert.equal(stroke.points.length, 3, 'parent event does not duplicate its last sample');
  assert.deepEqual(Array.from(stroke.points, ({ x, y }) => [x, y]), [[110, 220], [120, 230], [130, 240]]);
  assert.deepEqual(Array.from(stroke.pressures), [0.2, 0.5, 0.8]);
});

test('pointer-up keeps the final position and the last contact pressure', () => {
  const stroke = { points: [{ x: 10, y: 20 }], pressures: [0.7] };
  renderer.appendSamples(stroke, { type: 'pointerup', pointerType: 'pen', clientX: 12, clientY: 23, pressure: 0 });
  assert.deepEqual([stroke.points[1].x, stroke.points[1].y], [12, 23]);
  assert.equal(stroke.pressures[1], 0.7);
});

test('mouse input and saved strokes without pressure keep their selected width', () => {
  const stroke = { points: [], pressures: [] };
  renderer.appendSamples(stroke, { type: 'pointermove', pointerType: 'mouse', clientX: 0, clientY: 0, pressure: 0.5 });
  renderer.appendSamples(stroke, { type: 'pointermove', pointerType: 'mouse', clientX: 10, clientY: 10, pressure: 0.5 });
  const ctx = context();
  renderer.draw(ctx, { points: stroke.points, width: 9 });
  assert.deepEqual(Array.from(stroke.pressures), [1, 1]);
  assert.equal(ctx.lineWidth, 9);
});

test('the manifest loads the renderer before the content script', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));
  const scripts = manifest.content_scripts[0].js;
  assert.ok(scripts.indexOf('src/stroke-renderer.js') >= 0);
  assert.ok(scripts.indexOf('src/stroke-renderer.js') < scripts.indexOf('src/content.js'));
});
