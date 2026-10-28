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
      if (reduceMotion) {
        // No motion, no cycling: the letter stays until the reader burns it.
        render(text, true);
        phase = "shown";
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
    var cache = {};
    function lattice(x, y) {
      var key = x + "," + y;
      if (cache[key] === undefined) cache[key] = rng((x * 7919 + y * 104729 + seed) | 0)();
      return cache[key];
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
    var MARGIN = 40; // the canvas reaches past the sheet, for sparks
    var frame = null;

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
          var n = 0.7 * coarse(c, r) + 0.3 * fine(c, r);
          var t = distance / (rows + cols / 3) + 0.32 * n;
          times[r * cols + c] = t;
          if (t < lo) lo = t;
          if (t > hi) hi = t;
        }
      }
      for (var k = 0; k < times.length; k++) times[k] = (times[k] - lo) / (hi - lo || 1);
      var embers = [];
      for (var e = 0; e < 70; e++) {
        var ec = Math.floor(random() * cols), er = Math.floor(random() * rows);
        embers.push({ x: ec * CELL, y: er * CELL, lit: times[er * cols + ec], rise: 40 + random() * 80,
                      drift: -14 + random() * 28, radius: 0.8 + random() * 1.4, phase: random() * 6 });
      }
      return { cols: cols, rows: rows, times: times, embers: embers };
    }

    var tmp = document.createElement("canvas");
    var fadeTimer = null;
    // Safari before 18 has no canvas filter; the glow then gets a soft halo drawn by hand.
    var canFilter = typeof document.createElement("canvas").getContext("2d").filter === "string";

    // Paints one moment of the burn: the sheet is masked where the paper is gone, and the
    // canvas carries the scorch, char and glowing edge on what is left, plus the sparks.
    function draw(ctx, f, p, offX, offY, w, h) {
      // One set of buffers per burn, cleared each frame.
      var img = f.img || (f.img = ctx.createImageData(f.cols, f.rows));
      var glow = f.glow || (f.glow = ctx.createImageData(f.cols, f.rows));
      var mask = f.mask || (f.mask = ctx.createImageData(f.cols, f.rows));
      var px = img.data, gl = glow.data, mk = mask.data;
      px.fill(0); gl.fill(0); mk.fill(0);
      for (var i = 0; i < f.times.length; i++) {
        var d = f.times[i] - p; // > 0: not burned yet
        var o = i * 4;
        mk[o + 3] = 255 * clamp((d + 0.006) / 0.018);
        var r = 0, g = 0, b = 0, a = 0, ca;
        var remains = d >= -0.006; // browning and char only on paper that is still there
        // Painted from the outside in: browning, char, then the burning edge on top.
        ca = remains ? 0.28 * (1 - clamp((d - 0.07) / 0.12)) : 0;
        if (ca > 0) { r = 115 * ca; g = 64 * ca; b = 20 * ca; a = ca; }
        ca = remains ? 0.9 * (1 - clamp((d - 0.018) / 0.07)) : 0;
        if (ca > 0) { r = 33 * ca + r * (1 - ca); g = 18 * ca + g * (1 - ca); b = 8 * ca + b * (1 - ca); a = ca + a * (1 - ca); }
        ca = d > -0.012 ? 1 - clamp(d / 0.028) : 0;
        if (ca > 0) {
          var heat = clamp(1 - d / 0.028);
          var fr = 255, fg = 255 * (0.35 + 0.55 * heat), fb = 255 * (0.08 + 0.4 * heat * heat);
          r = fr * ca + r * (1 - ca); g = fg * ca + g * (1 - ca); b = fb * ca + b * (1 - ca); a = ca + a * (1 - ca);
          gl[o] = fr; gl[o + 1] = fg; gl[o + 2] = fb; gl[o + 3] = 255 * ca;
        }
        // ImageData is not premultiplied.
        if (a > 0) { px[o] = r / a; px[o + 1] = g / a; px[o + 2] = b / a; px[o + 3] = a * 255; }
      }
      tmp.width = f.cols; tmp.height = f.rows;
      var tctx = tmp.getContext("2d");
      tctx.putImageData(mask, 0, 0);
      var url = "url(" + tmp.toDataURL() + ")";
      sheet.style.webkitMaskImage = url; sheet.style.maskImage = url;
      ctx.imageSmoothingEnabled = true;
      tctx.putImageData(img, 0, 0);
      if (canFilter) ctx.filter = "blur(1.4px)";
      ctx.drawImage(tmp, offX, offY, w, h);
      tctx.putImageData(glow, 0, 0);
      ctx.globalCompositeOperation = "lighter";
      if (canFilter) {
        ctx.filter = "blur(7px)";
        ctx.drawImage(tmp, offX, offY, w, h);
        ctx.filter = "none";
      } else {
        // A halo from a few offset, faded copies.
        ctx.globalAlpha = 0.35;
        for (var k = 0; k < 4; k++) {
          var dx = (k % 2 ? 1 : -1) * 3, dy = (k < 2 ? 1 : -1) * 3;
          ctx.drawImage(tmp, offX + dx, offY + dy, w, h);
        }
        ctx.globalAlpha = 1;
      }
      ctx.globalCompositeOperation = "source-over";

      // Sparks leave from wherever the front passes.
      var life = 0.22;
      for (var s = 0; s < f.embers.length; s++) {
        var em = f.embers[s];
        if (p <= em.lit || p >= em.lit + life) continue;
        var age = (p - em.lit) / life;
        var x = offX + em.x * (w / (f.cols * CELL)) + em.drift * age + Math.sin(em.phase + age * 9) * 3;
        var y = offY + em.y * (h / (f.rows * CELL)) - em.rise * age;
        var rad = em.radius * (1 - age * 0.5) * 2;
        var grad = ctx.createRadialGradient(x, y, 0, x, y, rad * 2);
        grad.addColorStop(0, "rgba(255,216,128," + (1 - age) + ")");
        grad.addColorStop(0.5, "rgba(255,102,26," + (0.6 * (1 - age)) + ")");
        grad.addColorStop(1, "rgba(204,38,0,0)");
        ctx.fillStyle = grad;
        ctx.beginPath(); ctx.arc(x, y, rad * 2, 0, Math.PI * 2); ctx.fill();
      }
    }

    function clamp(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

    function unmask() { sheet.style.webkitMaskImage = sheet.style.maskImage = ""; }

    function stop() {
      if (frame) cancelAnimationFrame(frame);
      frame = null;
      clearTimeout(fadeTimer);
      fadeTimer = null;
      sheet.style.transition = "";
      sheet.style.opacity = "1";
      unmask();
      var ctx = canvas.getContext("2d");
      ctx.clearRect(0, 0, canvas.width, canvas.height);
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
      var dpr = Math.min(window.devicePixelRatio || 1, 2);
      var cw = rect.width + MARGIN * 2, ch = rect.height + MARGIN;
      canvas.width = Math.round(cw * dpr); canvas.height = Math.round(ch * dpr);
      var ctx = canvas.getContext("2d");
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      var f = field(rect.width, rect.height, (Math.random() * 1e9) | 0);
      sheet.style.webkitMaskSize = sheet.style.maskSize = "100% 100%";
      var start = performance.now();
      (function tick(now) {
        var t = Math.min((now - start) / DURATION, 1);
        var p = -0.04 + 1.12 * Math.pow(t, 1.35);
        ctx.clearRect(0, 0, cw, ch);
        draw(ctx, f, p, MARGIN, MARGIN, rect.width, rect.height);
        if (t < 1) { frame = requestAnimationFrame(tick); return; }
        sheet.style.opacity = "0";
        unmask();
        ctx.clearRect(0, 0, cw, ch);
        frame = null;
        done();
      })(start);
    }

    return { play: play, stop: stop };
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
