// ES5 only: older webOS engines do not support let/const or arrow functions.
var BASE = "/var/lib/webosbrew/wireguard";
var HB_SERVICE = "luna://org.webosbrew.hbchannel.service";
var POLL_MS = 5000;
var PUBLIC_IP_MS = 120000;

var I18N = {
  en: {
    connect: "Connect",
    disconnect: "Disconnect",
    connecting: "Connecting...",
    disconnecting: "Disconnecting...",
    install: "Install",
    startOnBoot: "Start on boot",
    killSwitch: "Kill switch",
    uploadConfig: "Upload config",
    details: "Details",
    back: "Back",
    scrollEnd: "End",

    server: "Server",
    handshake: "Handshake",
    received: "Received",
    sent: "Sent",
    publicIp: "Public IP",

    stConnected: "Connected",
    stDisconnected: "Disconnected",
    stConnecting: "Connecting",
    stRepairing: "Reconnecting",
    stBlocked: "Blocked by kill switch",
    stUnprotected: "VPN down: not protected",
    stFailed: "Connection failed",
    stNotInstalled: "Install required",
    ksRoutesSuffix: " (routes)",
    dnsNotRedirected: "DNS not protected",
    never: "never",

    leakTest: "Leak test",
    routes: "Routes",
    config: "Config",
    log: "Log",
    installUpdate: "Install / update",
    uninstall: "Uninstall",
    confirmUninstall: "Uninstall WireGuard?",
    cancel: "Cancel",

    uploadTitle: "Upload configuration",
    accessCode: "Access code",
    plainHttp: "Plain HTTP: home network only.",
    close: "Close",

    ready: "Ready",
    executing: "Running...",
    completed: "Completed",
    error: "Error",
    timeout: "Timeout",
    connected: "Connected",
    disconnected: "Disconnected",
    installingComponents: "Installing...",
    componentsInstalled: "Installed",
    uploadStarting: "Starting upload server...",
    uploadStarted: "Upload server started",
    uploadStopping: "Stopping upload server...",
    uploadStopped: "Upload server stopped",
    uploadStopError: "Error stopping upload server",
    bootOk: "Boot: connected",
    bootFailed: "Boot: connection failed",
    leakPass: "Leak test passed",
    leakWarn: "Leak test: warnings",
    leakFail: "Leak test failed",
    ksOnRoutes: "Kill switch on (routes)",

    serviceUnavailable:
      "ERROR: webOS.service.request is not available.\n\n" +
      "Check that this file exists:\n" +
      "lib/webOSTVjs-1.2.4/webOSTV.js",
    serviceUnavailableStatus: "Error: webOS service unavailable",
    hbTimeout: "TIMEOUT: no response from Homebrew service.",
    jsException: "JS EXCEPTION",
    lunaError: "luna-call ERROR"
  },

  es: {
    connect: "Conectar",
    disconnect: "Desconectar",
    connecting: "Conectando...",
    disconnecting: "Desconectando...",
    install: "Instalar",
    startOnBoot: "Iniciar al arrancar",
    killSwitch: "Kill switch",
    uploadConfig: "Subir config",
    details: "Detalles",
    back: "Volver",
    scrollEnd: "Fin",

    server: "Servidor",
    handshake: "Handshake",
    received: "Recibido",
    sent: "Enviado",
    publicIp: "IP pública",

    stConnected: "Conectado",
    stDisconnected: "Desconectado",
    stConnecting: "Conectando",
    stRepairing: "Reconectando",
    stBlocked: "Bloqueado por el kill switch",
    stUnprotected: "VPN caída: sin protección",
    stFailed: "Error de conexión",
    stNotInstalled: "Instalación necesaria",
    ksRoutesSuffix: " (rutas)",
    dnsNotRedirected: "DNS sin proteger",
    never: "nunca",

    leakTest: "Test de fugas",
    routes: "Rutas",
    config: "Config",
    log: "Log",
    installUpdate: "Instalar / actualizar",
    uninstall: "Desinstalar",
    confirmUninstall: "¿Desinstalar WireGuard?",
    cancel: "Cancelar",

    uploadTitle: "Subir configuración",
    accessCode: "Código de acceso",
    plainHttp: "HTTP sin cifrar: solo en tu red local.",
    close: "Cerrar",

    ready: "Listo",
    executing: "Ejecutando...",
    completed: "Completado",
    error: "Error",
    timeout: "Timeout",
    connected: "Conectado",
    disconnected: "Desconectado",
    installingComponents: "Instalando...",
    componentsInstalled: "Instalado",
    uploadStarting: "Arrancando servidor de subida...",
    uploadStarted: "Servidor de subida arrancado",
    uploadStopping: "Parando servidor de subida...",
    uploadStopped: "Servidor de subida parado",
    uploadStopError: "Error al parar subida",
    bootOk: "Arranque: conectado",
    bootFailed: "Arranque: error de conexión",
    leakPass: "Test de fugas superado",
    leakWarn: "Test de fugas: avisos",
    leakFail: "Test de fugas fallido",
    ksOnRoutes: "Kill switch activo (rutas)",

    serviceUnavailable:
      "ERROR: webOS.service.request no está disponible.\n\n" +
      "Comprueba que existe:\n" +
      "lib/webOSTVjs-1.2.4/webOSTV.js",
    serviceUnavailableStatus: "Error: servicio webOS no disponible",
    hbTimeout: "TIMEOUT: sin respuesta del servicio Homebrew.",
    jsException: "EXCEPCIÓN JS",
    lunaError: "ERROR luna-call"
  },

  tr: {
    connect: "Bağlan",
    disconnect: "Bağlantıyı kes",
    connecting: "Bağlanıyor...",
    disconnecting: "Bağlantı kesiliyor...",
    install: "Kur",
    startOnBoot: "Açılışta başlat",
    killSwitch: "Kill Switch",
    uploadConfig: "Yapılandırma yükle",
    details: "Ayrıntılar",
    back: "Geri",
    scrollEnd: "Son",

    server: "Sunucu",
    handshake: "El sıkışma",
    received: "Alınan",
    sent: "Gönderilen",
    publicIp: "Genel IP",

    stConnected: "Bağlı",
    stDisconnected: "Bağlı değil",
    stConnecting: "Bağlanıyor",
    stRepairing: "Yeniden bağlanıyor",
    stBlocked: "Kill Switch engelliyor",
    stUnprotected: "VPN kapalı: korumasız",
    stFailed: "Bağlantı kurulamadı",
    stNotInstalled: "Kurulum gerekli",
    ksRoutesSuffix: " (rotalar)",
    dnsNotRedirected: "DNS korunmuyor",
    never: "hiç",

    leakTest: "Sızıntı testi",
    routes: "Rotalar",
    config: "Yapılandırma",
    log: "Günlük",
    installUpdate: "Kur / güncelle",
    uninstall: "Kaldır",
    confirmUninstall: "WireGuard kaldırılsın mı?",
    cancel: "İptal",

    uploadTitle: "Yapılandırmayı yükle",
    accessCode: "Erişim kodu",
    plainHttp: "Şifresiz HTTP: yalnızca ev ağında.",
    close: "Kapat",

    ready: "Hazır",
    executing: "Çalışıyor...",
    completed: "Tamamlandı",
    error: "Hata",
    timeout: "Zaman aşımı",
    connected: "Bağlı",
    disconnected: "Bağlı değil",
    installingComponents: "Kuruluyor...",
    componentsInstalled: "Kuruldu",
    uploadStarting: "Yükleme sunucusu başlatılıyor...",
    uploadStarted: "Yükleme sunucusu başladı",
    uploadStopping: "Yükleme sunucusu durduruluyor...",
    uploadStopped: "Yükleme sunucusu durdu",
    uploadStopError: "Yükleme sunucusu durdurulamadı",
    bootOk: "Açılış: bağlandı",
    bootFailed: "Açılış: bağlantı kurulamadı",
    leakPass: "Sızıntı testi geçti",
    leakWarn: "Sızıntı testi: uyarılar",
    leakFail: "Sızıntı testi başarısız",
    ksOnRoutes: "Kill Switch açık (rotalar)",

    serviceUnavailable:
      "HATA: webOS.service.request kullanılamıyor.\n\n" +
      "Bu dosyanın var olduğunu kontrol edin:\n" +
      "lib/webOSTVjs-1.2.4/webOSTV.js",
    serviceUnavailableStatus: "Hata: webOS servisi kullanılamıyor",
    hbTimeout: "ZAMAN AŞIMI: Homebrew servisi yanıt vermedi.",
    jsException: "JS HATASI",
    lunaError: "luna-call HATASI"
  }
};

var currentLang = "en";
var installed = false;
var currentState = "stopped";
var actionBusy = false;
var toggleBusy = false;
var pollTimer = null;
var pollBusy = false;
var publicIp = "";
var publicIpAt = 0;
var publicIpBusy = false;
var publicIpState = "";
var bootShown = false;
var firstSummary = true;

// ------------------------------------------------------------------ language

function langFromLocale(locale) {
  var l = String(locale || "").toLowerCase();
  if (l.indexOf("es") === 0) return "es";
  if (l.indexOf("tr") === 0) return "tr";
  return "en";
}

function t(key) {
  return (I18N[currentLang] && I18N[currentLang][key]) || I18N.en[key] || key;
}

function applyLanguage() {
  document.documentElement.lang = currentLang;
  var nodes = document.querySelectorAll("[data-i18n]");
  for (var i = 0; i < nodes.length; i++) {
    nodes[i].textContent = t(nodes[i].getAttribute("data-i18n"));
  }
}

function setLanguage(lang) {
  if (!I18N[lang]) lang = "en";
  if (lang === currentLang) return;
  currentLang = lang;
  applyLanguage();
  renderSummary(lastSummary);
}

// The TV UI language: navigator.language first, then the webOS settings
// service, which some firmware versions report more reliably.
function detectLanguage() {
  currentLang = langFromLocale(navigator.language || navigator.userLanguage || "en");
  if (!serviceAvailable()) return;
  try {
    webOS.service.request("luna://com.webos.settingsservice", {
      method: "getSystemSettings",
      parameters: { category: "option", keys: ["localeInfo"] },
      onSuccess: function(res) {
        var ui =
          res && res.settings && res.settings.localeInfo &&
          res.settings.localeInfo.locales && res.settings.localeInfo.locales.UI;
        if (ui) setLanguage(langFromLocale(ui));
      },
      onFailure: function() {}
    });
  } catch (e) {}
}

// ------------------------------------------------------------------ output

function setStatus(text) {
  var lines = document.querySelectorAll(".status-line");
  for (var i = 0; i < lines.length; i++) lines[i].textContent = text || "";
}

function print(text) {
  var el = document.getElementById("out");
  if (el) {
    el.textContent = text || "";
    el.scrollTop = 0;
  }
}

function append(text) {
  var el = document.getElementById("out");
  if (el) el.textContent += "\n" + (text || "");
}

function scrollOutput(direction) {
  var el = document.getElementById("out");
  if (el) el.scrollTop += direction * 300;
}

function scrollOutputToEnd() {
  var el = document.getElementById("out");
  if (el) el.scrollTop = el.scrollHeight;
}

function decodeBase64Maybe(value) {
  if (!value) return "";
  try {
    return atob(value);
  } catch (e) {
    return "";
  }
}

function formatResponse(res) {
  var out = "";

  if (res.stdoutString) {
    out += res.stdoutString;
  } else if (res.stdoutBytes) {
    out += decodeBase64Maybe(res.stdoutBytes);
  }

  if (res.stderrString) {
    out += "\nSTDERR:\n" + res.stderrString;
  } else if (res.stderrBytes) {
    var stderr = decodeBase64Maybe(res.stderrBytes);
    if (stderr) out += "\nSTDERR:\n" + stderr;
  }

  if (!out) out = JSON.stringify(res, null, 2);
  return out;
}

// ------------------------------------------------------------------ service

function serviceAvailable() {
  return (
    typeof webOS !== "undefined" &&
    webOS.service &&
    typeof webOS.service.request === "function"
  );
}

// quiet: background polling, never touches the output box or status line.
function execCommand(command, callback, timeoutMs, quiet) {
  timeoutMs = timeoutMs || 20000;

  if (!serviceAvailable()) {
    var msg = t("serviceUnavailable");
    if (!quiet) {
      print(msg);
      setStatus(t("serviceUnavailableStatus"));
    }
    if (callback) callback(false, msg);
    return;
  }

  var finished = false;
  var timer = setTimeout(function() {
    if (!finished) {
      finished = true;
      var msg = t("hbTimeout");
      if (!quiet) {
        append("\n\n" + msg);
        setStatus(t("timeout"));
      }
      if (callback) callback(false, msg);
    }
  }, timeoutMs);

  try {
    webOS.service.request(HB_SERVICE, {
      method: "exec",
      parameters: { command: command },
      onSuccess: function(res) {
        if (finished) return;
        finished = true;
        clearTimeout(timer);
        if (callback) callback(true, formatResponse(res), res);
      },
      onFailure: function(err) {
        if (finished) return;
        finished = true;
        clearTimeout(timer);
        if (callback) callback(false, t("lunaError") + ":\n" + JSON.stringify(err, null, 2), err);
      }
    });
  } catch (e) {
    finished = true;
    clearTimeout(timer);
    if (callback) callback(false, t("jsException") + ":\n" + e.message + "\n\n" + (e.stack || ""), e);
  }
}

function run(command, label, timeoutMs, done) {
  setStatus(t("executing"));
  print("Running:\n" + (label || command) + "\n\nWaiting for response...");

  var wrappedCommand =
    "( " + command + " ) 2>&1; " +
    "RC=$?; " +
    "echo; echo COMMAND_RC=$RC; " +
    "exit 0";

  execCommand(wrappedCommand, function(ok, out) {
    print(out);
    var commandOk = ok && out.indexOf("COMMAND_RC=0") !== -1;
    setStatus(commandOk ? t("completed") : t("error"));
    if (done) done(commandOk, out);
  }, timeoutMs || 20000);
}

// ------------------------------------------------------------------ status card

var lastSummary = {};

function parseKv(text) {
  var result = {};
  var lines = String(text || "").split("\n");
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\r$/, "");
    var eq = line.indexOf("=");
    if (eq > 0) result[line.substring(0, eq)] = line.substring(eq + 1);
  }
  return result;
}

function isActiveState(state) {
  return (
    state === "up" || state === "starting" || state === "repairing" ||
    state === "blocked" || state === "down-unprotected"
  );
}

function formatBytes(value) {
  var n = parseFloat(value);
  if (isNaN(n)) return "-";
  var units = ["B", "KiB", "MiB", "GiB", "TiB"];
  var i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n = n / 1024;
    i++;
  }
  return (i === 0 ? String(Math.round(n)) : n.toFixed(1)) + " " + units[i];
}

function formatAge(seconds) {
  if (isNaN(seconds) || seconds < 0) return "-";
  if (seconds < 60) return seconds + " s";
  if (seconds < 3600) return Math.floor(seconds / 60) + " min";
  if (seconds < 86400) return Math.floor(seconds / 3600) + " h";
  return Math.floor(seconds / 86400) + " d";
}

function setText(id, text) {
  var el = document.getElementById(id);
  if (el) el.textContent = text;
}

function stateView(state) {
  switch (state) {
    case "up": return { label: "stConnected", css: "state-up" };
    case "starting": return { label: "stConnecting", css: "state-busy" };
    case "repairing": return { label: "stRepairing", css: "state-busy" };
    case "blocked": return { label: "stBlocked", css: "state-alert" };
    case "down-unprotected": return { label: "stUnprotected", css: "state-alert" };
    case "failed": return { label: "stFailed", css: "state-alert" };
    default: return { label: "stDisconnected", css: "state-stopped" };
  }
}

function renderSummary(s) {
  s = s || {};
  var card = document.getElementById("statusCard");
  var view;

  if (!installed) {
    view = { label: "stNotInstalled", css: "state-alert" };
  } else {
    view = stateView(currentState);
  }
  if (card) card.className = "card " + view.css;
  setText("stateText", t(view.label));

  var badge = document.getElementById("stateBadge");
  var badgeText = "";
  if (installed && isActiveState(currentState)) {
    if (String(s.detail || "").indexOf("dns-not-redirected") !== -1) badgeText = t("dnsNotRedirected");
  }
  if (badge) {
    badge.textContent = badgeText;
    badge.className = badgeText ? "badge" : "badge hidden";
  }

  var server = s.server || "";
  if (!server && s.endpoint) server = s.endpoint.replace(/:\d+$/, "");
  setText("vServer", server || "-");

  var running = s.running === "1";
  var hs = parseInt(s.handshake, 10);
  var now = parseInt(s.now, 10);
  if (running && hs > 0 && now > 0) setText("vHandshake", formatAge(now - hs));
  else setText("vHandshake", running ? t("never") : "-");
  setText("vRx", running ? formatBytes(s.rx) : "-");
  setText("vTx", running ? formatBytes(s.tx) : "-");
  setText("vPublicIp", publicIp || "-");
  setText("ksLabel", t("killSwitch") + (s.killswitch === "routes" ? t("ksRoutesSuffix") : ""));

  var btn = document.getElementById("connectBtn");
  if (btn && !actionBusy) {
    if (!installed) {
      setText("connectLbl", t("install"));
      btn.className = "primary connect";
    } else if (isActiveState(currentState)) {
      setText("connectLbl", t("disconnect"));
      btn.className = "primary connect disconnect";
    } else {
      setText("connectLbl", t("connect"));
      btn.className = "primary connect";
    }
  }

  if (!toggleBusy) {
    var auto = document.getElementById("autostartToggle");
    var ks = document.getElementById("killswitchToggle");
    if (auto) {
      auto.checked = s.autostart === "1";
      auto.disabled = !installed;
    }
    if (ks) {
      ks.checked = s.ks_setting === "1";
      ks.disabled = !installed;
    }
  }
}

function summaryCommand() {
  return (
    "if [ -x " + BASE + "/scripts/summary.sh ]; then " +
    BASE + "/scripts/summary.sh; " +
    "else echo installed=0; fi"
  );
}

function refreshPublicIp(force) {
  if (publicIpBusy || !installed) return;
  var now = new Date().getTime();
  if (!force && now - publicIpAt < PUBLIC_IP_MS) return;
  publicIpBusy = true;
  publicIpAt = now;
  execCommand(BASE + "/scripts/summary.sh pubip", function(ok, out) {
    publicIpBusy = false;
    var kv = parseKv(out);
    publicIp = ok && kv.pubip ? kv.pubip : "";
    setText("vPublicIp", publicIp || "-");
  }, 30000, true);
}

function showBootResult(s) {
  if (bootShown) return;
  bootShown = true;
  if (s.autostart !== "1" || !s.boot_result) return;
  setStatus(s.boot_result === "ok" ? t("bootOk") : t("bootFailed"));
}

function refreshSummary() {
  if (pollBusy) return;
  pollBusy = true;
  execCommand(summaryCommand(), function(ok, out) {
    pollBusy = false;
    if (!ok) return;
    var s = parseKv(out);
    installed = s.installed === "1";
    var previous = currentState;
    currentState = installed ? (s.state || "stopped") : "stopped";
    lastSummary = s;
    renderSummary(s);
    if (installed) {
      if (firstSummary) showBootResult(s);
      refreshPublicIp(firstSummary || currentState !== publicIpState || previous !== currentState);
      publicIpState = currentState;
    }
    firstSummary = false;
  }, 10000, true);
}

function pageHidden() {
  return !!(document.hidden || document.webkitHidden);
}

function startPolling() {
  if (pollTimer) return;
  refreshSummary();
  pollTimer = setInterval(refreshSummary, POLL_MS);
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

function onVisibilityChange() {
  if (pageHidden()) stopPolling();
  else startPolling();
}

// ------------------------------------------------------------------ actions

function toggleConnection() {
  if (actionBusy) return;
  if (!installed) {
    installComponents();
    return;
  }

  var disconnecting = isActiveState(currentState);
  var btn = document.getElementById("connectBtn");
  actionBusy = true;
  if (btn) setText("connectLbl", disconnecting ? t("disconnecting") : t("connecting"));
  if (!disconnecting) {
    currentState = "starting";
    renderSummary(lastSummary);
  }

  run(
    BASE + (disconnecting ? "/scripts/stop.sh" : "/scripts/start.sh"),
    disconnecting ? t("disconnect") : t("connect"),
    90000,
    function(ok) {
      actionBusy = false;
      if (ok) setStatus(disconnecting ? t("disconnected") : t("connected"));
      publicIpAt = 0;
      refreshSummary();
    }
  );
}

function installComponents() {
  var cmd =
    "APPID='com.github.cfernande1470.wireguard'; " +
    "echo 'Installing/updating WireGuard components...'; " +
    "echo; echo '== whoami / id =='; " +
    "id 2>&1 || true; " +
    "echo; echo '== app locations =='; " +
    "INSTALL=''; " +
    "for d in " +
      "/media/developer/apps/usr/palm/applications/$APPID " +
      "/media/cryptofs/apps/usr/palm/applications/$APPID " +
      "/media/internal/apps/usr/palm/applications/$APPID; do " +
      "echo \"checking: $d\"; " +
      "if [ -f \"$d/payload/wireguard/install.sh\" ]; then " +
        "INSTALL=\"$d/payload/wireguard/install.sh\"; " +
        "break; " +
      "fi; " +
    "done; " +
    "if [ -z \"$INSTALL\" ]; then " +
      "echo; echo '== fallback search =='; " +
      "INSTALL=$(find /media -type f -path '*/com.github.cfernande1470.wireguard/payload/wireguard/install.sh' 2>/dev/null | head -1); " +
    "fi; " +
    "if [ -z \"$INSTALL\" ]; then " +
      "echo 'ERROR: cannot find payload/wireguard/install.sh'; " +
      "echo; echo '== matching files =='; " +
      "find /media -path '*com.github.cfernande1470.wireguard*' 2>/dev/null | head -120; " +
      "echo; echo 'INSTALL_RC=1'; " +
      "exit 0; " +
    "fi; " +
    "echo; echo \"found installer: $INSTALL\"; " +
    "echo; echo '== running installer =='; " +
    "sh \"$INSTALL\" 2>&1; " +
    "RC=$?; " +
    "echo; echo \"INSTALL_RC=$RC\"; " +
    "exit 0";

  actionBusy = true;
  setStatus(t("installingComponents"));
  print("Running:\n" + t("installUpdate") + "\n\nWaiting for response...");

  execCommand(cmd, function(ok, out) {
    actionBusy = false;
    print(out);
    var installOk = ok && out.indexOf("INSTALL_RC=0") !== -1;
    setStatus(installOk ? t("componentsInstalled") : t("error"));
    refreshSummary();
  }, 60000);
}

function leakTest() {
  run(BASE + "/scripts/leaktest.sh", t("leakTest"), 60000, function(ok, out) {
    if (out.indexOf("RESULT=PASS") !== -1) setStatus(t("leakPass"));
    else if (out.indexOf("RESULT=WARN") !== -1) setStatus(t("leakWarn"));
    else setStatus(t("leakFail"));
  });
}

function showRoutes() {
  run(
    "echo '== routes =='; " +
    "ip route; " +
    "echo; echo '== IPv6 routes =='; " +
    "ip -6 route 2>&1 || true; " +
    "echo; echo '== route get 1.1.1.1 =='; " +
    "ip route get 1.1.1.1 2>&1 || true; " +
    "echo; echo '== resolver =='; " +
    "cat /etc/resolv.conf 2>&1 || true",
    t("routes"),
    30000
  );
}

function showConfig() {
  run(
    "echo '== wg0.conf =='; " +
    "sed -E 's#^(PrivateKey[[:space:]]*=[[:space:]]*).*#\\1REDACTED#;s#^(PresharedKey[[:space:]]*=[[:space:]]*).*#\\1REDACTED#' " +
    BASE + "/conf/wg0.conf 2>/dev/null || true; " +
    "echo; echo '== address =='; " +
    "cat " + BASE + "/conf/address 2>/dev/null || true; " +
    "echo; echo '== DNS =='; " +
    "cat " + BASE + "/conf/dns 2>/dev/null || echo '(from wg0.conf or the last upload)'; " +
    "echo; echo '== autostart =='; " +
    BASE + "/scripts/autostart.sh status 2>&1 || true; " +
    "echo; echo '== kill switch =='; " +
    BASE + "/scripts/killswitch.sh status 2>&1 | grep -v '^KILLSWITCH=' || true",
    t("config"),
    30000
  );
}

function showLog() {
  run(
    "echo '== watchdog.log =='; " +
    "tail -60 " + BASE + "/run/watchdog.log 2>/dev/null || true; " +
    "echo; echo '== wireguard-go.log =='; " +
    "tail -80 " + BASE + "/run/wireguard-go.log 2>/dev/null || true; " +
    "echo; echo '== autostart.log =='; " +
    "tail -80 " + BASE + "/run/autostart.log 2>/dev/null || true; " +
    "echo; echo '== upload.log =='; " +
    "tail -40 " + BASE + "/run/wg-upload.log 2>/dev/null || true",
    t("log"),
    30000
  );
}

function toggleAutostart() {
  var toggle = document.getElementById("autostartToggle");
  var enable = toggle && toggle.checked;
  toggleBusy = true;
  run(BASE + "/scripts/autostart.sh " + (enable ? "enable" : "disable"), t("startOnBoot"), 15000, function() {
    toggleBusy = false;
    refreshSummary();
  });
}

function toggleKillswitch() {
  var toggle = document.getElementById("killswitchToggle");
  var enable = toggle && toggle.checked;
  toggleBusy = true;
  run(BASE + "/scripts/killswitch.sh " + (enable ? "enable" : "disable"), t("killSwitch"), 30000, function(ok, out) {
    toggleBusy = false;
    if (enable && out.indexOf("routes only") !== -1) setStatus(t("ksOnRoutes"));
    refreshSummary();
  });
}

// ------------------------------------------------------------------ screens

function focusElement(id) {
  setTimeout(function() {
    var el = document.getElementById(id);
    if (el) el.focus();
  }, 50);
}

function detailsVisible() {
  var details = document.getElementById("detailsScreen");
  return details && details.className.indexOf("hidden") === -1;
}

function showDetails() {
  document.getElementById("mainScreen").className = "screen hidden";
  document.getElementById("detailsScreen").className = "screen";
  focusElement("leakBtn");
}

function showMain() {
  document.getElementById("detailsScreen").className = "screen hidden";
  document.getElementById("mainScreen").className = "screen";
  focusElement("detailsBtn");
}

function askUninstall() {
  var modal = document.getElementById("confirmModal");
  if (modal) modal.className = "modal";
  focusElement("confirmCancel");
}

function closeConfirm() {
  var modal = document.getElementById("confirmModal");
  if (modal) modal.className = "modal hidden";
  focusElement("leakBtn");
}

function confirmUninstall() {
  var modal = document.getElementById("confirmModal");
  if (modal) modal.className = "modal hidden";
  focusElement("leakBtn");
  run(BASE + "/scripts/uninstall.sh", t("uninstall"), 45000, function() {
    refreshSummary();
  });
}

// ------------------------------------------------------------------ upload

function uploadStart() {
  setStatus(t("uploadStarting"));
  print("Running:\n" + t("uploadConfig") + "\n\nWaiting for response...");

  execCommand(BASE + "/scripts/upload-start.sh", function(ok, out) {
    print(out);
    var started = ok && out.indexOf("CODE:") !== -1;
    setStatus(started ? t("uploadStarted") : t("error"));
    if (started) showUploadPopup(out);
  }, 30000);
}

function showUploadPopup(output) {
  var modal = document.getElementById("uploadModal");
  var urlEl = document.getElementById("uploadUrl");
  var pinEl = document.getElementById("uploadPin");
  var qrEl = document.getElementById("uploadQr");

  if (!modal || !urlEl || !pinEl) return;

  var urlMatch = output.match(/URL:\s*(http:\/\/[^\s]+)/i);
  var pinMatch = output.match(/CODE:\s*([0-9a-f]{8})/i);
  var url = urlMatch ? urlMatch[1] : "";

  urlEl.textContent = url || "-";
  pinEl.textContent = pinMatch ? pinMatch[1] : "--------";

  modal.className = "modal";

  if (qrEl) {
    var scale = Math.max(4, Math.round((window.innerWidth || 1920) / 240));
    var drawn = url && typeof QR !== "undefined" && QR.draw(qrEl, url, scale);
    qrEl.className = drawn ? "qr" : "qr hidden";
  }

  setTimeout(function() {
    var btn = modal.querySelector("button");
    if (btn) btn.focus();
  }, 200);
}

function closeUploadPopup() {
  var modal = document.getElementById("uploadModal");
  if (modal) modal.className = "modal hidden";

  setStatus(t("uploadStopping"));

  execCommand(BASE + "/scripts/upload-stop.sh", function(ok, out) {
    print(out);
    setStatus(ok ? t("uploadStopped") : t("uploadStopError"));
    focusElement("uploadBtn");
  }, 15000);
}

// ------------------------------------------------------------------ remote control

function remoteKeyCode(event) {
  if (event && typeof event.keyCode === "number" && event.keyCode) return event.keyCode;
  if (event && typeof event.which === "number") return event.which;
  if (event && event.key) {
    var keys = {
      ArrowLeft: 37,
      ArrowUp: 38,
      ArrowRight: 39,
      ArrowDown: 40,
      Enter: 13,
      Escape: 27,
      GoBack: 461
    };
    return keys[event.key] || 0;
  }
  return 0;
}

function visibleModal() {
  var modals = document.querySelectorAll(".modal");
  for (var i = 0; i < modals.length; i++) {
    if (modals[i].className.indexOf("hidden") === -1) return modals[i];
  }
  return null;
}

function remoteFocusableElements() {
  var modal = visibleModal();
  var root = modal || document;
  var elements = root.querySelectorAll("button, input[type=checkbox]");
  var focusable = [];

  for (var i = 0; i < elements.length; i++) {
    var element = elements[i];
    if (element.disabled) continue;
    if (element.offsetWidth === 0 || element.offsetHeight === 0) continue;
    focusable.push(element);
  }

  return focusable;
}

// A toggle is laid out by its label box, not by the small checkbox in it.
function focusRect(element) {
  var box = element.parentNode;
  if (element.tagName === "INPUT" && box && String(box.className).indexOf("toggle-box") !== -1) {
    return box.getBoundingClientRect();
  }
  return element.getBoundingClientRect();
}

function moveRemoteFocus(direction) {
  var elements = remoteFocusableElements();
  if (!elements.length) return false;

  var current = document.activeElement;
  if (elements.indexOf(current) === -1) {
    elements[0].focus();
    return true;
  }

  var currentRect = focusRect(current);
  var currentX = currentRect.left + currentRect.width / 2;
  var currentY = currentRect.top + currentRect.height / 2;
  var best = null;
  var bestScore = Infinity;

  for (var i = 0; i < elements.length; i++) {
    var candidate = elements[i];
    if (candidate === current) continue;

    var rect = focusRect(candidate);
    var dx = rect.left + rect.width / 2 - currentX;
    var dy = rect.top + rect.height / 2 - currentY;
    var primary = direction === "left" || direction === "right" ? dx : dy;
    var cross = direction === "left" || direction === "right" ? dy : dx;

    if (
      (direction === "left" && primary >= -2) ||
      (direction === "right" && primary <= 2) ||
      (direction === "up" && primary >= -2) ||
      (direction === "down" && primary <= 2)
    ) {
      continue;
    }

    // Prefer controls that share the row (left/right) or column (up/down);
    // others stay reachable with a penalty. Near ties go to the control
    // that comes first (left, top).
    var horizontal = direction === "left" || direction === "right";
    var overlap = horizontal
      ? rect.top < currentRect.bottom && rect.bottom > currentRect.top
      : rect.left < currentRect.right && rect.right > currentRect.left;
    if (horizontal && !overlap) continue;
    var score = Math.abs(primary) + (overlap ? 0 : 1000 + Math.abs(cross) * 2);
    if (score < bestScore - 4) {
      best = candidate;
      bestScore = score;
    }
  }

  if (!best) return false;
  best.focus();
  if (typeof best.scrollIntoView === "function") {
    try {
      best.scrollIntoView({ block: "nearest", inline: "nearest" });
    } catch (e) {
      // Older webOS browsers only support the boolean scrollIntoView argument.
      best.scrollIntoView(false);
    }
  }
  return true;
}

function handleBack(event) {
  var modal = visibleModal();
  if (modal) {
    event.preventDefault();
    if (modal.id === "uploadModal") closeUploadPopup();
    else if (modal.id === "confirmModal") closeConfirm();
    return;
  }
  if (detailsVisible()) {
    event.preventDefault();
    showMain();
    return;
  }
  if (typeof webOS !== "undefined" && webOS.platformBack) {
    event.preventDefault();
    webOS.platformBack();
  }
}

function handleRemoteKey(event) {
  var code = remoteKeyCode(event);

  if (code === 461 || code === 27) {
    handleBack(event);
    return;
  }

  if (code === 13) {
    var active = document.activeElement;
    if (
      active &&
      (active.tagName === "BUTTON" ||
        (active.tagName === "INPUT" && active.type === "checkbox"))
    ) {
      event.preventDefault();
      active.click();
    }
    return;
  }

  var directions = { 37: "left", 38: "up", 39: "right", 40: "down" };
  var direction = directions[code];
  if (!direction) return;

  if (moveRemoteFocus(direction)) {
    event.preventDefault();
    event.stopPropagation();
  }
}

// :focus-within is missing on older webOS engines; mirror it with a class.
function trackToggleFocus(event, focused) {
  var target = event.target;
  if (!target || target.tagName !== "INPUT") return;
  var box = target.parentNode;
  if (!box || !box.className || box.className.indexOf("toggle-box") === -1) return;
  box.className = focused ? "toggle-box focused" : "toggle-box";
}

// ------------------------------------------------------------------ start

window.onerror = function(message, source, lineno, colno, error) {
  print(
    "JS ERROR:\n" +
    message + "\n" +
    "line: " + lineno + ":" + colno + "\n" +
    (error && error.stack ? error.stack : "")
  );
  setStatus("JS error");
};

window.onload = function() {
  detectLanguage();
  applyLanguage();
  renderSummary({});
  setStatus("");

  document.addEventListener("keydown", handleRemoteKey, false);
  document.addEventListener("focus", function(e) { trackToggleFocus(e, true); }, true);
  document.addEventListener("blur", function(e) { trackToggleFocus(e, false); }, true);
  document.addEventListener("visibilitychange", onVisibilityChange, false);
  document.addEventListener("webkitvisibilitychange", onVisibilityChange, false);
  document.addEventListener("webOSRelaunch", function() {
    if (!pageHidden()) startPolling();
    refreshSummary();
  }, false);

  if (!pageHidden()) startPolling();
  focusElement("connectBtn");
};
