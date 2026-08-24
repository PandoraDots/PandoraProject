/* Pandora Inferno — força tokens CSS no WhatsApp Web (sobrevive a redefinições do WA). */
(function () {
  "use strict";

  var ACCENT = "#cc3333";
  var BUBBLE = "#4a0a0a";

  var VARS = {
    "--WDS-accent": ACCENT,
    "--WDS-accent-rgb": "204, 51, 51",
    "--WDS-primary": ACCENT,
    "--WDS-brand": ACCENT,
    "--WDS-green": ACCENT,
    "--WDS-green-rgb": "204, 51, 51",
    "--wa-sysColor-primary": ACCENT,
    "--green": ACCENT,
    "--green-rgb": "204, 51, 51",
    "--teal": ACCENT,
    "--teal-lighter": "#e65555",
    "--teal-light": "#ff6666",
    "--button-primary-background": ACCENT,
    "--button-primary-background-hover": "#e65555",
    "--button-primary": "#ffffff",
    "--button-round-background": ACCENT,
    "--checkbox": ACCENT,
    "--switch-button-checked-color": ACCENT,
    "--icon-ack": ACCENT,
    "--icon-accent": ACCENT,
    "--icon-pinned": ACCENT,
    "--unread-marker-background": ACCENT,
    "--unread-marker-text": "#ffffff",
    "--ptt-green": ACCENT,
    "--ptt-green-rgb": "204, 51, 51",
    "--audio-progress-outgoing": ACCENT,
    "--audio-progress-played-outgoing": "#e65555",
    "--progress-primary": ACCENT,
    "--typing": ACCENT,
    "--highlight": ACCENT,
    "--input-border-active": ACCENT,
    "--focus": ACCENT,
    "--active-tab-marker": ACCENT,
    "--chat-marker": ACCENT,
    "--status-primary": ACCENT,
    "--outgoing-background": BUBBLE,
    "--outgoing-background-rgb": "74, 10, 10",
    "--outgoing-background-deeper": "#2e0505",
    "--outgoing-background-deeper-rgb": "46, 5, 5",
    "--outgoing-background-highlight": "#6a1515",
    "--msg-out-0": BUBBLE,
    "--msg-out-0-rgb": "74, 10, 10",
    "--msg-out-1": "#2e0505",
    "--msg-out-1-rgb": "46, 5, 5",
    "--msg-ack": ACCENT,
    "--incoming-background": "#121212",
    "--incoming-background-rgb": "18, 18, 18",
    "--incoming-background-deeper": "#0a0a0a",
    "--background-default": "#000000",
    "--background-default-active": "#1a0a0a",
    "--background-default-hover": "#140808",
    "--app-background": "#000000",
    "--app-background-deeper": "#000000",
    "--intro-background": "#000000",
    "--conversation-panel-background": "#000000",
    "--panel-background": "#0a0a0a",
    "--panel-background-lighter": "#0a0a0a",
    "--panel-background-colored": "#0a0a0a",
    "--panel-background-colored-deeper": "#000000",
    "--panel-header-background": "#0a0a0a",
    "--drawer-background": "#000000",
    "--drawer-section-background": "#0a0a0a",
    "--compose-panel-background": "#0a0a0a",
    "--compose-input-background": "#121212",
    "--search-input-background": "#121212",
    "--search-container-background": "#000000",
    "--filters-container-background": "#000000",
    "--filters-item-background-active": ACCENT,
    "--filters-item-color-active": "#ffffff",
    "--chip-button-background-active": ACCENT,
    "--chip-button-foreground-active": "#ffffff",
    "--primary": "#ffffff",
    "--primary-strong": "#ffffff",
    "--primary-stronger": "#ffffff",
    "--secondary": "#cccccc",
    "--text-primary": "#ffffff",
    "--text-secondary": "#dddddd",
    "--message-primary": "#ffffff",
  };

  var GREEN_HEX = {
    "#005c4b": 1,
    "#005C4B": 1,
    "#00a884": 1,
    "#00A884": 1,
    "#25d366": 1,
    "#25D366": 1,
    "#21c063": 1,
    "#21C063": 1,
    "#1db356": 1,
    "#1aa34e": 1,
    "#027e5b": 1,
    "#054740": 1,
    "#1da851": 1,
  };

  function isGreenish(rgb) {
    var m = String(rgb || "").match(/rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/i);
    if (!m) return false;
    var r = +m[1],
      g = +m[2],
      b = +m[3];
    return g > r + 20 && g > b && g > 70 && r < 100;
  }

  function roots() {
    return [document.documentElement, document.body, document.getElementById("app")].filter(
      Boolean
    );
  }

  function applyVars() {
    roots().forEach(function (el) {
      Object.keys(VARS).forEach(function (k) {
        el.style.setProperty(k, VARS[k], "important");
      });
    });
  }

  function paintChips() {
    document
      .querySelectorAll(
        '#side [aria-pressed="true"], #side [aria-selected="true"], [role="tab"][aria-selected="true"], button[aria-pressed="true"]'
      )
      .forEach(function (el) {
        el.style.setProperty("background-color", ACCENT, "important");
        el.style.setProperty("background", ACCENT, "important");
        el.style.setProperty("color", "#ffffff", "important");
        el.style.setProperty("border-color", ACCENT, "important");
      });
  }

  function paintBubbles() {
    document.querySelectorAll("#main .message-out, #main div.message-out, #main [class*='message-out']").forEach(function (el) {
      el.style.setProperty("--outgoing-background", BUBBLE, "important");
      var kids = el.querySelectorAll(":scope > div, :scope > div > div");
      for (var i = 0; i < Math.min(kids.length, 8); i++) {
        var cs = window.getComputedStyle(kids[i]);
        if (isGreenish(cs.backgroundColor) || GREEN_HEX[cs.backgroundColor]) {
          kids[i].style.setProperty("background-color", BUBBLE, "important");
          kids[i].style.setProperty("background", BUBBLE, "important");
        }
      }
    });
  }

  function paintLinks() {
    document.querySelectorAll("#main a, #app a, #main [role='link']").forEach(function (el) {
      var cs = window.getComputedStyle(el);
      if (isGreenish(cs.color) || GREEN_HEX[cs.color]) {
        el.style.setProperty("color", ACCENT, "important");
      }
    });
  }

  function paintIcons() {
    var sels = [
      '[data-icon="msg-dblcheck"] svg path',
      '[data-icon="msg-dblcheck-ack"] svg path',
      '[data-icon="msg-check"] svg path',
      '[data-icon="status-v3-unread"] svg path',
      '[data-icon="ptt"] svg path',
      '[data-icon="audio-play"] svg path',
      '[data-icon="audio-pause"] svg path',
      '[data-icon="mic"] svg path',
      '[data-icon="send"] svg path',
      "footer span[data-icon] svg path",
      "#app svg path",
    ];
    var nodes = document.querySelectorAll(sels.join(","));
    var n = Math.min(nodes.length, 400);
    for (var i = 0; i < n; i++) {
      var el = nodes[i];
      var cs = window.getComputedStyle(el);
      var fill = cs.fill;
      var stroke = cs.stroke;
      var attrFill = (el.getAttribute("fill") || "").toLowerCase();
      if (
        isGreenish(fill) ||
        GREEN_HEX[fill] ||
        GREEN_HEX[attrFill] ||
        attrFill.indexOf("25d366") >= 0 ||
        attrFill.indexOf("00a884") >= 0 ||
        attrFill.indexOf("21c063") >= 0 ||
        attrFill.indexOf("005c4b") >= 0
      ) {
        el.style.setProperty("fill", ACCENT, "important");
      }
      if (isGreenish(stroke) || GREEN_HEX[stroke]) {
        el.style.setProperty("stroke", ACCENT, "important");
      }
    }
  }

  function paintResidualGreen() {
    paintBubbles();
    paintLinks();
    paintIcons();
    var sels = [
      '#main [data-testid="msg-container"] > div > div',
      "#side span",
      "footer span",
      "#main span",
    ];
    var nodes = document.querySelectorAll(sels.join(","));
    var n = Math.min(nodes.length, 300);
    for (var i = 0; i < n; i++) {
      var el = nodes[i];
      var cs = window.getComputedStyle(el);
      var bg = cs.backgroundColor;
      if (isGreenish(bg)) {
        el.style.setProperty("background-color", BUBBLE, "important");
        el.style.setProperty("background", BUBBLE, "important");
        el.style.setProperty("color", "#ffffff", "important");
      }
      var color = cs.color;
      if (isGreenish(color) && (el.tagName === "SPAN" || el.tagName === "P" || el.tagName === "A")) {
        el.style.setProperty("color", ACCENT, "important");
      }
    }
  }

  var scheduled = false;
  function scheduleLight() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(function () {
      scheduled = false;
      applyVars();
      paintChips();
      paintBubbles();
      paintLinks();
    });
  }

  function tickHeavy() {
    applyVars();
    paintChips();
    paintResidualGreen();
  }

  tickHeavy();
  document.addEventListener("DOMContentLoaded", tickHeavy);
  window.addEventListener("load", tickHeavy);

  new MutationObserver(scheduleLight).observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["style", "class", "aria-pressed", "aria-selected", "fill"],
  });

  setInterval(tickHeavy, 1500);
})();
