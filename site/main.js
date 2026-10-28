// Howler's site: the language switch, and a letter that writes its answer with a quill
// and then burns from the bottom edge, as the app's letter does (a port of BurnField).
(function () {
  "use strict";

  var root = document.documentElement;
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function lang() { return /^zh/i.test(root.lang) ? "zh" : "en"; }

  // MARK: Language

  var toggle = document.querySelector("[data-lang-toggle]");
  if (toggle) {
    toggle.addEventListener("click", function () {
      var next = lang() === "zh" ? "en" : "zh";
      root.lang = next === "zh" ? "zh-CN" : "en";
      try { localStorage.setItem("howler-lang", next); } catch (e) {}
      letter.restart();
    });
  }

  // MARK: Star seal

  // A star is a reader's wax seal on the letter: pressed here, given on GitHub (the link
  // opens it in a new tab; this page can't star for anyone).
  (function () {
    var link = document.querySelector("[data-star]");
    if (!link) return;
    var label = link.querySelector("[data-star-label]");
    var meta = link.querySelector("[data-star-meta]");

    function load(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }
    function save(key, value) { try { localStorage.setItem(key, value); } catch (e) {} }

    function showSealed() {
      link.classList.add("sealed");
      label.innerHTML = '<span class="en">Sealed, with thanks</span><span class="zh">已封缄，谢谢你</span>';
    }
    function showCount(n) {
      if (typeof n !== "number" || n < 0) return;
      meta.innerHTML = n === 0
        ? '<span class="en">be the first, on GitHub</span><span class="zh">来盖第一枚 · GitHub</span>'
        : '<span class="en">✦ ' + n + (n === 1 ? " seal" : " seals") + ' on GitHub</span><span class="zh">GitHub 上已有 ' + n + ' 枚</span>';
    }

    if (load("howler-sealed")) showSealed();

    // The count is a nicety: cached for an hour, and simply left out if the public API
    // (60 requests an hour per address) says no.
    var cached = null;
    try { cached = JSON.parse(load("howler-stars") || "null"); } catch (e) {}
    if (cached && Date.now() - cached.at < 3600e3) {
      showCount(cached.n);
    } else if (window.fetch) {
      fetch("https://api.github.com/repos/HiAriesZhou/Howler", { headers: { Accept: "application/vnd.github+json" } })
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (d) {
          if (!d || typeof d.stargazers_count !== "number") return;
          showCount(d.stargazers_count);
          save("howler-stars", JSON.stringify({ n: d.stargazers_count, at: Date.now() }));
        })
        .catch(function () {});
    }

    link.addEventListener("click", function () {
      link.classList.remove("pressing");
      void link.offsetWidth; // a second press plays again
      link.classList.add("pressing");
      save("howler-sealed", "1");
      setTimeout(function () { link.classList.remove("pressing"); showSealed(); }, reduceMotion ? 0 : 900);
    });
  })();

  // MARK: Letters

  var LETTERS = {
    en: [
      ["What does “burn after reading” mean?",
       "It marks a message meant to be read once: when you have it, the paper is destroyed, so nothing can be found later.\n\nHowler treats every answer that way. Read it, copy what you need, and the letter burns."],
      ["How do I undo my last git commit but keep the changes?",
       "Use a soft reset:\n\n    git reset --soft HEAD~1\n\nThe commit is gone; its changes stay staged, ready to commit again."],
      ["Is there a word for the smell of rain on dry earth?",
       "Petrichor — from Greek petra, stone, and ichor, the fluid said to flow in the veins of the gods."]
    ],
    zh: [
      ["“阅后即焚”是什么意思？",
       "指只供阅读一次的讯息：读过之后，纸就被销毁，日后无从查找。\n\nHowler 把每个回答都当作这样一封信：读完、复制需要的部分，信就烧掉。"],
      ["怎么撤销上一次 git 提交，但保留改动？",
       "用 soft reset：\n\n    git reset --soft HEAD~1\n\n提交没了，改动仍留在暂存区，可以重新提交。"],
      ["雨后泥土的气味有专门的词吗？",
       "有，叫 Petrichor（潮土油）：来自希腊语 petra（石头）与 ichor（传说中流淌在众神血管里的灵液）。"]
    ]
  };

  var sheet = document.querySelector("[data-sheet]");
  var askEl = document.querySelector("[data-ask]");
  var answerEl = document.querySelector("[data-answer]");
  var canvas = document.querySelector("[data-fire]");
  var burnButton = document.querySelector("[data-burn]");
  if (!sheet || !askEl || !answerEl || !canvas) return;

  var letter = (function () {
    var index = 0;
    var timer = null;
    // writing → shown → burning → resting → writing … Only a letter on show can burn.
    var phase = "idle";
    var run = 0; // bumps on restart, so stale callbacks stop
    var visible = true;
    var burnDue = false; // the automatic burn came due while the letter was off-screen

    function clear() { clearTimeout(timer); timer = null; }

    function render(text, done) {
      var freshLength = done ? 0 : Math.min(6, text.length);
      var settled = text.slice(0, text.length - freshLength);
      var fresh = text.slice(text.length - freshLength);
      answerEl.textContent = "";
      answerEl.appendChild(document.createTextNode(settled));
      var span = document.createElement("span");
      span.className = done ? "" : "fresh quill";
      span.textContent = fresh;
      answerEl.appendChild(span);
    }

    function write(myRun) {
      var letters = LETTERS[lang()];
      var pair = letters[index % letters.length];
      var text = pair[1];
      askEl.textContent = pair[0];
      sheet.style.opacity = "1";
      phase = "writing";
      fire.prepare();
      if (reduceMotion) {
        // No motion, no cycling: the letter stays until the reader burns it.
        render(text, true);
        phase = "shown";
        fire.prepare();
        return;
      }
      var shown = 0;
      (function step() {
        if (myRun !== run) return;
        shown = Math.min(text.length, shown + 1 + Math.floor(Math.random() * 2));
        render(text.slice(0, shown), false);
        if (shown >= text.length) {
          render(text, true);
          phase = "shown";
          fire.prepare();
          timer = setTimeout(function () {
            if (visible) burn(myRun); else burnDue = true;
          }, 4200);
          return;
        }
        var ch = text.charAt(shown - 1);
        var pause = /[.。,，:：;；!?！？—\n]/.test(ch) ? 260 : 26 + Math.random() * 40;
        timer = setTimeout(step, pause);
      })();
    }

    function burn(myRun) {
      if (myRun !== run || (phase !== "writing" && phase !== "shown")) return;
      phase = "burning";
      burnDue = false;
      clear();
      fire.play(function () {
        if (myRun !== run) return;
        phase = "resting";
        index += 1;
        askEl.textContent = "";
        answerEl.textContent = "";
        timer = setTimeout(function () { write(myRun); }, 700);
      });
    }

    function start() { write(run); }
    function restart() {
      run += 1;
      clear();
      fire.stop();
      burnDue = false;
      write(run);
    }
    function burnNow() { burn(run); }
    function setVisible(isVisible) {
      visible = isVisible;
      if (visible && burnDue && phase === "shown") burn(run);
    }
    return { start: start, restart: restart, burnNow: burnNow, setVisible: setVisible };
  })();

  // MARK: Fire

  // A seeded generator and smoothed lattice noise, as in the app.
  function rng(seed) {
    var s = seed >>> 0;
    return function () {
      s = (s + 0x6d2b79f5) >>> 0;
      var t = Math.imul(s ^ (s >>> 15), 1 | s);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function noise(seed, spacing) {
    // An integer hash per lattice point: no allocation, so lighting the fire doesn't stall.
    function lattice(x, y) {
      var h = (Math.imul(x, 374761393) + Math.imul(y, 668265263) + Math.imul(seed, 2246822519)) | 0;
      h = Math.imul(h ^ (h >>> 13), 1274126177);
      return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
    }
    return function (x, y) {
      var gx = Math.floor(x / spacing), gy = Math.floor(y / spacing);
      var fx = (x % spacing) / spacing, fy = (y % spacing) / spacing;
      var sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
      var top = lattice(gx, gy) + (lattice(gx + 1, gy) - lattice(gx, gy)) * sx;
      var bottom = lattice(gx, gy + 1) + (lattice(gx + 1, gy + 1) - lattice(gx, gy + 1)) * sx;
      return top + (bottom - top) * sy;
    };
  }

  var fire = (function () {
    var CELL = 4;
    var DURATION = 1150;
    var MARGIN = 40;     // canvas room left, right and above the sheet, for sparks
    var FLOOR = 46;      // canvas room below the sheet, where the ash settles
    var paperEl = sheet.parentNode; // carries the sheet's shadow
    var ashCanvas = document.querySelector("[data-ash]");
    var frame = null, ashFrame = null, fadeTimer = null, ashTimer = null;
    var tmp = document.createElement("canvas");
    var small = document.createElement("canvas"); // the glow, at a third of the cell size
    // One spark, drawn once: a hot core fading through orange to nothing.
    var spark = (function () {
      var c = document.createElement("canvas");
      c.width = c.height = 32;
      var g = c.getContext("2d");
      var grad = g.createRadialGradient(16, 16, 0, 16, 16, 16);
      grad.addColorStop(0, "rgba(255,216,128,1)");
      grad.addColorStop(0.5, "rgba(255,102,26,0.6)");
      grad.addColorStop(1, "rgba(204,38,0,0)");
      g.fillStyle = grad;
      g.fillRect(0, 0, 32, 32);
      return c;
    })();

    function clamp(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

    function field(width, height, seed) {
      var cols = Math.max(2, Math.ceil(width / CELL));
      var rows = Math.max(2, Math.ceil(height / CELL));
      var random = rng(seed);
      var ignitions = [
        [cols * (0.15 + 0.2 * random()), rows + 4],
        [cols * (0.65 + 0.25 * random()), rows + 10]
      ];
      var coarse = noise(seed + 1, 18), fine = noise(seed + 2, 5);
      var times = new Float32Array(cols * rows);
      var lo = Infinity, hi = -Infinity;
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          var distance = Infinity;
          for (var i = 0; i < 2; i++) {
            var dx = ignitions[i][0] - c, dy = (ignitions[i][1] - r) * 1.15;
            distance = Math.min(distance, Math.sqrt(dx * dx + dy * dy));
          }
          var t = distance / (rows + cols / 3) + 0.32 * (0.7 * coarse(c, r) + 0.3 * fine(c, r));
          times[r * cols + c] = t;
          if (t < lo) lo = t;
          if (t > hi) hi = t;
        }
      }
      for (var k = 0; k < times.length; k++) times[k] = (times[k] - lo) / (hi - lo || 1);

      function cell() {
        var c = Math.floor(random() * cols), r = Math.floor(random() * rows);
        return { x: c * CELL, y: r * CELL, lit: times[r * cols + c] };
      }
      // Sparks rise from the burning edge; flakes of ash fall from it and settle below.
      var embers = [];
      for (var e = 0; e < 70; e++) {
        var ec = cell();
        embers.push({ x: ec.x, y: ec.y, lit: ec.lit, rise: 40 + random() * 80, drift: -14 + random() * 28,
                      radius: 0.8 + random() * 1.4, phase: random() * 6 });
      }
      var flakes = [];
      for (var a = 0; a < 54; a++) {
        var fc = cell();
        var points = [], sides = 4 + Math.floor(random() * 3);
        for (var v = 0; v < sides; v++) points.push(0.55 + random() * 0.45);
        flakes.push({ x0: fc.x, y0: fc.y, lit: fc.lit, size: 1.4 + random() * 3.4, points: points,
                      shade: random(), drift: -26 + random() * 52, speed: 170 + random() * 110,
                      flutter: 3 + random() * 6, phase: random() * 6, spin: -5 + random() * 10,
                      angle: random() * 6.28, rest: random(), ember: random() < 0.22,
                      start: null, landedAt: null, x: 0, y: 0 });
      }
      return { cols: cols, rows: rows, times: times, embers: embers, flakes: flakes };
    }

    // The desk the paper burns away to: the first solid background up the tree.
    function pageColor() {
      var sources = [document.body, document.documentElement];
      for (var i = 0; i < sources.length; i++) {
        var m = getComputedStyle(sources[i]).backgroundColor.match(/[\d.]+/g);
        if (m && m.length >= 3 && (m.length < 4 || +m[3] >= 1)) return [+m[0], +m[1], +m[2]];
      }
      return [233, 222, 198];
    }

    // One moment of the burn: where the paper is gone the desk shows through (painted in
    // the page's own color), with scorch, char and the glowing edge on what is left.
    function draw(ctx, f, p, w, h, page) {
      // One cell of padding all round, copying the edge, so the blurred cover reaches past
      // the sheet's edge instead of leaving a thin rim of paper.
      var pc = f.cols + 2, pr = f.rows + 2;
      var img = f.img || (f.img = ctx.createImageData(pc, pr));
      var glow = f.glow || (f.glow = ctx.createImageData(pc, pr));
      var px = img.data, gl = glow.data;
      gl.fill(0);
      for (var i = 0; i < pc * pr; i++) {
        var cc = Math.min(f.cols - 1, Math.max(0, (i % pc) - 1));
        var cr = Math.min(f.rows - 1, Math.max(0, Math.floor(i / pc) - 1));
        var d = f.times[cr * f.cols + cc] - p; // > 0: not burned yet
        var o = i * 4;
        var gone = 1 - clamp((d + 0.006) / 0.018);
        var r = page[0] * gone, g = page[1] * gone, b = page[2] * gone, a = gone, ca;
        var remains = 1 - gone;
        ca = remains * 0.28 * (1 - clamp((d - 0.07) / 0.12)); // browning
        if (ca > 0) { r = 115 * ca + r * (1 - ca); g = 64 * ca + g * (1 - ca); b = 20 * ca + b * (1 - ca); a = ca + a * (1 - ca); }
        ca = remains * 0.9 * (1 - clamp((d - 0.018) / 0.07)); // char
        if (ca > 0) { r = 33 * ca + r * (1 - ca); g = 18 * ca + g * (1 - ca); b = 8 * ca + b * (1 - ca); a = ca + a * (1 - ca); }
        ca = d > -0.012 ? 1 - clamp(d / 0.028) : 0; // the burning edge
        if (ca > 0) {
          var heat = clamp(1 - d / 0.028);
          var fr = 255, fg = 255 * (0.35 + 0.55 * heat), fb = 255 * (0.08 + 0.4 * heat * heat);
          r = fr * ca + r * (1 - ca); g = fg * ca + g * (1 - ca); b = fb * ca + b * (1 - ca); a = ca + a * (1 - ca);
          gl[o] = fr; gl[o + 1] = fg; gl[o + 2] = fb; gl[o + 3] = 255 * ca;
        }
        // ImageData is not premultiplied.
        if (a > 0) { px[o] = r / a; px[o + 1] = g / a; px[o + 2] = b / a; px[o + 3] = a * 255; }
        else { px[o + 3] = 0; }
      }
      var tctx = tmp.getContext("2d"); // sized once per burn, in play()
      var cw = w / f.cols, ch = h / f.rows; // one cell, in canvas points
      var x0 = MARGIN - cw, y0 = MARGIN - ch, ww = w + 2 * cw, hh = h + 2 * ch;
      ctx.imageSmoothingEnabled = true;
      tctx.putImageData(img, 0, 0);
      // Upscaling the cell image with smoothing softens its edges; no per-frame blur filter.
      ctx.drawImage(tmp, x0, y0, ww, hh);
      // The glow: shrunk onto a small canvas and stretched back, which blurs it for free.
      tctx.putImageData(glow, 0, 0);
      var gctx = small.getContext("2d");
      gctx.clearRect(0, 0, small.width, small.height);
      gctx.imageSmoothingEnabled = true;
      gctx.drawImage(tmp, 0, 0, small.width, small.height);
      ctx.globalCompositeOperation = "lighter";
      ctx.drawImage(small, x0 - 6, y0 - 6, ww + 12, hh + 12);
      ctx.globalAlpha = 0.6;
      ctx.drawImage(tmp, x0, y0, ww, hh);
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = "source-over";

      var life = 0.22;
      for (var s = 0; s < f.embers.length; s++) {
        var em = f.embers[s];
        if (p <= em.lit || p >= em.lit + life) continue;
        var age = (p - em.lit) / life;
        var x = MARGIN + em.x + em.drift * age + Math.sin(em.phase + age * 9) * 3;
        var y = MARGIN + em.y - em.rise * age;
        var rad = em.radius * (1 - age * 0.5) * 4;
        if (!isFinite(x) || !isFinite(y) || !(rad > 0)) continue;
        ctx.globalAlpha = 1 - age;
        ctx.drawImage(spark, x - rad, y - rad, rad * 2, rad * 2);
      }
      ctx.globalAlpha = 1;
    }

    // Ash: each flake drifts down from where the fire passed it and comes to rest on the
    // floor below the sheet; a few keep a dying ember for a moment. Returns true while any fall.
    function drawAsh(ctx, f, p, now, h) {
      var floor = MARGIN + h + 12;
      var falling = false;
      for (var i = 0; i < f.flakes.length; i++) {
        var fl = f.flakes[i];
        if (fl.start === null) {
          if (p < fl.lit) { falling = true; continue; }
          fl.start = now;
        }
        if (fl.landedAt === null) {
          var dt = (now - fl.start) / 1000;
          fl.x = MARGIN + fl.x0 + fl.drift * dt + Math.sin(fl.phase + dt * 4) * fl.flutter;
          fl.y = MARGIN + fl.y0 + fl.speed * dt + 260 * dt * dt;
          fl.angle += fl.spin * Math.min(0.05, (now - (fl.last || now)) / 1000);
          fl.last = now;
          var rest = floor + fl.rest * 10;
          if (fl.y >= rest) { fl.y = rest; fl.landedAt = now; } else falling = true;
        }
        var shade = fl.shade < 0.45 ? 34 + fl.shade * 60 : 110 + fl.shade * 60;
        ctx.save();
        ctx.translate(fl.x, fl.y);
        ctx.rotate(fl.angle);
        ctx.beginPath();
        for (var v = 0; v < fl.points.length; v++) {
          var ang = (v / fl.points.length) * Math.PI * 2;
          var rr = fl.size * fl.points[v];
          if (v === 0) ctx.moveTo(Math.cos(ang) * rr, Math.sin(ang) * rr * 0.7);
          else ctx.lineTo(Math.cos(ang) * rr, Math.sin(ang) * rr * 0.7);
        }
        ctx.closePath();
        ctx.fillStyle = "rgba(" + shade + "," + (shade - 6) + "," + (shade - 12) + ",0.88)";
        ctx.fill();
        if (fl.ember) {
          var glowLeft = fl.landedAt === null ? 1 : clamp(1 - (now - fl.landedAt) / 1600);
          if (glowLeft > 0) {
            ctx.fillStyle = "rgba(255," + Math.round(110 + 60 * glowLeft) + ",40," + (0.85 * glowLeft) + ")";
            ctx.beginPath(); ctx.arc(0, 0, fl.size * 0.45, 0, Math.PI * 2); ctx.fill();
            falling = true; // keep animating until the ember dies
          }
        }
        ctx.restore();
      }
      return falling;
    }

    // Reassigning a canvas's size reallocates it even when unchanged, so only on a change.
    function size(c, w, h, dpr) {
      var cw = Math.round((w + MARGIN * 2) * dpr), chh = Math.round((h + MARGIN + FLOOR) * dpr);
      if (c.width !== cw || c.height !== chh) { c.width = cw; c.height = chh; }
      var ctx = c.getContext("2d");
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, cw, chh);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      return ctx;
    }

    function clearAsh() {
      if (ashFrame) cancelAnimationFrame(ashFrame);
      clearTimeout(ashTimer);
      ashFrame = ashTimer = null;
      if (!ashCanvas) return;
      // Back to opaque at once: a fade-in here would hide the next burn's first flakes.
      ashCanvas.style.transition = "none";
      ashCanvas.classList.remove("fading");
      void ashCanvas.offsetWidth;
      ashCanvas.style.transition = "";
      ashCanvas.getContext("2d").clearRect(0, 0, ashCanvas.width, ashCanvas.height);
    }

    function stop() {
      if (frame) cancelAnimationFrame(frame);
      frame = null;
      clearTimeout(fadeTimer);
      fadeTimer = null;
      clearAsh();
      paperEl.classList.remove("burning");
      sheet.style.transition = "";
      sheet.style.opacity = "1";
      canvas.getContext("2d").clearRect(0, 0, canvas.width, canvas.height);
    }

    var ready = null;
    function sizeKey(w, h) { return Math.round(w) + "x" + Math.round(h); }
    function fitScratch(f) {
      var pc = f.cols + 2, pr = f.rows + 2;
      if (tmp.width !== pc || tmp.height !== pr) { tmp.width = pc; tmp.height = pr; }
      var sw = Math.max(2, Math.round(pc / 3)), sh = Math.max(2, Math.round(pr / 3));
      if (small.width !== sw || small.height !== sh) { small.width = sw; small.height = sh; }
    }

    // While a finished letter waits, do the slow parts of lighting it: build its burn field,
    // size the fire canvas and paint one invisible frame, so the first click doesn't stutter.
    function prepare() {
      if (reduceMotion) return;
      var idle = window.requestIdleCallback || function (cb) { return setTimeout(cb, 200); };
      idle(function () {
        if (frame) return;
        var rect = sheet.getBoundingClientRect();
        var w = rect.width, h = rect.height, k = sizeKey(w, h);
        if (!w || !h || (ready && ready.key === k)) return;
        var f = field(w, h, (Math.random() * 1e9) | 0);
        fitScratch(f);
        var dpr = Math.min(window.devicePixelRatio || 1, 2);
        var ctx = size(canvas, w, h, dpr);
        if (ashCanvas && !ashFrame && !ashTimer) size(ashCanvas, w, h, dpr); // only while no ash lies there
        draw(ctx, f, -1, w, h, pageColor());
        ctx.clearRect(0, 0, w + MARGIN * 2, h + MARGIN + FLOOR);
        ready = { key: k, f: f };
      });
    }

    function play(done) {
      stop();
      if (reduceMotion) {
        sheet.style.transition = "opacity .3s ease";
        sheet.style.opacity = "0";
        fadeTimer = setTimeout(function () { fadeTimer = null; sheet.style.transition = ""; done(); }, 320);
        return;
      }
      var rect = sheet.getBoundingClientRect();
      var w = rect.width, h = rect.height;
      var dpr = Math.min(window.devicePixelRatio || 1, 2);
      var ctx = size(canvas, w, h, dpr);
      var ashCtx = ashCanvas ? size(ashCanvas, w, h, dpr) : null;
      // A field prepared while the letter waited, if it still fits; flakes and sparks carry
      // state, so each field burns once.
      var f = ready && ready.key === sizeKey(w, h) ? ready.f : field(w, h, (Math.random() * 1e9) | 0);
      ready = null;
      var page = pageColor();
      fitScratch(f);
      paperEl.classList.add("burning"); // the shadow goes with the paper
      var start = performance.now();
      var p = -0.04;

      // While the fire burns, flakes are drawn on the fire canvas, in front of the burned-away
      // area they fall through; afterwards on the ash canvas, behind the next letter.
      function ash(target, now) {
        if (!target) return false;
        if (target === ashCtx) ashCtx.clearRect(0, 0, w + MARGIN * 2, h + MARGIN + FLOOR);
        return drawAsh(target, f, p, now, h);
      }

      (function tick(now) {
        var t = Math.min((now - start) / DURATION, 1);
        p = -0.04 + 1.12 * Math.pow(t, 1.35);
        ctx.clearRect(0, 0, w + MARGIN * 2, h + MARGIN + FLOOR);
        draw(ctx, f, p, w, h, page);
        ash(ctx, now);
        if (t < 1) { frame = requestAnimationFrame(tick); return; }
        frame = null;
        sheet.style.opacity = "0";
        paperEl.classList.remove("burning");
        ctx.clearRect(0, 0, w + MARGIN * 2, h + MARGIN + FLOOR);
        done();
        // The ash keeps falling, then lies on the floor a while before it fades.
        if (!ashCtx) return;
        (function settle(now2) {
          if (ash(ashCtx, now2)) { ashFrame = requestAnimationFrame(settle); return; }
          ashFrame = null;
          ashTimer = setTimeout(function () {
            ashCanvas.classList.add("fading");
            ashTimer = setTimeout(clearAsh, 2600);
          }, 4500);
        })(performance.now());
      })(start);
    }

    return { play: play, stop: stop, prepare: prepare };
  })();

  if (burnButton) burnButton.addEventListener("click", function () { letter.burnNow(); });
  // Off-screen, the letter finishes writing but waits to burn until it is seen again.
  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (entries) {
      letter.setVisible(entries[0].isIntersecting);
    }).observe(sheet);
  }
  document.addEventListener("keydown", function (event) { if (event.key === "Escape") letter.burnNow(); });

  letter.start();
})();
