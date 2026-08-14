(function () {
  "use strict";

  var EXPERT_ROUTE = "/effects/equalizers/expert";
  var EXPERT_WIDTH = 1060;
  var EXPERT_HEIGHT = 820;
  var state = {
    type: null,
    preset: null,
    presets: [],
    response: null,
    saveTimer: null,
    panel: null,
    layoutMode: null
  };

  function getBridge() {
    return new Promise(function (resolve, reject) {
      if (window.WebViewJavascriptBridge) {
        resolve(window.WebViewJavascriptBridge);
        return;
      }
      if (window.WVJBCallbacks) {
        window.WVJBCallbacks.push(resolve);
        return;
      }
      window.WVJBCallbacks = [resolve];
      var iframe = document.createElement("iframe");
      iframe.style.display = "none";
      iframe.src = "https://__bridge_loaded__";
      document.documentElement.appendChild(iframe);
      setTimeout(function () {
        document.documentElement.removeChild(iframe);
      }, 0);
      setTimeout(function () {
        reject(new Error("Bridge loading timed out"));
      }, 5000);
    });
  }

  function call(method, path, data) {
    return getBridge().then(function (bridge) {
      return new Promise(function (resolve, reject) {
        bridge.callHandler(method + " " + path, data || {}, function (response) {
          if (response && response.error) {
            reject(new Error(response.error));
          } else {
            resolve(response ? response.data : null);
          }
        });
      });
    });
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }

  function debounceSave(fn) {
    clearTimeout(state.saveTimer);
    state.saveTimer = setTimeout(fn, 180);
  }

  function setStatus(text) {
    var status = state.panel && state.panel.querySelector(".eqm-expert-status");
    if (status) status.textContent = text || "";
  }

  function ensurePanel() {
    if (state.panel) return state.panel;
    var host = document.querySelector("eqm-equalizers");
    if (!host) return null;

    var panel = document.createElement("div");
    panel.className = "eqm-expert-panel";
    panel.innerHTML = [
      '<div class="eqm-expert-toolbar">',
      '<button data-action="collapse">-</button>',
      '<select data-field="preset"></select>',
      '<input data-field="global" type="number" min="-24" max="24" step="0.1" title="Global gain">',
      '<button data-action="auto">Auto gain</button>',
      '<button data-action="save">Save as</button>',
      '<button data-action="export">Export</button>',
      '<button data-action="import">Import</button>',
      '</div>',
      '<canvas class="eqm-expert-chart" width="900" height="210"></canvas>',
      '<div class="eqm-expert-row eqm-expert-head">',
      '<span>On</span><span>Color</span><span>Type</span><span>Freq</span><span>Gain</span><span>Q</span><span></span><span></span>',
      '</div>',
      '<div class="eqm-expert-list"></div>',
      '<button data-action="add" style="width:100%;margin-top:8px;">+ Add band</button>',
      '<div class="eqm-expert-status"></div>'
    ].join("");

    host.appendChild(panel);
    state.panel = panel;
    bindPanel(panel);
    return panel;
  }

  function bindPanel(panel) {
    panel.querySelector('[data-field="preset"]').addEventListener("change", function (event) {
      call("POST", EXPERT_ROUTE + "/presets/select", { id: event.target.value })
        .then(refreshExpert)
        .catch(function (error) { setStatus(error.message); });
    });
    panel.querySelector('[data-field="global"]').addEventListener("input", function (event) {
      var value = clamp(parseFloat(event.target.value) || 0, -24, 24);
      debounceSave(function () {
        call("POST", EXPERT_ROUTE + "/global", { global: value })
          .then(refreshExpert)
          .catch(function (error) { setStatus(error.message); });
      });
    });
    panel.querySelector('[data-action="auto"]').addEventListener("click", function () {
      call("POST", EXPERT_ROUTE + "/auto-gain", {})
        .then(refreshExpert)
        .catch(function (error) { setStatus(error.message); });
    });
    panel.querySelector('[data-action="add"]').addEventListener("click", function () {
      var count = state.preset && state.preset.bands ? state.preset.bands.length : 0;
      var frequency = Math.round(20 * Math.pow(1000, count / 99));
      call("POST", EXPERT_ROUTE + "/bands", {
        enabled: true,
        filterType: "PK",
        frequency: clamp(frequency, 20, 20000),
        gain: 0,
        q: 1,
        color: bandColor(count)
      }).then(refreshExpert).catch(function (error) { setStatus(error.message); });
    });
    panel.querySelector('[data-action="save"]').addEventListener("click", function () {
      var name = window.prompt("Preset name", state.preset ? state.preset.name : "Expert Preset");
      if (!name || !state.preset) return;
      call("POST", EXPERT_ROUTE + "/presets", {
        name: name,
        global: state.preset.global,
        bands: state.preset.bands,
        select: true
      }).then(refreshExpert).catch(function (error) { setStatus(error.message); });
    });
    panel.querySelector('[data-action="export"]').addEventListener("click", function () {
      call("GET", EXPERT_ROUTE + "/presets/export", {}).catch(function (error) { setStatus(error.message); });
    });
    panel.querySelector('[data-action="import"]').addEventListener("click", function () {
      call("GET", EXPERT_ROUTE + "/presets/import", {})
        .then(refreshExpert)
        .catch(function (error) { setStatus(error.message); });
    });
  }

  function bandColor(index) {
    var colors = ["#00E0A4", "#FFB020", "#FFE600", "#A7F432", "#1DFF42", "#15E67A", "#28D7F0", "#3E51FF", "#6B2CFF", "#FF4E6A"];
    return colors[index % colors.length];
  }

  function render() {
    var panel = ensurePanel();
    if (!panel) return;
    var isExpert = state.type === "Expert";
    panel.dataset.active = isExpert ? "true" : "false";
    if (!isExpert || !state.preset) return;
    applyExpertLayout();

    var presetSelect = panel.querySelector('[data-field="preset"]');
    presetSelect.innerHTML = state.presets.map(function (preset) {
      return '<option value="' + escapeHtml(preset.id) + '">' + escapeHtml(preset.name) + '</option>';
    }).join("");
    presetSelect.value = state.preset.id;
    panel.querySelector('[data-field="global"]').value = Number(state.preset.global || 0).toFixed(1);

    var list = panel.querySelector(".eqm-expert-list");
    list.innerHTML = state.preset.bands.map(renderBand).join("");
    list.querySelectorAll(".eqm-expert-row").forEach(function (row) {
      row.addEventListener("input", onBandInput);
      row.addEventListener("change", onBandInput);
      row.querySelector('[data-action="delete"]').addEventListener("click", onDeleteBand);
    });
    drawChart(panel.querySelector("canvas"));
  }

  function applyExpertLayout() {
    if (state.layoutMode === "expert") return;
    state.layoutMode = "expert";
    Promise.all([
      call("POST", "/ui/min-height", { minHeight: 420 }),
      call("POST", "/ui/max-height", { maxHeight: EXPERT_HEIGHT }),
      call("POST", "/ui/min-width", { minWidth: 430 }),
      call("POST", "/ui/max-width", { maxWidth: EXPERT_WIDTH })
    ]).then(function () {
      call("POST", "/ui/height", { height: EXPERT_HEIGHT }).catch(function () {});
      call("POST", "/ui/width", { width: EXPERT_WIDTH }).catch(function () {});
    }).catch(function () {});
  }

  function leaveExpertLayout() {
    if (state.layoutMode !== "expert") return;
    state.layoutMode = null;
    Promise.all([
      call("POST", "/ui/min-height", { minHeight: 180 }),
      call("POST", "/ui/max-height", { maxHeight: 820 }),
      call("POST", "/ui/min-width", { minWidth: 430 }),
      call("POST", "/ui/max-width", { maxWidth: 1060 })
    ]).then(function () {
      call("POST", "/ui/height", { height: 400 }).catch(function () {});
    }).catch(function () {});
  }

  function renderBand(band, index) {
    return [
      '<div class="eqm-expert-row" data-index="' + index + '">',
      '<input data-field="enabled" type="checkbox" ' + (band.enabled ? "checked" : "") + '>',
      '<input data-field="color" type="color" value="' + escapeHtml(band.color || bandColor(index)) + '">',
      '<select data-field="filterType">',
      option("PK", "PK", band.filterType),
      option("LS", "LS", band.filterType),
      option("HS", "HS", band.filterType),
      option("LP", "LP", band.filterType),
      option("HP", "HP", band.filterType),
      '</select>',
      '<input data-field="frequency" type="number" min="20" max="20000" step="1" value="' + Math.round(band.frequency) + '">',
      '<input data-field="gain" type="number" min="-24" max="24" step="0.1" value="' + Number(band.gain).toFixed(1) + '">',
      '<input data-field="q" type="number" min="0.1" max="24" step="0.01" value="' + Number(band.q).toFixed(2) + '">',
      '<input type="range" data-field="gainRange" min="-24" max="24" step="0.1" value="' + Number(band.gain).toFixed(1) + '">',
      '<button data-action="delete">-</button>',
      '</div>'
    ].join("");
  }

  function option(value, label, selected) {
    return '<option value="' + value + '"' + (selected === value ? " selected" : "") + '>' + label + '</option>';
  }

  function onBandInput(event) {
    var row = event.currentTarget;
    var index = parseInt(row.dataset.index, 10);
    if (event.target.dataset.field === "gainRange") {
      row.querySelector('[data-field="gain"]').value = event.target.value;
    }
    var band = readBand(row);
    state.preset.bands[index] = band;
    drawChart(state.panel.querySelector("canvas"));
    debounceSave(function () {
      call("POST", EXPERT_ROUTE + "/bands/update", { index: index, band: band })
        .then(refreshExpert)
        .catch(function (error) { setStatus(error.message); });
    });
  }

  function readBand(row) {
    return {
      enabled: row.querySelector('[data-field="enabled"]').checked,
      color: row.querySelector('[data-field="color"]').value,
      filterType: row.querySelector('[data-field="filterType"]').value,
      frequency: clamp(parseFloat(row.querySelector('[data-field="frequency"]').value) || 1000, 20, 20000),
      gain: clamp(parseFloat(row.querySelector('[data-field="gain"]').value) || 0, -24, 24),
      q: clamp(parseFloat(row.querySelector('[data-field="q"]').value) || 1, 0.1, 24)
    };
  }

  function onDeleteBand(event) {
    var index = parseInt(event.target.closest(".eqm-expert-row").dataset.index, 10);
    call("DELETE", EXPERT_ROUTE + "/bands", { index: index })
      .then(refreshExpert)
      .catch(function (error) { setStatus(error.message); });
  }

  function drawChart(canvas) {
    if (!canvas || !state.preset) return;
    var context = canvas.getContext("2d");
    var width = canvas.width;
    var height = canvas.height;
    context.clearRect(0, 0, width, height);
    context.fillStyle = "#142228";
    context.fillRect(0, 0, width, height);
    context.strokeStyle = "#29414a";
    context.lineWidth = 1;
    for (var i = 0; i <= 10; i++) {
      var x = (width * i) / 10;
      context.beginPath();
      context.moveTo(x, 0);
      context.lineTo(x, height);
      context.stroke();
    }
    for (var j = 0; j <= 6; j++) {
      var y = (height * j) / 6;
      context.beginPath();
      context.moveTo(0, y);
      context.lineTo(width, y);
      context.stroke();
    }
    drawCurve(context, width, height, state.preset.bands, "#e8eef0", true);
    state.preset.bands.forEach(function (band) {
      drawCurve(context, width, height, [band], band.color || "#00E0A4", false);
    });
  }

  function drawCurve(context, width, height, bands, color, includeGlobal) {
    context.strokeStyle = color;
    context.globalAlpha = includeGlobal ? 1 : 0.45;
    context.lineWidth = includeGlobal ? 2 : 1.5;
    context.beginPath();
    for (var x = 0; x < width; x++) {
      var frequency = 20 * Math.pow(1000, x / Math.max(1, width - 1));
      var gain = includeGlobal ? Number(state.preset.global || 0) : 0;
      bands.forEach(function (band) {
        gain += responseGain(frequency, band);
      });
      var y = height / 2 - (clamp(gain, -24, 24) / 24) * (height / 2 - 10);
      if (x === 0) context.moveTo(x, y);
      else context.lineTo(x, y);
    }
    context.stroke();
    context.globalAlpha = 1;
  }

  function responseGain(frequency, band) {
    if (!band.enabled) return 0;
    var ratio = Math.max(frequency, 20) / Math.max(band.frequency, 20);
    var distance = Math.log(ratio) / Math.log(2);
    var width = Math.max(0.05, 1 / Math.max(0.1, band.q));
    if (band.filterType === "LS") return band.gain / (1 + Math.pow(2, distance / width));
    if (band.filterType === "HS") return band.gain / (1 + Math.pow(2, -distance / width));
    if (band.filterType === "LP") return -24 * Math.max(0, distance / width);
    if (band.filterType === "HP") return -24 * Math.max(0, -distance / width);
    return band.gain / (1 + Math.pow(distance / width, 2));
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, function (char) {
      return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char];
    });
  }

  function refreshExpert() {
    return Promise.all([
      call("GET", EXPERT_ROUTE + "/presets", {}),
      call("GET", EXPERT_ROUTE + "/presets/selected", {})
    ]).then(function (values) {
      state.presets = values[0] || [];
      state.preset = values[1];
      setStatus(state.preset ? state.preset.bands.length + " bands" : "");
      render();
    });
  }

  function tick() {
    ensurePanel();
    call("GET", "/effects/equalizers/type", {})
      .then(function (data) {
        var nextType = data && data.type;
        if (nextType !== state.type) {
          state.type = nextType;
          if (state.type === "Expert") {
            applyExpertLayout();
            refreshExpert();
          } else {
            leaveExpertLayout();
            render();
          }
        }
      })
      .catch(function () {});
  }

  function start() {
    ensurePanel();
    setInterval(tick, 500);
    tick();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
