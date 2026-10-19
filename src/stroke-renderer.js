// Shared by declarative content scripts and the click-to-inject fallback.
(() => {
  const clampPressure = (value) => Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 1;
  const widthAt = (width, pressure) => Math.max(1, width * (0.2 + 0.8 * pressure));

  // Centripetal Catmull–Rom controls keep unevenly spaced input samples from
  // overshooting at corners. Canvas rasterizes the actual cubic curves.
  function controls(points, index) {
    const a = points[index];
    const b = points[index + 1];
    const first = points[0], last = points[points.length - 1];
    const closed = points.length > 3 && Math.hypot(first.x - last.x, first.y - last.y) < 0.01;
    const before = points[index - 1] || (closed ? points[points.length - 2]
      : { x: 2 * a.x - b.x, y: 2 * a.y - b.y });
    const after = points[index + 2] || (closed ? points[1]
      : { x: 2 * b.x - a.x, y: 2 * b.y - a.y });
    const knot = (p, q) => Math.max(0.001, Math.sqrt(Math.hypot(q.x - p.x, q.y - p.y)));
    const d0 = knot(before, a), d1 = knot(a, b), d2 = knot(b, after);
    const c1 = {}, c2 = {};
    for (const axis of ['x', 'y']) {
      const start = (a[axis] - before[axis]) / d0 - (b[axis] - before[axis]) / (d0 + d1)
        + (b[axis] - a[axis]) / d1;
      const end = (b[axis] - a[axis]) / d1 - (after[axis] - a[axis]) / (d1 + d2)
        + (after[axis] - b[axis]) / d2;
      c1[axis] = a[axis] + start * d1 / 3;
      c2[axis] = b[axis] - end * d1 / 3;
    }
    return { c1, c2 };
  }

  function traceCurve(ctx, points, move = true) {
    if (move) ctx.moveTo(points[0].x, points[0].y);
    for (let index = 0; index < points.length - 1; index++) {
      const { c1, c2 } = controls(points, index);
      const end = points[index + 1];
      ctx.bezierCurveTo(c1.x, c1.y, c2.x, c2.y, end.x, end.y);
    }
  }

  function cleanSamples(stroke) {
    const samples = [];
    stroke.points.forEach((point, index) => {
      if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) return;
      const pressure = clampPressure(stroke.pressures?.[index]);
      const last = samples[samples.length - 1];
      if (last && Math.hypot(point.x - last.x, point.y - last.y) < 0.01) {
        last.pressure = pressure;
      } else {
        samples.push({ x: point.x, y: point.y, pressure });
      }
    });
    return samples;
  }

  function draw(ctx, stroke) {
    const samples = cleanSamples(stroke);
    if (!samples.length) return;
    const first = samples[0];
    ctx.beginPath();
    if (samples.length === 1) {
      ctx.arc(first.x, first.y, widthAt(stroke.width, first.pressure) / 2, 0, Math.PI * 2);
      ctx.fill();
      return;
    }

    if (samples.every((sample) => Math.abs(sample.pressure - first.pressure) < 0.001)) {
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.lineWidth = widthAt(stroke.width, first.pressure);
      traceCurve(ctx, samples);
      ctx.stroke();
      return;
    }

    const left = [], right = [], angles = [];
    for (let index = 0; index < samples.length; index++) {
      const point = samples[index];
      const last = index === samples.length - 1;
      const { c1, c2 } = controls(samples, last ? index - 1 : index);
      let dx = last ? point.x - c2.x : c1.x - point.x;
      let dy = last ? point.y - c2.y : c1.y - point.y;
      if (Math.hypot(dx, dy) < 0.001) {
        const neighbor = samples[last ? index - 1 : index + 1];
        dx = last ? point.x - neighbor.x : neighbor.x - point.x;
        dy = last ? point.y - neighbor.y : neighbor.y - point.y;
      }
      const length = Math.hypot(dx, dy) || 1;
      const nx = -dy / length, ny = dx / length;
      const radius = widthAt(stroke.width, point.pressure) / 2;
      left.push({ x: point.x + nx * radius, y: point.y + ny * radius });
      right.push({ x: point.x - nx * radius, y: point.y - ny * radius });
      angles.push(Math.atan2(ny, nx));
    }

    // One fill avoids dark seams where translucent highlighter caps overlap.
    const last = samples[samples.length - 1];
    const endAngle = angles[angles.length - 1];
    traceCurve(ctx, left);
    ctx.arc(last.x, last.y, widthAt(stroke.width, last.pressure) / 2,
      endAngle, endAngle - Math.PI, true);
    traceCurve(ctx, right.reverse(), false);
    ctx.arc(first.x, first.y, widthAt(stroke.width, first.pressure) / 2,
      angles[0] - Math.PI, angles[0] - 2 * Math.PI, true);
    ctx.closePath();
    ctx.fill();
  }

  function appendSamples(stroke, event, scroll = { x: 0, y: 0 }) {
    if (!stroke.pressures) stroke.pressures = stroke.points.map(() => 1);
    const coalesced = typeof event.getCoalescedEvents === 'function' ? event.getCoalescedEvents() : [];
    for (const sample of [...coalesced, event]) {
      if (!Number.isFinite(sample.clientX) || !Number.isFinite(sample.clientY)) continue;
      const point = { x: sample.clientX + scroll.x, y: sample.clientY + scroll.y };
      const last = stroke.points.length - 1;
      const isPen = (sample.pointerType || event.pointerType) === 'pen';
      // Pointer-up pressure is always zero; keep the last contact pressure.
      const pressure = event.type === 'pointerup'
        ? (stroke.pressures[last] ?? 1)
        : (isPen ? clampPressure(sample.pressure) : 1);
      if (last >= 0 && Math.hypot(point.x - stroke.points[last].x, point.y - stroke.points[last].y) < 0.01) {
        stroke.pressures[last] = pressure;
      } else {
        stroke.points.push(point);
        stroke.pressures.push(pressure);
      }
    }
  }

  globalThis.MagicPenStrokeRenderer = Object.freeze({ draw, appendSamples });
})();
