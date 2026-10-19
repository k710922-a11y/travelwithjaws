// 해변과 도시가 만나는 히어로 장면 — 캔버스로 그리는 가벼운 '영상'
// 왼쪽: 모래사장·파라솔·밀려오는 파도 / 가운데: 현수교 / 오른쪽: 도시 스카이라인과 산
// 이미지·동영상 파일 없이 동작. 실제 영상(권리 승인분)이 있으면 그 뒤의 대체 장면으로 쓴다.
// 사용: const stop = startHeroScene(canvasElement, { reduced: boolean })

export function startHeroScene(canvas, opts = {}) {
  const ctx = canvas.getContext("2d");
  if (!ctx) return () => {};
  let W = 0, H = 0, dpr = 1, raf = 0, running = true, visible = true;
  let mx = 0.5, my = 0.5, tmx = 0.5, tmy = 0.5;
  const reduced = !!opts.reduced;

  // 시드 고정 난수 — 매번 같은 도시가 그려지도록
  let seed = 7;
  const rnd = () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };

  const buildings = [];
  const ridgeFar = [], ridgeNear = [];
  const gulls = Array.from({ length: 5 }, (_, i) => ({ x: rnd(), y: 0.12 + rnd() * 0.18, s: 0.6 + rnd() * 0.6, ph: rnd() * 6, v: 0.008 + rnd() * 0.01 }));
  function generate() {
    seed = 7; buildings.length = 0; ridgeFar.length = 0; ridgeNear.length = 0;
    let x = 0.4;
    while (x < 1.08) {
      const w = 0.018 + rnd() * 0.03;
      const tall = rnd();
      const h = tall > 0.86 ? 0.26 + rnd() * 0.14 : 0.08 + rnd() * 0.15;
      const kind = rnd();
      const lights = Array.from({ length: 14 }, () => ({ x: rnd(), y: rnd(), ph: rnd() * 6.28, sp: 0.4 + rnd() * 1.2 }));
      buildings.push({ x, w, h, kind, shade: rnd(), lights });
      x += w + 0.002 + rnd() * 0.006;
    }
    for (let i = 0; i <= 40; i++) {
      const t = i / 40;
      ridgeFar.push(0.12 + Math.sin(t * 5.2 + 1) * 0.035 + Math.sin(t * 13) * 0.012 + (t > 0.45 ? 0.04 : 0));
      ridgeNear.push(0.07 + Math.sin(t * 7 + 2) * 0.025 + Math.sin(t * 19) * 0.008);
    }
  }

  function resize() {
    const r = canvas.getBoundingClientRect();
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = Math.max(1, r.width); H = Math.max(1, r.height);
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  const mix = (a, b, t) => a + (b - a) * t;
  const hex = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
  const mixc = (a, b, t, al = 1) => { const A = hex(a), B = hex(b); return `rgba(${A.map((v, i) => Math.round(mix(v, B[i], t))).join(",")},${al})`; };

  function draw(time) {
    const t = time / 1000;
    mx += (tmx - mx) * 0.05; my += (tmy - my) * 0.05;
    const px = (mx - 0.5), py = (my - 0.5);
    // 낮 → 황금빛 오후 사이를 천천히 오간다 (밝은 분위기 유지)
    const gold = reduced ? 0.25 : (Math.sin(t / 18) + 1) / 2 * 0.75;
    const horizon = H * 0.6 + py * 6;

    // 하늘
    const sky = ctx.createLinearGradient(0, 0, 0, horizon);
    sky.addColorStop(0, mixc("#5fb8ec", "#6aa8e2", gold));
    sky.addColorStop(0.55, mixc("#a9dcf6", "#c7d9f2", gold));
    sky.addColorStop(1, mixc("#e9f8fd", "#ffe2b0", gold));
    ctx.fillStyle = sky; ctx.fillRect(0, 0, W, horizon + 2);

    // 해
    const sx = W * (0.72 - gold * 0.06) - px * 10, sy = horizon - H * (0.36 - gold * 0.14);
    const sr = Math.max(26, H * 0.055);
    const glow = ctx.createRadialGradient(sx, sy, 0, sx, sy, sr * 6);
    glow.addColorStop(0, mixc("#fff7d6", "#ffe08a", gold, 0.95));
    glow.addColorStop(0.2, mixc("#fff3c4", "#ffd27a", gold, 0.45));
    glow.addColorStop(1, "rgba(255,240,200,0)");
    ctx.fillStyle = glow; ctx.fillRect(0, 0, W, horizon);
    ctx.fillStyle = mixc("#fffbe8", "#ffe39a", gold); ctx.beginPath(); ctx.arc(sx, sy, sr, 0, 6.29); ctx.fill();

    // 구름 (느리게 흐름)
    for (let i = 0; i < 4; i++) {
      const cx = ((i * 0.31 + t * 0.006 * (1 + i * 0.3)) % 1.3 - 0.15) * W - px * (8 + i * 4);
      const cy = H * (0.1 + i * 0.07);
      ctx.fillStyle = `rgba(255,255,255,${0.55 - i * 0.08})`;
      ctx.beginPath();
      for (let k = 0; k < 4; k++) ctx.ellipse(cx + k * 26, cy - (k % 2) * 8, 34 - k * 3, 12 + (k % 2) * 4, 0, 0, 6.29);
      ctx.fill();
    }

    // 먼 산 두 겹 (부산 해안 도시처럼 도시 뒤로 산)
    const ridge = (arr, off, col, base) => {
      ctx.fillStyle = col; ctx.beginPath(); ctx.moveTo(-20, horizon);
      arr.forEach((v, i) => ctx.lineTo(W * (0.3 + i / 40 * 0.75) - px * off, base - v * H));
      ctx.lineTo(W + 20, horizon); ctx.closePath(); ctx.fill();
    };
    ridge(ridgeFar, 6, mixc("#9ec6e3", "#b9b8dc", gold, 0.75), horizon);
    ridge(ridgeNear, 10, mixc("#7fb0d6", "#a49ccf", gold, 0.8), horizon);

    // 도시 스카이라인
    const cityShift = -px * 18;
    buildings.forEach(b => {
      const bx = b.x * W + cityShift, bw = b.w * W, bh = b.h * H, by = horizon - bh;
      const base = b.shade > 0.5 ? "#5b5bd6" : "#3f6fb8";
      ctx.fillStyle = mixc(base, "#e8ecf8", 0.42 - b.shade * 0.2 + gold * 0.08, 0.95);
      if (b.kind > 0.82) { // 둥근 지붕 고층
        ctx.beginPath(); ctx.moveTo(bx, horizon); ctx.lineTo(bx, by + bw * 0.4);
        ctx.quadraticCurveTo(bx + bw / 2, by - bw * 0.3, bx + bw, by + bw * 0.4); ctx.lineTo(bx + bw, horizon); ctx.fill();
      } else if (b.kind > 0.68) { // 계단형
        ctx.fillRect(bx, by + bh * 0.18, bw, bh * 0.82); ctx.fillRect(bx + bw * 0.2, by, bw * 0.6, bh * 0.2);
      } else ctx.fillRect(bx, by, bw, bh);
      // 유리면 하이라이트
      ctx.fillStyle = `rgba(255,255,255,${0.12 + gold * 0.1})`; ctx.fillRect(bx + bw * 0.62, by + 4, bw * 0.14, bh - 4);
      // 창문 불빛 (황금빛일수록 켜짐)
      if (gold > 0.3 && bh > 30) {
        b.lights.forEach(l => {
          const on = Math.sin(t * l.sp + l.ph) > 0.2;
          if (!on) return;
          ctx.fillStyle = `rgba(255,214,120,${(gold - 0.3) * 1.4})`;
          ctx.fillRect(bx + 3 + l.x * (bw - 8), by + 8 + l.y * (bh - 16), 2.5, 2.5);
        });
      }
    });

    // 바다
    const sea = ctx.createLinearGradient(0, horizon, 0, H);
    sea.addColorStop(0, mixc("#59c3dc", "#7cb9d8", gold));
    sea.addColorStop(0.5, "#1aa3c4");
    sea.addColorStop(1, "#0d86ad");
    ctx.fillStyle = sea; ctx.fillRect(0, horizon, W, H - horizon);
    // 수평선 반사광
    ctx.fillStyle = "rgba(255,255,255,0.35)"; ctx.fillRect(0, horizon, W, 1.2);

    // 햇빛 반짝임 기둥
    for (let i = 0; i < 26; i++) {
      const yy = horizon + 4 + i * (H - horizon) / 30;
      const spread = 6 + i * 3.2;
      const flick = reduced ? 0.6 : (Math.sin(t * 3 + i * 1.7) + 1) / 2;
      ctx.fillStyle = `rgba(255,248,214,${0.5 * flick * (1 - i / 30)})`;
      ctx.fillRect(sx - spread / 2 + Math.sin(t * 2 + i) * 4, yy, spread * (0.4 + flick * 0.6), 1.6);
    }

    // 물결 선 (원근: 아래로 갈수록 간격·진폭 커짐)
    for (let row = 0; row < 14; row++) {
      const k = row / 14, y = horizon + Math.pow(k, 1.6) * (H - horizon) + 6;
      const amp = 1 + k * 4, freq = 0.02 - k * 0.012;
      ctx.strokeStyle = `rgba(255,255,255,${0.12 + k * 0.18})`; ctx.lineWidth = 1 + k;
      ctx.beginPath();
      for (let x = -10; x <= W + 10; x += 12) {
        const yy = y + Math.sin(x * freq + t * (0.8 + k) + row) * amp;
        x === -10 ? ctx.moveTo(x, yy) : ctx.lineTo(x, yy);
      }
      ctx.setLineDash([18 + k * 30, 30 + k * 40]); ctx.lineDashOffset = -t * (10 + k * 20);
      ctx.stroke();
    }
    ctx.setLineDash([]);

    // 현수교 (바다 위, 도시 앞)
    const deck = horizon + H * 0.035, bShift = -px * 26;
    const T1 = W * 0.36 + bShift, T2 = W * 0.66 + bShift, th = H * 0.16;
    ctx.strokeStyle = "rgba(250,252,255,0.95)"; ctx.lineWidth = 2.4;
    // 상판
    ctx.beginPath(); ctx.moveTo(W * 0.08 + bShift, deck); ctx.lineTo(W * 1.05 + bShift, deck); ctx.stroke();
    ctx.fillStyle = "rgba(240,246,252,0.95)"; ctx.fillRect(W * 0.08 + bShift, deck, W, 3);
    // 주탑
    [T1, T2].forEach(tx => {
      ctx.fillStyle = "rgba(250,252,255,0.97)";
      ctx.fillRect(tx - 5, deck - th, 3, th + 10); ctx.fillRect(tx + 2, deck - th, 3, th + 10);
      ctx.fillRect(tx - 5, deck - th * 0.62, 10, 2); ctx.fillRect(tx - 5, deck - th, 10, 2);
    });
    // 주케이블 + 행어
    const cable = (x1, y1, x2, y2, sag) => {
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.quadraticCurveTo((x1 + x2) / 2, Math.max(y1, y2) + sag, x2, y2); ctx.stroke();
      ctx.lineWidth = 0.8;
      for (let x = x1 + 10; x < x2; x += 10) {
        const tt = (x - x1) / (x2 - x1), cy = (1 - tt) ** 2 * y1 + 2 * (1 - tt) * tt * (Math.max(y1, y2) + sag) + tt * tt * y2;
        ctx.beginPath(); ctx.moveTo(x, cy); ctx.lineTo(x, deck); ctx.stroke();
      }
      ctx.lineWidth = 2;
    };
    ctx.lineWidth = 2;
    cable(T1, deck - th, T2, deck - th, th * 0.85);
    cable(W * 0.12 + bShift, deck - 2, T1, deck - th, th * 0.05);
    cable(T2, deck - th, W * 0.95 + bShift, deck - 2, th * 0.05);
    // 다리 위 차량 불빛
    for (let i = 0; i < 9; i++) {
      const dir = i % 2 ? 1 : -1;
      const pos = ((i * 0.137 + t * 0.03 * dir) % 1 + 1) % 1;
      ctx.fillStyle = dir > 0 ? "rgba(255,190,90,0.95)" : "rgba(255,255,255,0.95)";
      ctx.fillRect(W * (0.1 + pos * 0.9) + bShift, deck - 2 + (dir > 0 ? 0 : 1), 4, 1.6);
    }
    // 다리 그림자 반사
    ctx.fillStyle = "rgba(255,255,255,0.12)"; ctx.fillRect(W * 0.08 + bShift, deck + 8, W, 2);

    // 요트
    const yx = ((t * 0.012) % 1.2 - 0.1) * W, yy = horizon + H * 0.11;
    ctx.fillStyle = "#ffffff";
    ctx.beginPath(); ctx.moveTo(yx, yy); ctx.lineTo(yx + 2, yy - 30); ctx.lineTo(yx + 20, yy); ctx.closePath(); ctx.fill();
    ctx.fillStyle = "#ffb627"; ctx.beginPath(); ctx.moveTo(yx - 2, yy); ctx.lineTo(yx, yy - 22); ctx.lineTo(yx - 13, yy); ctx.closePath(); ctx.fill();
    ctx.fillStyle = "#0f2a3d"; ctx.beginPath(); ctx.moveTo(yx - 16, yy + 1); ctx.lineTo(yx + 24, yy + 1); ctx.lineTo(yx + 18, yy + 6); ctx.lineTo(yx - 11, yy + 6); ctx.fill();


    // 상어 지느러미 — Travel.with.Jaws 의 길잡이. 바다를 천천히 가로지르며 물살을 남김
    const fx = ((0.15 + t * 0.018) % 1.3 - 0.15) * W - px * 22, fy = horizon + H * 0.2 + Math.sin(t * 0.8) * 3;
    const fs = Math.max(0.8, H / 620);
    ctx.strokeStyle = "rgba(255,255,255,0.55)"; ctx.lineWidth = 1.4;
    for (let k = 1; k <= 3; k++) { ctx.beginPath(); ctx.moveTo(fx - 4 * fs, fy + 1); ctx.quadraticCurveTo(fx - (18 + k * 16) * fs, fy - 1 + k * 2.2, fx - (34 + k * 26) * fs, fy + k * 3.4); ctx.stroke(); }
    ctx.fillStyle = "#123247";
    ctx.beginPath(); ctx.moveTo(fx - 14 * fs, fy + 1); ctx.bezierCurveTo(fx - 9 * fs, fy - 10 * fs, fx - 2 * fs, fy - 18 * fs, fx + 6 * fs, fy - 22 * fs);
    ctx.bezierCurveTo(fx + 4 * fs, fy - 12 * fs, fx + 5 * fs, fy - 5 * fs, fx + 10 * fs, fy + 1); ctx.closePath(); ctx.fill();
    ctx.fillStyle = "rgba(255,255,255,0.8)"; ctx.fillRect(fx - 16 * fs, fy + 1, 28 * fs, 1.4);
    // 갈매기
    ctx.strokeStyle = "rgba(15,42,61,0.65)"; ctx.lineWidth = 1.6;
    gulls.forEach(g => {
      const gx = ((g.x + t * g.v) % 1.2 - 0.1) * W, gy = g.y * H + Math.sin(t + g.ph) * 6, flap = Math.sin(t * 6 + g.ph) * 4 * g.s;
      ctx.beginPath(); ctx.moveTo(gx - 9 * g.s, gy - flap); ctx.quadraticCurveTo(gx - 4 * g.s, gy - 4 * g.s, gx, gy);
      ctx.quadraticCurveTo(gx + 4 * g.s, gy - 4 * g.s, gx + 9 * g.s, gy - flap); ctx.stroke();
    });

    // 전경 모래사장 (왼쪽 아래)
    const lap = reduced ? 0 : Math.sin(t * 0.9) * 10;
    const sandTop = H * 0.83 - py * 8;
    const shore = (o) => {
      ctx.beginPath(); ctx.moveTo(-20, sandTop - 30 + o);
      ctx.bezierCurveTo(W * 0.2, sandTop - 10 + o, W * 0.36, sandTop + 26 + o, W * 0.62, H + 20);
      ctx.lineTo(-20, H + 20); ctx.closePath();
    };
    // 젖은 모래 + 거품
    shore(-8 + lap); ctx.fillStyle = "rgba(255,255,255,0.75)"; ctx.fill();
    shore(-2 + lap * 0.6); ctx.fillStyle = "#e9cf9a"; ctx.fill();
    shore(10); const sand = ctx.createLinearGradient(0, sandTop, 0, H);
    sand.addColorStop(0, "#f8e3b5"); sand.addColorStop(1, "#f1d091"); ctx.fillStyle = sand; ctx.fill();

    // 파라솔
    const umb = (ux, uy, s, c1, c2) => {
      ctx.strokeStyle = "#0f2a3d"; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(ux, uy); ctx.lineTo(ux + 2, uy + 34 * s); ctx.stroke();
      for (let i = 0; i < 6; i++) {
        ctx.fillStyle = i % 2 ? c1 : c2;
        ctx.beginPath(); ctx.moveTo(ux, uy - 16 * s);
        ctx.arc(ux, uy, 26 * s, Math.PI + i * Math.PI / 6, Math.PI + (i + 1) * Math.PI / 6); ctx.closePath(); ctx.fill();
      }
    };
    const bx = -px * 30;
    umb(W * 0.07 + bx, sandTop + 8, 1.1, "#ffb627", "#ffffff");
    umb(W * 0.17 + bx, sandTop + 24, 0.9, "#0091b8", "#ffffff");
    umb(W * 0.26 + bx, sandTop + 46, 0.75, "#5b5bd6", "#ffffff");
    // 비치 타월
    ctx.fillStyle = "#ff8f6b"; ctx.save(); ctx.translate(W * 0.13 + bx, sandTop + 60); ctx.rotate(-0.15); ctx.fillRect(0, 0, 46, 14); ctx.fillStyle = "#fff"; ctx.fillRect(10, 0, 5, 14); ctx.fillRect(26, 0, 5, 14); ctx.restore();
  }

  function loop(time) {
    if (!running) return;
    if (visible) draw(time);
    raf = requestAnimationFrame(loop);
  }

  const onMove = e => { const r = canvas.getBoundingClientRect(); tmx = (e.clientX - r.left) / r.width; tmy = (e.clientY - r.top) / r.height; };
  const ro = new ResizeObserver(() => { resize(); if (reduced) draw(12000); });
  ro.observe(canvas);
  let io = null;
  if ("IntersectionObserver" in window) { io = new IntersectionObserver(es => { visible = es[0].isIntersecting; }); io.observe(canvas); }
  generate(); resize();
  if (reduced) draw(12000);
  else { window.addEventListener("pointermove", onMove, { passive: true }); raf = requestAnimationFrame(loop); }

  return () => { running = false; cancelAnimationFrame(raf); ro.disconnect(); io?.disconnect(); window.removeEventListener("pointermove", onMove); };
}
