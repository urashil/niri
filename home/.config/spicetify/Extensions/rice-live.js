// rice-live: applies the wallpaper palette (rice-colors.css, rewritten by matugen / spotify-theme) to Spotify without restarting it.
(function rice() {
  if (!Spicetify || !Spicetify.Platform) { setTimeout(rice, 300); return; }
  let last = "";
  async function tick() {
    try {
      const css = await (await fetch("rice-colors.css?" + Date.now(), { cache: "no-store" })).text();
      if (css && css !== last) {
        last = css;
        let s = document.getElementById("rice-live");
        if (!s) { s = document.createElement("style"); s.id = "rice-live"; document.head.appendChild(s); }
        s.textContent = css;
      }
    } catch (e) { /* the file is only there once spotify-theme has run */ }
  }
  tick();
  setInterval(tick, 1500);
})();
