// Visionneuse du support de cours en lecture seule (images WebP, pas de PDF publié).
(function () {
  function init() {
    var root = document.getElementById("slide-viewer");
    if (!root || root.dataset.ready) return;
    root.dataset.ready = "1";

    var total = parseInt(root.dataset.total, 10);
    var base = root.dataset.base;
    var img = root.querySelector(".sv-img");
    var input = root.querySelector(".sv-input");
    var current = 1;

    function src(n) {
      return base + "slide-" + String(n).padStart(3, "0") + ".webp";
    }

    function show(n) {
      current = Math.min(Math.max(n, 1), total);
      img.src = src(current);
      img.alt = "Diapositive " + current + " sur " + total;
      input.value = current;
      if (current < total) new Image().src = src(current + 1);
    }

    root.querySelector(".sv-prev").addEventListener("click", function () { show(current - 1); });
    root.querySelector(".sv-next").addEventListener("click", function () { show(current + 1); });
    root.querySelector(".sv-first").addEventListener("click", function () { show(1); });
    root.querySelector(".sv-full").addEventListener("click", function () {
      if (document.fullscreenElement) document.exitFullscreen();
      else if (root.requestFullscreen) root.requestFullscreen();
    });
    input.addEventListener("change", function () { show(parseInt(input.value, 10) || 1); });

    root.addEventListener("keydown", function (e) {
      if (e.target === input) return;
      if (e.key === "ArrowRight" || e.key === "PageDown" || e.key === " ") { show(current + 1); e.preventDefault(); }
      if (e.key === "ArrowLeft" || e.key === "PageUp") { show(current - 1); e.preventDefault(); }
      if (e.key === "Home") { show(1); e.preventDefault(); }
      if (e.key === "End") { show(total); e.preventDefault(); }
    });

    // Dissuasion (pas une protection absolue) : pas de clic droit ni de glisser-déposer.
    root.addEventListener("contextmenu", function (e) { e.preventDefault(); });
    img.addEventListener("dragstart", function (e) { e.preventDefault(); });

    root.querySelector(".sv-total").textContent = total;
    input.max = total;
    show(1);
  }

  if (window.document$) window.document$.subscribe(init);
  else document.addEventListener("DOMContentLoaded", init);
})();
