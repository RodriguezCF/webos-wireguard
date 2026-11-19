# WireGuard for LG webOS Homebrew

[English](#english) · [Español](#español) · [Türkçe](#türkçe)

---

# English

A WireGuard client for rooted LG webOS TVs using Homebrew Channel.

This project provides a simple webOS app that can install, configure, start, stop and monitor a WireGuard VPN tunnel on LG webOS. It uses WireGuard in userspace through `wireguard-go`, because LG webOS stock kernels usually do not include the WireGuard kernel module.

The app is designed for rooted TVs with Homebrew Channel installed.

---

## Features

- WireGuard userspace tunnel using `wireguard-go`
- Bundled `wg`, `wireguard-go` and `wg-upload` binaries
- TV-friendly webOS interface
- English, Spanish and Turkish UI
- Manual **Install / update** workflow
- No automatic payload installation on app launch
- Temporary web upload server for `wg0.conf`
- Time-limited configuration upload protected by a random access code and failed-attempt lockout
- One-button Connect / Disconnect with a live status card
- Tunnel DNS: the TV resolver uses the DNS servers from your config while the VPN is up
- Optional kill switch (off by default)
- IPv6 leak protection on every interface
- Watchdog that repairs the tunnel after TV standby, Wi-Fi reconnects and network changes
- Leak test, routes, config and log in a Details screen
- Optional autostart on boot, with retries
- Runtime uninstall action

---

## Why userspace WireGuard?

On normal Linux systems, WireGuard usually runs as a kernel module.

On LG webOS TVs, the WireGuard kernel module is normally not available in the stock kernel. For that reason, this project uses:

- `wireguard-go` to create the WireGuard interface in userspace
- `wg` from `wireguard-tools` to configure the tunnel
- a TUN interface created from userspace

This makes it possible to run WireGuard without building or installing a custom webOS kernel.

---

## Requirements

- Rooted LG webOS TV
- Homebrew Channel installed
- Homebrew root service available
- `/dev/net/tun` support on the TV
- Compatible CPU architecture

The bundled binaries in the current release are built for:

```text
linux/armv7 (32-bit ARM)
```

Check your TV architecture with:

```sh
uname -m
```

The bundled ARMv7 binaries also run on supported 64-bit LG TVs.

---

## Installation

### 1. Download or build the IPK

Release package:

```text
com.github.cfernande1470.wireguard_1.1.0_all.ipk
```

To package manually:

```sh
make package
```

Packaging requires `ares-package` from either LG's `@webos-tools/cli` or
webOSBrew's `ares-cli-rs`. Set `ARES_PACKAGE=/path/to/ares-package` when it is
not available on `PATH`. The package is forced to architecture `all` because
the bundled ARMv7 binaries run on both 32-bit and 64-bit TVs.

Output:

```text
dist/com.github.cfernande1470.wireguard_1.1.0_all.ipk
```

### 2. Install using Homebrew Channel

Copy or upload the IPK to your TV and install it from Homebrew Channel.

### 3. Open the app

After launching the app, press **Install** (the main button shows Install until the components are prepared;
later updates use **Details > Install / update**).

This prepares persistent state under:

```text
/var/lib/webosbrew/wireguard
```

The packaged binaries and scripts stay inside the application directory. The state directory only contains the
configuration, logs, runtime files, and symlinks to the packaged payload, so updates take effect without duplicating
the binaries. The app does not prepare this state automatically; this is intentional.

---

## First-time setup

1. Open the WireGuard app on the TV.
2. Press **Install**.
3. Press **Upload config**.
4. Scan the QR code or open the displayed URL from a computer or phone on the same LAN.
5. Enter the displayed access code.
6. Upload your `wg0.conf`.
7. Return to the TV and close the upload window.
8. Press **Connect**.
9. Open **Details > Leak test** to verify the tunnel.

---

## The TV app

The main screen holds only:

- a status card: Connected, Disconnected, Reconnecting, VPN down: not protected, Blocked by kill switch or
  Connection failed, with the server, the time since the last handshake, data received and sent, and the public IPv4
  address. It refreshes every 5 seconds while the app is visible and pauses while it is hidden
- **Connect / Disconnect** (focused on launch)
- **Start on boot** and **Kill switch** toggles
- **Upload config** and **Details**

**Details** (Back returns to the main screen) holds **Leak test**, **Routes**, **Config** (keys stay REDACTED),
**Log**, **Install / update**, **Uninstall** (asks for confirmation, Cancel is focused first) and the text output.

The language follows the TV locale (Spanish for `es-*`, Turkish for `tr-*`, English otherwise). Remote navigation uses the arrows, OK and
Back.

---

## Example configuration

A safe example configuration is included at:

```text
examples/wg0.example.conf
```

Copy it, replace the placeholder keys and endpoint, then upload your real `wg0.conf` from the app.

Do not commit real WireGuard configuration files. They contain private keys and private VPN details.

Example:

```ini
[Interface]
PrivateKey = REPLACE_WITH_CLIENT_PRIVATE_KEY
Address = 10.10.10.2/32

[Peer]
PublicKey = REPLACE_WITH_SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.invalid:51820
PersistentKeepalive = 25
```

---

## Configuration handling

The uploader accepts normal `wg-quick` style configuration files and converts them for `wg setconf`.

Handled fields:

```text
PrivateKey
ListenPort
FwMark
PublicKey
PresharedKey
AllowedIPs
Endpoint
PersistentKeepalive
Address
```

Ignored fields:

```text
MTU
Table
SaveConfig
PreUp
PostUp
PreDown
PostDown
```

`DNS` is saved separately in `/var/lib/webosbrew/wireguard/conf/dns` (see Tunnel DNS).

`Address` is extracted and stored separately in:

```text
/var/lib/webosbrew/wireguard/conf/address
```

The converted WireGuard config is stored as:

```text
/var/lib/webosbrew/wireguard/conf/wg0.conf
```

A backup of every uploaded config is stored in:

```text
/var/lib/webosbrew/wireguard/uploads
```

Uploaded `MTU` values are ignored by the uploader. The start script uses a default tunnel MTU of `1420`.

---

## Full-tunnel routing

If your config contains:

```ini
AllowedIPs = 0.0.0.0/0
```

the start script converts it into split default routes:

```text
0.0.0.0/1
128.0.0.0/1
```

This avoids replacing the default route directly and tends to behave better on webOS.

The VPN endpoint is pinned outside the tunnel using the current default route, so WireGuard can still reach the server after the tunnel starts.
Endpoints given as a hostname are resolved through the TV's original resolver at start and again by the watchdog when
the tunnel stops working, so a changed dynamic DNS address is picked up.

---

## Tunnel DNS

While the VPN is up, the TV resolver uses the `DNS =` servers of your configuration:

- each IPv4 DNS server gets a host route through `wg0`, also when it sits inside the LAN
- the resolver file behind `/etc/resolv.conf` (on recent webOS versions `/var/lib/misc/resolv.conf`) is replaced with a bind
  mount (the webOS root file system is read only). When bind mounts fail, the file is rewritten instead. The original is saved under `run/` and restored
  exactly on stop, on a failed start and on uninstall
- search domains from the `DNS =` line are kept; IPv6 DNS servers are ignored because IPv6 is not tunneled
- the watchdog re-applies the redirection when the network manager rewrites the file, for example after wake-up

The DNS servers come from `conf/dns` (written by the uploader), from a `DNS =` line in `conf/wg0.conf`, or, for
configs uploaded with an older version, from the newest file in `uploads/`. Without any DNS server in the config the
TV keeps its normal resolver and the app status card shows nothing special, but **Leak test** warns about it.

---

## Kill switch

The kill switch is optional and off by default. Turn it on with the **Kill switch** toggle; the setting is stored in
`conf/killswitch`.

When it is on and the VPN is meant to be up, it works on two levels:

- **Routes (always).** `blackhole 0.0.0.0/1` and `blackhole 128.0.0.0/1` (plus `unreachable ::/1` and `8000::/1`
  for IPv6, and a `/32` blackhole for each tunnel DNS server) sit behind the tunnel routes with metric 4000. While
  `wg0` exists its routes (metric 0) win; the moment `wg0` vanishes (for example `wireguard-go` dies or the link
  restarts) the kernel drops them and the blackhole routes take over, with no gap. The LAN subnets and the pinned
  endpoint routes are more specific, so the LAN and the WireGuard handshake keep working. This needs no netfilter, so
  it is the kill switch on TVs whose kernel has none (on such TVs the `iptables` binary exists but
  reports "Table does not exist"). The toggle then reads **Kill switch (routes)**.
- **Firewall (when iptables works).** A dedicated `WG_KILLSWITCH` chain is jumped to from `OUTPUT` (iptables and,
  when available, ip6tables). It allows loopback, `wg0`, DHCP, the LAN subnets of the physical interfaces, multicast
  and broadcast, and UDP to each endpoint IP and port. DNS outside `wg0` and everything else are dropped. No other
  chain or rule is touched: only this chain and its single jump are added and removed.

More details:

- While the tunnel is down, `/etc/resolv.conf` keeps pointing only at the tunnel DNS servers, never back at the LAN
  router, and those servers are blackholed, so lookups fail instead of leaking.
- During autostart, the endpoints are resolved and pinned first, then the routes, the DNS redirection and (with
  iptables) a boot chain go in before the first start attempt. Endpoint hostnames are cached in `run/endpoint-cache`,
  so a start or repair still finds the server when the kill switch blocks the resolver's upstream server.
- If the tunnel fails, traffic stays blocked and the status card shows **Blocked by kill switch** until the tunnel
  works again or you press **Disconnect** or turn the kill switch off.
- **Disconnect**, **Uninstall** and turning the toggle off remove the routes and the chain completely.
- Without netfilter, apps that talk to the TV's own DNS proxy directly (instead of reading `/etc/resolv.conf`) could
  still reach the LAN router while the tunnel is down; the routes cannot filter by port.

---

## Watchdog, standby and network changes

`start.sh` launches a small watchdog (`scripts/watchdog.sh`, PID in `run/watchdog.pid`, log in `run/watchdog.log`);
`stop.sh` stops it. Every 5 seconds it checks, with a few `ip` and `wg` calls:

- the current default route outside `wg0`: when the gateway or interface changed (Wi-Fi and Ethernet) or the pinned
  endpoint route vanished, the endpoint routes are pinned again
- disabled IPv6, the DNS redirection and the kill switch routes and rules
- the latest handshake: when it is older than 3 minutes while the network is up, it sends one probe packet through the
  tunnel, re-resolves hostname endpoints and repairs the routes
- if `wireguard-go` died, it restarts the tunnel at most once a minute

If the tunnel cannot be repaired:

- with the kill switch on, traffic stays blocked and the watchdog keeps trying
- with the kill switch off, after 6 failed rounds (about 40 seconds) it removes the VPN catch-all routes and restores
  the normal resolver so the TV keeps internet access. The log says `VPN DOWN ... TRAFFIC IS NOT PROTECTED` and the
  status card shows **VPN down: not protected**. It keeps trying every 15 seconds and puts the VPN routes back as soon
  as a handshake succeeds.

This fixes the standby problem of 1.0.x: after the TV was switched off with the VPN on, the link restart flushed the
endpoint route, the encrypted packets were routed into `wg0` itself, and nothing worked until the VPN was stopped and
started again.

---

## IPv6 status

IPv6 routes and IPv6 addresses in the WireGuard configuration are currently
ignored. While the tunnel is active, IPv6 is disabled on every interface except
loopback and `wg0` (and the `default` template for interfaces that appear
later). The original value of each interface is saved and restored exactly when
WireGuard stops or a start fails. The watchdog disables IPv6 again when an
interface is re-created, for example after standby.

### IPv6 endpoints

An endpoint with an IPv6 address (`Endpoint = [2001:db8::1]:51820`, or a hostname that only resolves to IPv6) is
supported. The endpoint gets a `/128` route through the current IPv6 default route, and IPv6 stays enabled on that
interface only, because the TV needs it to reach the server. To stop other IPv6 traffic from leaving outside the
tunnel, `unreachable` routes for `::/1` and `8000::/1` are added (link-local and multicast keep working), and the kill
switch allows only the endpoint over IPv6. Switching between Wi-Fi and Ethernet with an IPv6 endpoint needs a
reconnect. IPv4 inside the tunnel works as usual.

---

## Autostart

The app can enable WireGuard autostart.

When enabled, it creates:

```text
/var/lib/webosbrew/init.d/90-wireguard
```

This is a symlink to the packaged `boot.sh`. At boot, the script waits up to 60 seconds for a default route and then
starts WireGuard. A failed start is retried up to 5 times with a growing pause (10, 20, 40 and 80 seconds). The output
goes to `run/autostart.log`, the result to `run/boot-result`, and the app shows the last boot result when it opens.
If the app is removed, the link becomes non-executable and the Homebrew hook runner skips it.

---

## Uninstall

**Details > Uninstall** asks for confirmation, stops WireGuard, removes the kill switch chain, restores DNS and IPv6,
and removes:

```text
/var/lib/webosbrew/wireguard
/var/lib/webosbrew/init.d/90-wireguard
/var/run/wireguard/wg0.sock
```

After that, you can remove the app from Homebrew Channel.

---

## Build notes

### Build `wg-upload`

```sh
cd uploader

GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" \
  -o ../app/com.github.cfernande1470.wireguard/payload/wireguard/bin/wg-upload \
  ./wg-upload.go

cd ..
```

### Build `wireguard-go`

```sh
cd wireguard-go

GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" \
  -o ../app/com.github.cfernande1470.wireguard/payload/wireguard/bin/wireguard-go .

cd ..
```

### Build for ARMv7

For all supported TVs:

```sh
GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build ...
```

All bundled binaries must remain 32-bit ARM to support both 32-bit and 64-bit LG TVs.

Check binaries with:

```sh
file app/com.github.cfernande1470.wireguard/payload/wireguard/bin/*
```

---

## Troubleshooting

### Updating to 1.1.0

Disconnect, install the new IPK, open the app and run **Details > Install / update** once. The installer stops the
old runtime and links the new scripts. Upload the config again if you want the uploader to store the DNS servers in
`conf/dns`; otherwise they are read from the newest file in `uploads/`.

### Updating from 1.0.1

Run **Install / update** once. The installer stops the old runtime, removes the copied payload, replaces it with
symlinks to the packaged files, and preserves the existing configuration.

### `ERROR luna-call`

This usually means the Homebrew root service failed or rejected the command.

Check that Homebrew Channel and its root service are working.

From the TV over SSH:

```sh
luna-send -n 1 'luna://org.webosbrew.hbchannel.service/exec' '{"command":"id; echo OK"}'
```

### `interface was not created`

Check TUN support:

```sh
ls -l /dev/net/tun
```

### VPN starts but traffic does not route

Open **Details > Leak test**, **Routes** and **Log** from the app.

Check:

```sh
ip route
ip addr show wg0
wg show wg0
```

### Uploaded config works but DNS does not change

Check that the config has a `DNS =` line and run **Details > Leak test**. The **Log** shows `resolver redirected with
a bind mount` or a `DNS IS NOT REDIRECTED` warning. On the TV:

```sh
cat /etc/resolv.conf
cat /var/lib/webosbrew/wireguard/run/dns-mode
ip route get <dns-server>
```

### No internet after standby

The watchdog should repair this within seconds. Check **Details > Log** (`watchdog.log`). Pressing **Disconnect** and
**Connect** still resets everything.

---

## Security notes

Your private key is stored on the TV in:

```text
/var/lib/webosbrew/wireguard/conf/wg0.conf
```

The upload server uses a random eight-character access code. It stops after one successful upload, five incorrect
codes, or ten minutes.

**The upload is plain HTTP.** The configuration, including your private key, crosses the LAN unencrypted. Anyone who
can watch traffic on that network (a shared Wi-Fi, a compromised device) could read the key. Use it only on your own
trusted home network, and rotate the key if in doubt. The uploader only answers clients with a local address
(RFC 1918, IPv6 ULA, link-local, loopback); requests from other addresses get `403`. The upload window on the TV shows
this warning in short form.

Do not publish real `wg0.conf` files or logs containing private data.

---

## Project layout

```text
app/com.github.cfernande1470.wireguard/
  appinfo.json
  index.html
  css/
  js/
  lib/
  payload/wireguard/
    install.sh
    bin/
      wg
      wireguard-go
      wg-upload
    scripts/
      lib.sh          shared helpers (DNS, IPv6, kill switch, endpoint routes)
      start.sh
      stop.sh
      watchdog.sh     repairs the tunnel after standby and network changes
      killswitch.sh   enable | disable | status
      summary.sh      status for the app
      leaktest.sh
      status.sh
      upload-start.sh
      upload-stop.sh
      autostart.sh
      boot.sh
      exec-clean.sh
      uninstall.sh

examples/
  wg0.example.conf

uploader/
  wg-upload.go

wireguard-go/
wireguard-tools/
```

---

## Changelog

### 1.1.0

- Tunnel DNS: the TV resolver uses the config's DNS servers through `wg0` while the VPN is up, restored exactly on stop
- Optional kill switch (off by default): blackhole routes behind the tunnel routes, plus a dedicated `WG_KILLSWITCH`
  chain where iptables works
- IPv6 disabled on every interface while the VPN is up, each original value restored
- Watchdog: fixes no internet after TV standby with the VPN on, follows Wi-Fi and Ethernet changes, re-resolves
  hostname endpoints, falls back to the normal network (clearly marked as unprotected) when the tunnel cannot be
  repaired and the kill switch is off
- IPv6 endpoints supported
- Autostart retries up to 5 times; the app shows the last boot result
- Uploader accepts local network clients only and stores the DNS servers; plain HTTP documented
- Scripts and web files always check out with LF, also on Windows (`.gitattributes`)
- New TV interface: status card, one Connect / Disconnect button, kill switch toggle, Details screen with leak test,
  QR code for the upload URL, language from the TV locale, 10-foot sizing
- Turkish added to the TV app and the upload page, which now follows the browser language; outline icons on every
  button

### 1.0.8

- Fix unresponsive UI on older webOS engines by using ES5 variable declarations (thanks @mastrogippo, PR #8)
- Confirmed working by two users on webOS 3.9.3, including installation, configuration upload, VPN start/stop, root status and autostart
- Stable release uses the same IPK tested as 1.0.8-rc.1; the official catalog minimum remains webOS 5.0

### 1.0.7

- Close inherited service descriptors before launching WireGuard and the upload server
- Prevent background daemons from keeping Homebrew Luna connections open after the service exits
- Preserve daemon PID tracking, logs, and upload-server startup settings

### 1.0.6

- Updated project links and maintainer attribution to RodriguezCF
- Simplified the TV interface

### 1.0.5

Fixed:

- Prevent IPv6 traffic from bypassing IPv4-only VPN configurations
- Preserve and restore the original IPv6 state across tunnel restarts and failed starts
- Serialize start and stop operations to prevent overlapping tunnel processes
- Track the long-lived `wireguard-go` process instead of its short-lived launcher
- Wait up to 60 seconds for networking during autostart and report a clear timeout

### 1.0.3

Fixed:

- Add explicit five-way remote navigation for arrow keys and OK/Enter
- Handle the Back key for upload dialog

### 1.0.2

Changed:

- Keep binaries and scripts in the application directory and link to them instead of copying the payload
- Use a symlinked boot hook so removing the app cannot keep starting the VPN
- Preserve only configuration, logs, and runtime state under `/var/lib/webosbrew/wireguard`
- Replace the four-digit PIN with a random eight-character access code
- Stop the upload server after one successful upload or ten minutes, and lock it after five incorrect codes
- Package releases with the standard `ares-package` tool instead of a custom IPK builder

### 1.0.1

Fixed:

- Renamed the application and package consistently to `com.github.cfernande1470.wireguard`
- Rebuilt all bundled executables for 32-bit ARMv7 compatibility
- Added an MIT licence and reproducible build, package and release verification scripts

### 1.0.0

Initial stable release.

Added:

- LG webOS Homebrew app for WireGuard
- Userspace WireGuard support through `wireguard-go`
- Bundled `wg`, `wireguard-go` and `wg-upload`
- Manual Install / update workflow
- No automatic payload installation on app startup
- Bilingual UI: English and Spanish
- Bilingual upload web server
- PIN-protected `wg0.conf` upload
- Start, stop, status, routes, config and log actions
- Optional autostart on boot
- Runtime uninstall action

Notes:

- WireGuard runs in userspace because the WireGuard kernel module is not normally available on LG webOS stock kernels.
- Current bundled binaries are built for 32-bit `linux/armv7`.
- IPv6 and DNS handling are not implemented in this release.

---

## License

The app-specific code is licensed under the [MIT License](LICENSE). Bundled WireGuard components retain their own licences:

```text
wireguard-go/LICENSE
wireguard-tools/COPYING
```

---

# Español

Cliente WireGuard para televisores LG webOS con root y Homebrew Channel.

Este proyecto proporciona una app sencilla para webOS que permite instalar, configurar, arrancar, parar y monitorizar un túnel VPN WireGuard en LG webOS. Usa WireGuard en userspace mediante `wireguard-go`, porque los kernels stock de LG webOS normalmente no incluyen el módulo WireGuard en el kernel.

La app está pensada para televisores con root y Homebrew Channel instalado.

---

## Funciones

- Túnel WireGuard en userspace usando `wireguard-go`
- Binarios incluidos: `wg`, `wireguard-go` y `wg-upload`
- Interfaz adaptada a TV
- Interfaz en inglés, español y turco
- Flujo manual de **Instalar / actualizar**
- Sin instalación automática del payload al abrir la app
- Servidor web temporal para subir `wg0.conf`
- Subida temporal protegida por un código aleatorio, con caducidad y bloqueo tras varios intentos fallidos
- Botón único Conectar / Desconectar con tarjeta de estado en directo
- DNS del túnel: la TV usa los servidores DNS de tu configuración mientras la VPN está activa
- Kill switch opcional (desactivado por defecto)
- Protección contra fugas IPv6 en todas las interfaces
- Watchdog que repara el túnel tras el modo reposo de la TV, reconexiones Wi-Fi y cambios de red
- Test de fugas, rutas, configuración y log en la pantalla Detalles
- Inicio automático opcional al arrancar, con reintentos
- Acción de desinstalación del runtime

---

## ¿Por qué WireGuard en userspace?

En Linux normal, WireGuard suele funcionar como módulo del kernel.

En televisores LG webOS, el módulo WireGuard normalmente no está disponible en el kernel de fábrica. Por eso este proyecto usa:

- `wireguard-go` para crear la interfaz WireGuard desde userspace
- `wg` de `wireguard-tools` para configurar el túnel
- una interfaz TUN creada desde userspace

Así se puede usar WireGuard sin compilar ni instalar un kernel personalizado para webOS.

---

## Requisitos

- TV LG webOS con root
- Homebrew Channel instalado
- Servicio root de Homebrew disponible
- Soporte para `/dev/net/tun` en la TV
- Arquitectura de CPU compatible

Los binarios incluidos actualmente están compilados para:

```text
linux/armv7 (32-bit ARM)
```

Comprueba la arquitectura de tu TV con:

```sh
uname -m
```

Los binarios ARMv7 incluidos también funcionan en televisores LG de 64 bits compatibles.

---

## Instalación

### 1. Descargar o compilar el IPK

Paquete de release:

```text
com.github.cfernande1470.wireguard_1.1.0_all.ipk
```

Para empaquetar manualmente:

```sh
make package
```

El empaquetado requiere `ares-package`, incluido tanto en `@webos-tools/cli`
de LG como en `ares-cli-rs` de webOSBrew. Si no está disponible en `PATH`, usa
`ARES_PACKAGE=/ruta/a/ares-package`. El paquete fuerza la arquitectura `all`
porque los binarios ARMv7 incluidos funcionan en televisores de 32 y 64 bits.

Resultado:

```text
dist/com.github.cfernande1470.wireguard_1.1.0_all.ipk
```

### 2. Instalar usando Homebrew Channel

Copia o sube el IPK a la TV e instálalo desde Homebrew Channel.

### 3. Abrir la app

Después de abrir la app, pulsa **Instalar** (el botón principal muestra Instalar hasta que los componentes estén
preparados; las actualizaciones posteriores usan **Detalles > Instalar / actualizar**).

Esto prepara el estado persistente en:

```text
/var/lib/webosbrew/wireguard
```

Los binarios y scripts permanecen dentro del directorio de la aplicación. El directorio de estado solo contiene la
configuración, los logs, los datos de ejecución y enlaces al payload empaquetado, por lo que las actualizaciones se
aplican sin duplicar los binarios. La app no prepara este estado automáticamente; esto es intencionado.

---

## Primer uso

1. Abre la app WireGuard en la TV.
2. Pulsa **Instalar**.
3. Pulsa **Subir config**.
4. Escanea el código QR o abre la URL mostrada desde un ordenador o móvil en la misma LAN.
5. Introduce el código de acceso mostrado.
6. Sube tu `wg0.conf`.
7. Vuelve a la TV y cierra la ventana de subida.
8. Pulsa **Conectar**.
9. Abre **Detalles > Test de fugas** para verificar el túnel.

---

## La app de la TV

La pantalla principal solo contiene:

- una tarjeta de estado: Conectado, Desconectado, Reconectando, VPN caída: sin protección, Bloqueado por el kill
  switch o Error de conexión, con el servidor, el tiempo desde el último handshake, los datos recibidos y enviados y la
  IPv4 pública. Se actualiza cada 5 segundos mientras la app está visible y se pausa cuando está oculta
- **Conectar / Desconectar** (con el foco al abrir)
- los interruptores **Iniciar al arrancar** y **Kill switch**
- **Subir config** y **Detalles**

**Detalles** (Atrás vuelve a la pantalla principal) contiene **Test de fugas**, **Rutas**, **Config** (las claves
siguen REDACTED), **Log**, **Instalar / actualizar**, **Desinstalar** (pide confirmación, con Cancelar enfocado) y la
salida de texto.

El idioma sigue el idioma de la TV (español para `es-*`, turco para `tr-*`, inglés en otro caso). La navegación usa las flechas, OK y
Atrás.

---

## Configuración de ejemplo

Se incluye una configuración de ejemplo segura en:

```text
examples/wg0.example.conf
```

Cópiala, sustituye las claves y el endpoint de ejemplo, y luego sube tu `wg0.conf` real desde la app.

No subas configuraciones WireGuard reales al repositorio. Contienen claves privadas y datos privados de tu VPN.

Ejemplo:

```ini
[Interface]
PrivateKey = REPLACE_WITH_CLIENT_PRIVATE_KEY
Address = 10.10.10.2/32

[Peer]
PublicKey = REPLACE_WITH_SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.invalid:51820
PersistentKeepalive = 25
```

---

## Gestión de la configuración

El uploader acepta configuraciones normales de tipo `wg-quick` y las convierte para `wg setconf`.

Campos gestionados:

```text
PrivateKey
ListenPort
FwMark
PublicKey
PresharedKey
AllowedIPs
Endpoint
PersistentKeepalive
Address
```

Campos ignorados:

```text
MTU
Table
SaveConfig
PreUp
PostUp
PreDown
PostDown
```

`DNS` se guarda aparte en `/var/lib/webosbrew/wireguard/conf/dns` (ver DNS del túnel).

`Address` se extrae y se guarda aparte en:

```text
/var/lib/webosbrew/wireguard/conf/address
```

La configuración convertida se guarda como:

```text
/var/lib/webosbrew/wireguard/conf/wg0.conf
```

Cada configuración subida se copia como backup en:

```text
/var/lib/webosbrew/wireguard/uploads
```

Los valores `MTU` subidos se ignoran en el uploader. El script de arranque usa una MTU de túnel por defecto de `1420`.

---

## Rutas full tunnel

Si tu configuración contiene:

```ini
AllowedIPs = 0.0.0.0/0
```

el script de arranque lo convierte en dos medias rutas:

```text
0.0.0.0/1
128.0.0.0/1
```

Esto evita reemplazar directamente la ruta por defecto y suele funcionar mejor en webOS.

La ruta hacia el endpoint VPN se fija fuera del túnel usando la ruta por defecto actual, para que WireGuard pueda seguir llegando al servidor después de levantar el túnel.
Los endpoints indicados con un nombre se resuelven con el resolvedor original de la TV al arrancar y de nuevo cuando
el watchdog detecta que el túnel no funciona, así que se detecta un cambio de IP de un DNS dinámico.

---

## DNS del túnel

Mientras la VPN está activa, la TV usa los servidores `DNS =` de tu configuración:

- cada servidor DNS IPv4 recibe una ruta de host por `wg0`, también si está dentro de la LAN
- el archivo del resolvedor detrás de `/etc/resolv.conf` (en versiones recientes de webOS `/var/lib/misc/resolv.conf`) se sustituye
  con un bind mount (el sistema de archivos raíz de webOS es de solo lectura). Si el bind mount falla, se reescribe el archivo. El original se guarda en `run/` y se
  restaura exactamente al parar, tras un arranque fallido y al desinstalar
- los dominios de búsqueda de la línea `DNS =` se conservan; los servidores DNS IPv6 se ignoran porque IPv6 no va por
  el túnel
- el watchdog vuelve a aplicar la redirección si el gestor de red reescribe el archivo, por ejemplo al salir del reposo

Los servidores DNS se leen de `conf/dns` (lo escribe el uploader), de una línea `DNS =` en `conf/wg0.conf` o, para
configuraciones subidas con una versión anterior, del archivo más reciente de `uploads/`. Sin servidor DNS en la
configuración, la TV mantiene su resolvedor normal y el **Test de fugas** lo avisa.

---

## Kill switch

El kill switch es opcional y está desactivado por defecto. Se activa con el interruptor **Kill switch**; el ajuste se
guarda en `conf/killswitch`.

Cuando está activo y la VPN debe estar levantada, funciona en dos niveles:

- **Rutas (siempre).** `blackhole 0.0.0.0/1` y `blackhole 128.0.0.0/1` (más `unreachable ::/1` y `8000::/1` para
  IPv6, y un blackhole `/32` para cada servidor DNS del túnel) quedan detrás de las rutas del túnel con métrica 4000.
  Mientras existe `wg0` ganan sus rutas (métrica 0); en cuanto `wg0` desaparece (por ejemplo, si `wireguard-go` se
  detiene o el enlace se reinicia) el kernel las borra y las rutas blackhole toman el relevo sin hueco. Las subredes
  LAN y las rutas fijadas del endpoint son más específicas, así que la LAN y el handshake de WireGuard siguen
  funcionando. No necesita netfilter, así que es el kill switch en las TV cuyo kernel no lo tiene (en esas TV el
  binario `iptables` existe pero responde "Table does not exist"). El interruptor muestra entonces
  **Kill switch (rutas)**.
- **Cortafuegos (si iptables funciona).** Se añade una cadena propia `WG_KILLSWITCH` con un salto desde `OUTPUT`
  (iptables y, si existe, ip6tables). Permite loopback, `wg0`, DHCP, las subredes LAN de las interfaces físicas,
  multicast y broadcast, y UDP hacia la IP y el puerto de cada endpoint. El DNS fuera de `wg0` y todo lo demás se
  descarta. No se toca ninguna otra cadena ni regla: solo se añaden y eliminan esta cadena y su salto.

Más detalles:

- Mientras el túnel está caído, `/etc/resolv.conf` sigue apuntando solo a los servidores DNS del túnel, nunca de nuevo
  al router de la LAN, y esos servidores están en blackhole, así que las consultas fallan en lugar de filtrarse.
- Durante el inicio automático se resuelven y fijan primero los endpoints, y después se añaden las rutas, la
  redirección DNS y (con iptables) una cadena de arranque antes del primer intento. Los nombres de los endpoints se
  guardan en `run/endpoint-cache`, así que un arranque o una reparación siguen encontrando el servidor aunque el kill
  switch bloquee el servidor DNS de origen.
- Si el túnel falla, el tráfico sigue bloqueado y la tarjeta muestra **Bloqueado por el kill switch** hasta que el
  túnel vuelva a funcionar, pulses **Desconectar** o desactives el kill switch.
- **Desconectar**, **Desinstalar** y desactivar el interruptor eliminan las rutas y la cadena por completo.
- Sin netfilter, las apps que consulten directamente el proxy DNS propio de la TV (en lugar de leer `/etc/resolv.conf`)
  aún podrían llegar al router de la LAN mientras el túnel está caído; las rutas no pueden filtrar por puerto.

---

## Watchdog, reposo y cambios de red

`start.sh` lanza un pequeño watchdog (`scripts/watchdog.sh`, PID en `run/watchdog.pid`, log en `run/watchdog.log`);
`stop.sh` lo detiene. Cada 5 segundos comprueba, con unas pocas llamadas a `ip` y `wg`:

- la ruta por defecto actual fuera de `wg0`: si cambió la puerta de enlace o la interfaz (Wi-Fi y Ethernet) o
  desapareció la ruta del endpoint, vuelve a fijar las rutas del endpoint
- la IPv6 desactivada, la redirección DNS y las rutas y reglas del kill switch
- el último handshake: si tiene más de 3 minutos y hay red, envía un paquete de prueba por el túnel, vuelve a resolver
  los endpoints con nombre y repara las rutas
- si `wireguard-go` se detuvo, reinicia el túnel como mucho una vez por minuto

Si el túnel no se puede reparar:

- con el kill switch activo, el tráfico sigue bloqueado y el watchdog sigue intentándolo
- sin kill switch, tras 6 rondas fallidas (unos 40 segundos) quita las rutas de la VPN que capturan todo el tráfico y
  restaura el resolvedor normal para que la TV mantenga el acceso a internet. El log dice `VPN DOWN ... TRAFFIC IS NOT
  PROTECTED` y la tarjeta muestra **VPN caída: sin protección**. Sigue intentándolo cada 15 segundos y vuelve a poner
  las rutas de la VPN en cuanto hay un handshake.

Esto corrige el problema del reposo de 1.0.x: al apagar la TV con la VPN activa, el reinicio del enlace borraba la
ruta del endpoint, los paquetes cifrados se enviaban al propio `wg0` y nada funcionaba hasta parar y arrancar la VPN.

---

## Estado de IPv6

Las rutas y direcciones IPv6 de la configuración de WireGuard se ignoran por
ahora. Mientras el túnel está activo, IPv6 se desactiva en todas las interfaces
salvo loopback y `wg0` (y la plantilla `default` para las interfaces que
aparezcan después). Se guarda el valor original de cada interfaz y se restaura
exactamente al detener WireGuard o tras un arranque fallido. El watchdog vuelve
a desactivar IPv6 si una interfaz se recrea, por ejemplo tras el reposo.

### Endpoints IPv6

Se admite un endpoint con dirección IPv6 (`Endpoint = [2001:db8::1]:51820`, o un nombre que solo resuelve a IPv6). El
endpoint recibe una ruta `/128` por la ruta IPv6 por defecto actual, e IPv6 sigue activa solo en esa interfaz, porque
la TV la necesita para llegar al servidor. Para que el resto del tráfico IPv6 no salga fuera del túnel se añaden
rutas `unreachable` para `::/1` y `8000::/1` (link-local y multicast siguen funcionando), y el kill switch solo permite
el endpoint por IPv6. Cambiar entre Wi-Fi y Ethernet con un endpoint IPv6 requiere reconectar. El IPv4 dentro del
túnel funciona como siempre.

---

## Inicio automático

La app puede activar WireGuard al arrancar.

Cuando está activado, crea:

```text
/var/lib/webosbrew/init.d/90-wireguard
```

Es un enlace al `boot.sh` incluido en la app. Durante el arranque, el script espera hasta 60 segundos a que exista una
ruta por defecto y luego inicia WireGuard. Un arranque fallido se reintenta hasta 5 veces con pausas crecientes (10,
20, 40 y 80 segundos). La salida va a `run/autostart.log`, el resultado a `run/boot-result`, y la app muestra el
último resultado al abrirse. Si se elimina la app, el enlace deja de ser ejecutable y Homebrew lo ignora.

---

## Desinstalación

**Detalles > Desinstalar** pide confirmación, detiene WireGuard, elimina la cadena del kill switch, restaura DNS e
IPv6, y elimina:

```text
/var/lib/webosbrew/wireguard
/var/lib/webosbrew/init.d/90-wireguard
/var/run/wireguard/wg0.sock
```

Después puedes eliminar la app desde Homebrew Channel.

---

## Notas de compilación

### Compilar `wg-upload`

```sh
cd uploader

GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" \
  -o ../app/com.github.cfernande1470.wireguard/payload/wireguard/bin/wg-upload \
  ./wg-upload.go

cd ..
```

### Compilar `wireguard-go`

```sh
cd wireguard-go

GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" \
  -o ../app/com.github.cfernande1470.wireguard/payload/wireguard/bin/wireguard-go .

cd ..
```

### Compilar para ARMv7

Para todos los televisores compatibles:

```sh
GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build ...
```

Todos los binarios incluidos deben seguir siendo ARM de 32 bits para admitir televisores LG de 32 y 64 bits.

Comprueba los binarios con:

```sh
file app/com.github.cfernande1470.wireguard/payload/wireguard/bin/*
```

---

## Solución de problemas

### Actualizar a 1.1.0

Desconecta, instala el nuevo IPK, abre la app y ejecuta una vez **Detalles > Instalar / actualizar**. El instalador
detiene el runtime anterior y enlaza los nuevos scripts. Vuelve a subir la configuración si quieres que el uploader
guarde los servidores DNS en `conf/dns`; si no, se leen del archivo más reciente de `uploads/`.

### Actualizar desde 1.0.1

Pulsa **Instalar / actualizar** una vez. El instalador detiene el runtime antiguo, elimina la copia del payload, la
sustituye por enlaces a los archivos incluidos en la app y conserva la configuración existente.

### `ERROR luna-call`

Normalmente significa que el servicio root de Homebrew ha fallado o ha rechazado el comando.

Comprueba que Homebrew Channel y su servicio root funcionan.

Desde SSH en la TV:

```sh
luna-send -n 1 'luna://org.webosbrew.hbchannel.service/exec' '{"command":"id; echo OK"}'
```

### `interface was not created`

Comprueba soporte TUN:

```sh
ls -l /dev/net/tun
```

### La VPN arranca pero el tráfico no va por el túnel

Abre **Detalles > Test de fugas**, **Rutas** y **Log** desde la app.

Comprueba:

```sh
ip route
ip addr show wg0
wg show wg0
```

### La configuración sube bien pero DNS no cambia

Comprueba que la configuración tiene una línea `DNS =` y ejecuta **Detalles > Test de fugas**. El **Log** muestra
`resolver redirected with a bind mount` o el aviso `DNS IS NOT REDIRECTED`. En la TV:

```sh
cat /etc/resolv.conf
cat /var/lib/webosbrew/wireguard/run/dns-mode
ip route get <servidor-dns>
```

### Sin internet tras el reposo

El watchdog debería repararlo en segundos. Revisa **Detalles > Log** (`watchdog.log`). Pulsar **Desconectar** y
**Conectar** sigue reiniciándolo todo.

---

## Seguridad

Tu clave privada se guarda en la TV en:

```text
/var/lib/webosbrew/wireguard/conf/wg0.conf
```

El servidor de subida usa un código de acceso aleatorio de ocho caracteres. Se detiene tras una subida correcta,
cinco códigos incorrectos o diez minutos.

**La subida usa HTTP sin cifrar.** La configuración, incluida tu clave privada, viaja por la LAN sin cifrar. Quien
pueda observar el tráfico de esa red (una Wi-Fi compartida, un dispositivo comprometido) podría leer la clave. Úsala
solo en tu red doméstica de confianza y cambia la clave si tienes dudas. El uploader solo responde a clientes con una
dirección local (RFC 1918, IPv6 ULA, link-local, loopback); el resto recibe `403`. La ventana de subida de la TV
muestra este aviso de forma breve.

No publiques configuraciones reales ni logs con datos privados.

---

## Estructura del proyecto

```text
app/com.github.cfernande1470.wireguard/
  appinfo.json
  index.html
  css/
  js/
  lib/
  payload/wireguard/
    install.sh
    bin/
      wg
      wireguard-go
      wg-upload
    scripts/
      lib.sh          funciones comunes (DNS, IPv6, kill switch, rutas del endpoint)
      start.sh
      stop.sh
      watchdog.sh     repara el túnel tras el reposo y los cambios de red
      killswitch.sh   enable | disable | status
      summary.sh      estado para la app
      leaktest.sh
      status.sh
      upload-start.sh
      upload-stop.sh
      autostart.sh
      boot.sh
      exec-clean.sh
      uninstall.sh

examples/
  wg0.example.conf

uploader/
  wg-upload.go

wireguard-go/
wireguard-tools/
```

---

## Registro de cambios

### 1.1.0

- DNS del túnel: la TV usa los servidores DNS de la configuración por `wg0` mientras la VPN está activa, y se
  restauran exactamente al parar
- Kill switch opcional (desactivado por defecto): rutas blackhole detrás de las rutas del túnel, más una cadena propia
  `WG_KILLSWITCH` donde iptables funciona
- IPv6 desactivada en todas las interfaces mientras la VPN está activa, restaurando cada valor original
- Watchdog: corrige la falta de internet tras el reposo de la TV con la VPN activa, sigue los cambios entre Wi-Fi y
  Ethernet, vuelve a resolver los endpoints con nombre y, sin kill switch, vuelve a la red normal (marcada claramente
  como sin protección) si el túnel no se puede reparar
- Endpoints IPv6 admitidos
- El inicio automático se reintenta hasta 5 veces; la app muestra el último resultado del arranque
- El uploader solo acepta clientes de la red local y guarda los servidores DNS; documentado que usa HTTP sin cifrar
- Los scripts y archivos web se descargan siempre con LF, también en Windows (`.gitattributes`)
- Nueva interfaz de TV: tarjeta de estado, un solo botón Conectar / Desconectar, interruptor de kill switch, pantalla
  Detalles con test de fugas, código QR para la URL de subida, idioma según la TV y tamaños para ver a distancia
- Turco añadido a la app de la TV y a la página de subida, que ahora sigue el idioma del navegador; iconos de contorno
  en todos los botones

### 1.0.8

- Corregida la interfaz que no respondía en motores antiguos de webOS usando declaraciones de variables ES5 (gracias a @mastrogippo, PR #8)
- Dos usuarios confirman su funcionamiento en webOS 3.9.3, incluida la instalación, subida de configuración, inicio/parada de VPN, estado root y arranque automático
- La versión estable usa el mismo IPK probado como 1.0.8-rc.1; el mínimo oficial del catálogo sigue siendo webOS 5.0

### 1.0.7

- Cerrados los descriptores heredados del servicio antes de iniciar WireGuard y el servidor de subida
- Evitado que los procesos en segundo plano mantengan abiertas las conexiones Luna tras salir el servicio de Homebrew
- Conservados el seguimiento del PID, los logs y los ajustes de arranque del servidor de subida

### 1.0.6

- Actualizados los enlaces del proyecto y la atribución a RodriguezCF
- Simplificada la interfaz de la TV

### 1.0.5

Corregido:

- Evitado que el tráfico IPv6 escape de configuraciones VPN que sólo admiten IPv4
- Conservado y restaurado el estado IPv6 original tras reinicios del túnel y arranques fallidos
- Serializadas las operaciones de inicio y parada para evitar procesos de túnel solapados
- Registrado el proceso persistente de `wireguard-go` en lugar de su lanzador temporal
- Ampliada a 60 segundos la espera de red del inicio automático, con un error claro al agotarse

### 1.0.3

Corregido:

- Añadida navegación explícita con las flechas del mando y activación con OK/Enter

### 1.0.2

Cambios:

- Los binarios y scripts permanecen en la aplicación y se enlazan en lugar de copiar el payload
- El hook de arranque es un enlace, así que eliminar la app no puede seguir iniciando la VPN
- Solo la configuración, los logs y el estado de ejecución permanecen en `/var/lib/webosbrew/wireguard`
- El PIN de cuatro cifras se sustituye por un código de acceso aleatorio de ocho caracteres
- El servidor se detiene tras una subida correcta o diez minutos y se bloquea tras cinco códigos incorrectos
- Las releases se empaquetan con la herramienta estándar `ares-package` en lugar de un generador IPK propio

### 1.0.1

Corregido:

- Renombrado coherente de la aplicación y el paquete a `com.github.cfernande1470.wireguard`
- Recompilación de todos los ejecutables incluidos para ARMv7 de 32 bits
- Añadida la licencia MIT y scripts reproducibles de compilación, empaquetado y verificación

### 1.0.0

Primera versión estable.

Añadido:

- App LG webOS Homebrew para WireGuard
- Soporte WireGuard en userspace mediante `wireguard-go`
- Binarios incluidos: `wg`, `wireguard-go` y `wg-upload`
- Flujo manual de Instalar / actualizar
- Sin instalación automática del payload al abrir la app
- Interfaz bilingüe: inglés y español
- Servidor web de subida bilingüe
- Subida de `wg0.conf` protegida por PIN
- Acciones de arrancar, parar, estado, rutas, configuración y log
- Inicio automático opcional al arrancar
- Acción de desinstalación del runtime

Notas:

- WireGuard se ejecuta en userspace porque el módulo WireGuard del kernel no suele estar disponible en kernels stock de LG webOS.
- Los binarios incluidos actualmente están compilados para `linux/armv7` de 32 bits.
- IPv6 y gestión de DNS no están implementados en esta versión.

---

## Licencia

El código específico de la app está publicado bajo la [licencia MIT](LICENSE). Los componentes de WireGuard incluidos conservan sus propias licencias:

```text
wireguard-go/LICENSE
wireguard-tools/COPYING
```

---

# Türkçe

Homebrew Channel kullanan, root erişimli LG webOS TV'ler için bir WireGuard istemcisi.

Bu proje, LG webOS üzerinde bir WireGuard VPN tünelini kurabilen, yapılandırabilen, başlatıp durdurabilen ve izleyebilen basit bir webOS uygulaması sunar. LG webOS'un fabrika çekirdekleri genellikle WireGuard çekirdek modülünü içermediği için WireGuard'ı `wireguard-go` aracılığıyla userspace'te çalıştırır.

Uygulama, Homebrew Channel kurulu, root erişimli TV'ler için tasarlanmıştır.

---

## Özellikler

- `wireguard-go` ile userspace WireGuard tüneli
- Hazır gelen `wg`, `wireguard-go` ve `wg-upload` ikili dosyaları
- TV kullanımına uygun webOS arayüzü
- İngilizce, İspanyolca ve Türkçe arayüz
- Elle çalıştırılan **Kur / güncelle** akışı
- Uygulama açılışında otomatik payload kurulumu yok
- `wg0.conf` için geçici web yükleme sunucusu
- Rastgele bir erişim kodu ve hatalı deneme kilidiyle korunan, süre sınırlı yapılandırma yüklemesi
- Canlı durum kartıyla tek düğmeli Bağlan / Bağlantıyı kes
- Tünel DNS'i: VPN açıkken TV'nin çözümleyicisi yapılandırmanızdaki DNS sunucularını kullanır
- İsteğe bağlı kill switch (varsayılan olarak kapalı)
- Tüm ağ arayüzlerinde IPv6 sızıntı koruması
- TV bekleme modu, Wi-Fi yeniden bağlanmaları ve ağ değişikliklerinden sonra tüneli onaran watchdog
- Ayrıntılar ekranında sızıntı testi, rotalar, yapılandırma ve günlük
- Yeniden denemeli, isteğe bağlı açılışta otomatik başlatma
- Runtime kaldırma işlemi

---

## Neden userspace WireGuard?

Normal Linux sistemlerinde WireGuard genellikle bir çekirdek modülü olarak çalışır.

LG webOS TV'lerde WireGuard çekirdek modülü fabrika çekirdeğinde normalde bulunmaz. Bu nedenle bu proje şunları kullanır:

- WireGuard arayüzünü userspace'te oluşturmak için `wireguard-go`
- tüneli yapılandırmak için `wireguard-tools` içindeki `wg`
- userspace'ten oluşturulan bir TUN arayüzü

Bu sayede özel bir webOS çekirdeği derlemeden veya kurmadan WireGuard çalıştırmak mümkün olur.

---

## Gereksinimler

- Root erişimli LG webOS TV
- Kurulu Homebrew Channel
- Kullanılabilir Homebrew root servisi
- TV'de `/dev/net/tun` desteği
- Uyumlu CPU mimarisi

Mevcut sürümdeki hazır ikili dosyalar şu hedef için derlenmiştir:

```text
linux/armv7 (32-bit ARM)
```

TV'nizin mimarisini şu komutla kontrol edin:

```sh
uname -m
```

Hazır ARMv7 ikili dosyaları, desteklenen 64 bit LG TV'lerde de çalışır.

---

## Kurulum

### 1. IPK'yı indirin veya derleyin

Sürüm paketi:

```text
com.github.cfernande1470.wireguard_1.1.0_all.ipk
```

Elle paketlemek için:

```sh
make package
```

Paketleme için LG'nin `@webos-tools/cli` paketinde ya da webOSBrew'un `ares-cli-rs` aracında bulunan
`ares-package` gerekir. `PATH` üzerinde bulunmuyorsa `ARES_PACKAGE=/path/to/ares-package` değişkenini ayarlayın.
Hazır ARMv7 ikili dosyaları hem 32 bit hem 64 bit TV'lerde çalıştığı için paket mimarisi zorunlu olarak `all`
yapılır.

Çıktı:

```text
dist/com.github.cfernande1470.wireguard_1.1.0_all.ipk
```

### 2. Homebrew Channel ile kurun

IPK'yı TV'nize kopyalayın veya yükleyin ve Homebrew Channel'dan kurun.

### 3. Uygulamayı açın

Uygulamayı başlattıktan sonra **Kur** düğmesine basın (bileşenler hazırlanana kadar ana düğmede Kur yazar;
sonraki güncellemeler **Ayrıntılar > Kur / güncelle** üzerinden yapılır).

Bu işlem kalıcı durumu şu dizinde hazırlar:

```text
/var/lib/webosbrew/wireguard
```

Paketlenmiş ikili dosyalar ve betikler uygulama dizininin içinde kalır. Durum dizini yalnızca yapılandırmayı,
günlükleri, çalışma zamanı dosyalarını ve paketlenmiş payload'a giden sembolik bağlantıları içerir; böylece
güncellemeler ikili dosyalar çoğaltılmadan etkili olur. Uygulama bu durumu otomatik olarak hazırlamaz; bu bilinçli
bir tercihtir.

---

## İlk kurulum

1. TV'de WireGuard uygulamasını açın.
2. **Kur** düğmesine basın.
3. **Yapılandırma yükle** düğmesine basın.
4. QR kodunu tarayın veya gösterilen URL'yi aynı LAN'daki bir bilgisayardan ya da telefondan açın.
5. Gösterilen erişim kodunu girin.
6. `wg0.conf` dosyanızı yükleyin.
7. TV'ye dönün ve yükleme penceresini kapatın.
8. **Bağlan** düğmesine basın.
9. Tüneli doğrulamak için **Ayrıntılar > Sızıntı testi** ekranını açın.

---

## TV uygulaması

Ana ekranda yalnızca şunlar bulunur:

- bir durum kartı: Bağlı, Bağlı değil, Yeniden bağlanıyor, VPN kapalı: korumasız, Kill Switch engelliyor veya
  Bağlantı kurulamadı; ayrıca sunucu, son el sıkışmadan (handshake) bu yana geçen süre, alınan ve gönderilen veri ile
  genel IPv4 adresi. Uygulama görünür olduğu sürece 5 saniyede bir yenilenir, gizliyken duraklar
- **Bağlan / Bağlantıyı kes** (açılışta odak buradadır)
- **Açılışta başlat** ve **Kill Switch** anahtarları
- **Yapılandırma yükle** ve **Ayrıntılar**

**Ayrıntılar** ekranında (Geri tuşu ana ekrana döner) **Sızıntı testi**, **Rotalar**, **Yapılandırma** (anahtarlar
REDACTED olarak kalır), **Günlük**, **Kur / güncelle**, **Kaldır** (onay ister, odak önce İptal üzerindedir) ve metin
çıktısı bulunur.

Dil, TV'nin yerel ayarını izler (`es-*` için İspanyolca, `tr-*` için Türkçe, diğer durumlarda İngilizce). Kumandayla
gezinmede oklar, OK ve Geri tuşları kullanılır.

---

## Örnek yapılandırma

Güvenli bir örnek yapılandırma şurada bulunur:

```text
examples/wg0.example.conf
```

Bunu kopyalayın, yer tutucu anahtarları ve endpoint'i değiştirin, ardından gerçek `wg0.conf` dosyanızı uygulamadan
yükleyin.

Gerçek WireGuard yapılandırma dosyalarını commit etmeyin. Bu dosyalar özel anahtarlar ve gizli VPN bilgileri içerir.

Örnek:

```ini
[Interface]
PrivateKey = REPLACE_WITH_CLIENT_PRIVATE_KEY
Address = 10.10.10.2/32

[Peer]
PublicKey = REPLACE_WITH_SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.invalid:51820
PersistentKeepalive = 25
```

---

## Yapılandırmanın işlenmesi

Yükleyici, normal `wg-quick` biçimindeki yapılandırma dosyalarını kabul eder ve bunları `wg setconf` için dönüştürür.

İşlenen alanlar:

```text
PrivateKey
ListenPort
FwMark
PublicKey
PresharedKey
AllowedIPs
Endpoint
PersistentKeepalive
Address
```

Yok sayılan alanlar:

```text
MTU
Table
SaveConfig
PreUp
PostUp
PreDown
PostDown
```

`DNS` ayrı olarak `/var/lib/webosbrew/wireguard/conf/dns` dosyasına kaydedilir (bkz. Tünel DNS'i).

`Address` ayıklanır ve ayrı olarak şuraya kaydedilir:

```text
/var/lib/webosbrew/wireguard/conf/address
```

Dönüştürülmüş WireGuard yapılandırması şu adla saklanır:

```text
/var/lib/webosbrew/wireguard/conf/wg0.conf
```

Yüklenen her yapılandırmanın bir yedeği şurada saklanır:

```text
/var/lib/webosbrew/wireguard/uploads
```

Yüklenen `MTU` değerleri yükleyici tarafından yok sayılır. Başlatma betiği varsayılan olarak `1420` tünel MTU'sunu
kullanır.

---

## Tam tünel yönlendirmesi

Yapılandırmanız şunu içeriyorsa:

```ini
AllowedIPs = 0.0.0.0/0
```

başlatma betiği bunu iki parçalı varsayılan rotaya dönüştürür:

```text
0.0.0.0/1
128.0.0.0/1
```

Bu yöntem varsayılan rotayı doğrudan değiştirmekten kaçınır ve webOS'ta genellikle daha iyi çalışır.

VPN endpoint'i mevcut varsayılan rota kullanılarak tünelin dışında sabitlenir; böylece WireGuard, tünel başladıktan sonra da sunucuya ulaşabilir.
Ana bilgisayar adı (hostname) olarak verilen endpoint'ler başlatma sırasında TV'nin özgün çözümleyicisiyle, tünel
çalışmayı bıraktığında ise watchdog tarafından yeniden çözümlenir; böylece değişen bir dinamik DNS adresi algılanır.

---

## Tünel DNS'i

VPN açıkken TV'nin çözümleyicisi yapılandırmanızdaki `DNS =` sunucularını kullanır:

- her IPv4 DNS sunucusu, LAN içinde olsa bile `wg0` üzerinden bir host rotası alır
- `/etc/resolv.conf` arkasındaki çözümleyici dosyası (yeni webOS sürümlerinde `/var/lib/misc/resolv.conf`) bir bind
  mount ile değiştirilir (webOS kök dosya sistemi salt okunurdur). Bind mount başarısız olursa dosya yeniden yazılır. Özgün dosya `run/` altına kaydedilir ve
  durdurmada, başarısız bir başlatmada ve kaldırmada birebir geri yüklenir
- `DNS =` satırındaki arama alan adları korunur; IPv6 tünellenmediği için IPv6 DNS sunucuları yok sayılır
- ağ yöneticisi dosyayı yeniden yazdığında (örneğin uyandıktan sonra) watchdog yönlendirmeyi yeniden uygular

DNS sunucuları `conf/dns` dosyasından (yükleyici yazar), `conf/wg0.conf` içindeki bir `DNS =` satırından ya da eski bir
sürümle yüklenmiş yapılandırmalar için `uploads/` içindeki en yeni dosyadan alınır. Yapılandırmada hiç DNS sunucusu
yoksa TV normal çözümleyicisini kullanmaya devam eder ve uygulamanın durum kartı özel bir şey göstermez, ancak
**Sızıntı testi** bu konuda uyarır.

---

## Kill switch

Kill switch isteğe bağlıdır ve varsayılan olarak kapalıdır. **Kill Switch** anahtarıyla açın; ayar
`conf/killswitch` dosyasında saklanır.

Açık olduğunda ve VPN'in çalışıyor olması gerektiğinde iki düzeyde çalışır:

- **Rotalar (her zaman).** `blackhole 0.0.0.0/1` ve `blackhole 128.0.0.0/1` (ayrıca IPv6 için `unreachable ::/1` ve
  `8000::/1`, her tünel DNS sunucusu için de bir `/32` blackhole) 4000 metrikle tünel rotalarının arkasında durur.
  `wg0` var olduğu sürece onun rotaları (metrik 0) kazanır; `wg0` kaybolduğu anda (örneğin `wireguard-go` sonlanırsa
  veya bağlantı yeniden başlarsa) çekirdek bu rotaları siler ve hiç boşluk kalmadan blackhole rotaları devreye girer.
  LAN alt ağları ve sabitlenmiş endpoint rotaları daha spesifik olduğu için LAN ve WireGuard el sıkışması çalışmaya
  devam eder. Bu yöntem netfilter gerektirmez; bu nedenle çekirdeğinde netfilter bulunmayan TV'lerde kill switch budur
  (bu TV'lerde `iptables` ikili dosyası vardır ama "Table does not exist" yanıtını verir). Anahtar bu durumda
  **Kill Switch (rotalar)** olarak görünür.
- **Güvenlik duvarı (iptables çalışıyorsa).** `OUTPUT` zincirinden ayrı bir `WG_KILLSWITCH` zincirine atlanır
  (iptables ve varsa ip6tables). Bu zincir loopback'e, `wg0`'a, DHCP'ye, fiziksel arayüzlerin LAN alt ağlarına,
  multicast ve broadcast trafiğine ve her endpoint IP'si ile portuna giden UDP'ye izin verir. `wg0` dışındaki DNS ve
  geri kalan her şey düşürülür. Başka hiçbir zincire veya kurala dokunulmaz: yalnızca bu zincir ve tek atlama kuralı
  eklenip kaldırılır.

Diğer ayrıntılar:

- Tünel kapalıyken `/etc/resolv.conf` yalnızca tünel DNS sunucularını göstermeye devam eder, hiçbir zaman LAN
  yönlendiricisine geri dönmez ve bu sunucular blackhole'a alınmıştır; böylece sorgular sızmak yerine başarısız olur.
- Otomatik başlatma sırasında önce endpoint'ler çözümlenip sabitlenir, ardından ilk başlatma denemesinden önce rotalar,
  DNS yönlendirmesi ve (iptables varsa) bir açılış zinciri eklenir. Endpoint ana bilgisayar adları
  `run/endpoint-cache` içinde önbelleğe alınır; böylece kill switch çözümleyicinin üst sunucusunu engellese bile bir
  başlatma veya onarım sunucuyu yine bulabilir.
- Tünel başarısız olursa trafik engelli kalır ve durum kartı, tünel yeniden çalışana, siz **Bağlantıyı kes** düğmesine
  basana ya da kill switch'i kapatana kadar **Kill Switch engelliyor** gösterir.
- **Bağlantıyı kes**, **Kaldır** ve anahtarı kapatmak, rotaları ve zinciri tamamen kaldırır.
- Netfilter olmadan, TV'nin kendi DNS proxy'siyle doğrudan konuşan uygulamalar (`/etc/resolv.conf` dosyasını okumak
  yerine) tünel kapalıyken LAN yönlendiricisine yine ulaşabilir; rotalar porta göre filtreleme yapamaz.

---

## Watchdog, bekleme modu ve ağ değişiklikleri

`start.sh` küçük bir watchdog başlatır (`scripts/watchdog.sh`, PID `run/watchdog.pid` içinde, günlük
`run/watchdog.log` içinde); `stop.sh` onu durdurur. Watchdog her 5 saniyede bir, birkaç `ip` ve `wg` çağrısıyla
şunları kontrol eder:

- `wg0` dışındaki mevcut varsayılan rota: ağ geçidi veya arayüz değiştiğinde (Wi-Fi ve Ethernet) ya da sabitlenmiş
  endpoint rotası kaybolduğunda endpoint rotaları yeniden sabitlenir
- devre dışı bırakılmış IPv6, DNS yönlendirmesi ve kill switch rotaları ile kuralları
- son el sıkışma: ağ açıkken 3 dakikadan eskiyse tünelden bir yoklama paketi gönderir, ana bilgisayar adlı
  endpoint'leri yeniden çözümler ve rotaları onarır
- `wireguard-go` sonlanmışsa tüneli en fazla dakikada bir yeniden başlatır

Tünel onarılamazsa:

- kill switch açıkken trafik engelli kalır ve watchdog denemeye devam eder
- kill switch kapalıyken, 6 başarısız turdan sonra (yaklaşık 40 saniye) tüm trafiği yakalayan VPN rotalarını kaldırır
  ve TV'nin internet erişimi sürsün diye normal çözümleyiciyi geri yükler. Günlükte
  `VPN DOWN ... TRAFFIC IS NOT PROTECTED` yazar ve durum kartı **VPN kapalı: korumasız** gösterir. Her 15 saniyede
  bir denemeye devam eder ve bir el sıkışma başarılı olur olmaz VPN rotalarını geri koyar.

Bu, 1.0.x sürümlerindeki bekleme modu sorununu giderir: VPN açıkken TV kapatıldığında bağlantının yeniden başlaması
endpoint rotasını siliyor, şifreli paketler `wg0`'ın kendisine yönlendiriliyor ve VPN durdurulup yeniden
başlatılana kadar hiçbir şey çalışmıyordu.

---

## IPv6 durumu

WireGuard yapılandırmasındaki IPv6 rotaları ve IPv6 adresleri şu anda yok
sayılır. Tünel etkinken IPv6, loopback ve `wg0` dışındaki tüm arayüzlerde (ve
sonradan ortaya çıkan arayüzler için `default` şablonunda) devre dışı bırakılır.
Her arayüzün özgün değeri kaydedilir ve WireGuard durduğunda veya bir başlatma
başarısız olduğunda birebir geri yüklenir. Bir arayüz yeniden oluşturulduğunda
(örneğin bekleme modundan sonra) watchdog IPv6'yı yeniden devre dışı bırakır.

### IPv6 endpoint'leri

IPv6 adresli bir endpoint (`Endpoint = [2001:db8::1]:51820` ya da yalnızca IPv6'ya çözümlenen bir ana bilgisayar adı)
desteklenir. Endpoint, mevcut IPv6 varsayılan rotası üzerinden bir `/128` rotası alır ve TV'nin sunucuya ulaşmak için
IPv6'ya ihtiyacı olduğundan IPv6 yalnızca o arayüzde etkin kalır. Diğer IPv6 trafiğinin tünel dışına çıkmasını önlemek
için `::/1` ve `8000::/1` için `unreachable` rotaları eklenir (link-local ve multicast çalışmaya devam eder) ve kill
switch IPv6 üzerinden yalnızca endpoint'e izin verir. IPv6 endpoint'i kullanırken Wi-Fi ile Ethernet arasında geçiş
yapmak yeniden bağlanmayı gerektirir. Tünel içindeki IPv4 her zamanki gibi çalışır.

---

## Otomatik başlatma

Uygulama, WireGuard için otomatik başlatmayı etkinleştirebilir.

Etkinleştirildiğinde şunu oluşturur:

```text
/var/lib/webosbrew/init.d/90-wireguard
```

Bu, paketlenmiş `boot.sh` dosyasına giden bir sembolik bağlantıdır. Açılışta betik, bir varsayılan rota için en fazla
60 saniye bekler ve ardından WireGuard'ı başlatır. Başarısız bir başlatma, giderek uzayan aralarla (10, 20, 40 ve 80
saniye) en fazla 5 kez yeniden denenir. Çıktı `run/autostart.log` dosyasına, sonuç `run/boot-result` dosyasına
yazılır ve uygulama açıldığında son açılış sonucunu gösterir. Uygulama kaldırılırsa bağlantı çalıştırılamaz hale gelir
ve Homebrew hook çalıştırıcısı onu atlar.

---

## Kaldırma

**Ayrıntılar > Kaldır** onay ister, WireGuard'ı durdurur, kill switch zincirini kaldırır, DNS ve IPv6 ayarlarını geri
yükler ve şunları siler:

```text
/var/lib/webosbrew/wireguard
/var/lib/webosbrew/init.d/90-wireguard
/var/run/wireguard/wg0.sock
```

Bundan sonra uygulamayı Homebrew Channel'dan kaldırabilirsiniz.

---

## Derleme notları

### `wg-upload` derleme

```sh
cd uploader

GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" \
  -o ../app/com.github.cfernande1470.wireguard/payload/wireguard/bin/wg-upload \
  ./wg-upload.go

cd ..
```

### `wireguard-go` derleme

```sh
cd wireguard-go

GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" \
  -o ../app/com.github.cfernande1470.wireguard/payload/wireguard/bin/wireguard-go .

cd ..
```

### ARMv7 için derleme

Desteklenen tüm TV'ler için:

```sh
GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build ...
```

Hem 32 bit hem 64 bit LG TV'leri desteklemek için hazır ikili dosyaların tümü 32 bit ARM olarak kalmalıdır.

İkili dosyaları şu komutla kontrol edin:

```sh
file app/com.github.cfernande1470.wireguard/payload/wireguard/bin/*
```

---

## Sorun giderme

### 1.1.0 sürümüne güncelleme

Bağlantıyı kesin, yeni IPK'yı kurun, uygulamayı açın ve **Ayrıntılar > Kur / güncelle** işlemini bir kez çalıştırın.
Kurulum betiği eski runtime'ı durdurur ve yeni betiklere bağlantı verir. Yükleyicinin DNS sunucularını `conf/dns`
içine kaydetmesini istiyorsanız yapılandırmayı yeniden yükleyin; aksi halde bu sunucular `uploads/` içindeki en yeni
dosyadan okunur.

### 1.0.1 sürümünden güncelleme

**Kur / güncelle** işlemini bir kez çalıştırın. Kurulum betiği eski runtime'ı durdurur, kopyalanmış payload'ı siler,
yerine paketlenmiş dosyalara giden sembolik bağlantılar koyar ve mevcut yapılandırmayı korur.

### `ERROR luna-call`

Bu genellikle Homebrew root servisinin başarısız olduğu veya komutu reddettiği anlamına gelir.

Homebrew Channel'ın ve root servisinin çalıştığını kontrol edin.

TV'ye SSH ile bağlanıp şunu çalıştırın:

```sh
luna-send -n 1 'luna://org.webosbrew.hbchannel.service/exec' '{"command":"id; echo OK"}'
```

### `interface was not created`

TUN desteğini kontrol edin:

```sh
ls -l /dev/net/tun
```

### VPN başlıyor ama trafik tünelden geçmiyor

Uygulamada **Ayrıntılar > Sızıntı testi**, **Rotalar** ve **Günlük** ekranlarını açın.

Şunları kontrol edin:

```sh
ip route
ip addr show wg0
wg show wg0
```

### Yüklenen yapılandırma çalışıyor ama DNS değişmiyor

Yapılandırmada bir `DNS =` satırı bulunduğunu kontrol edin ve **Ayrıntılar > Sızıntı testi** işlemini çalıştırın.
**Günlük** ekranında `resolver redirected with a bind mount` satırı ya da `DNS IS NOT REDIRECTED` uyarısı görünür.
TV'de:

```sh
cat /etc/resolv.conf
cat /var/lib/webosbrew/wireguard/run/dns-mode
ip route get <dns-server>
```

### Bekleme modundan sonra internet yok

Watchdog bunu birkaç saniye içinde onarmalıdır. **Ayrıntılar > Günlük** (`watchdog.log`) ekranına bakın.
**Bağlantıyı kes** ve ardından **Bağlan** düğmesine basmak her şeyi yine sıfırlar.

---

## Güvenlik notları

Özel anahtarınız TV'de şurada saklanır:

```text
/var/lib/webosbrew/wireguard/conf/wg0.conf
```

Yükleme sunucusu sekiz karakterlik rastgele bir erişim kodu kullanır. Bir başarılı yüklemeden, beş hatalı koddan veya
on dakikadan sonra durur.

**Yükleme düz HTTP üzerinden yapılır.** Özel anahtarınız dahil yapılandırma, LAN üzerinden şifrelenmeden iletilir. O
ağdaki trafiği izleyebilen herkes (paylaşılan bir Wi-Fi, ele geçirilmiş bir cihaz) anahtarı okuyabilir. Yalnızca
güvendiğiniz kendi ev ağınızda kullanın ve şüpheniz varsa anahtarı yenileyin. Yükleyici yalnızca yerel adresli
istemcilere yanıt verir (RFC 1918, IPv6 ULA, link-local, loopback); diğer adreslerden gelen istekler `403` alır. TV'deki
yükleme penceresi bu uyarıyı kısa biçimde gösterir.

Gerçek `wg0.conf` dosyalarını veya özel veri içeren günlükleri yayımlamayın.

---

## Proje yapısı

```text
app/com.github.cfernande1470.wireguard/
  appinfo.json
  index.html
  css/
  js/
  lib/
  payload/wireguard/
    install.sh
    bin/
      wg
      wireguard-go
      wg-upload
    scripts/
      lib.sh          shared helpers (DNS, IPv6, kill switch, endpoint routes)
      start.sh
      stop.sh
      watchdog.sh     repairs the tunnel after standby and network changes
      killswitch.sh   enable | disable | status
      summary.sh      status for the app
      leaktest.sh
      status.sh
      upload-start.sh
      upload-stop.sh
      autostart.sh
      boot.sh
      exec-clean.sh
      uninstall.sh

examples/
  wg0.example.conf

uploader/
  wg-upload.go

wireguard-go/
wireguard-tools/
```

---

## Değişiklik günlüğü

### 1.1.0

- Tünel DNS'i: VPN açıkken TV'nin çözümleyicisi yapılandırmadaki DNS sunucularını `wg0` üzerinden kullanır; durdurmada
  birebir geri yüklenir
- İsteğe bağlı kill switch (varsayılan olarak kapalı): tünel rotalarının arkasında blackhole rotaları, iptables'ın
  çalıştığı yerlerde ek olarak ayrı bir `WG_KILLSWITCH` zinciri
- VPN açıkken tüm ağ arayüzlerinde IPv6 devre dışı; her özgün değer geri yüklenir
- Watchdog: VPN açıkken TV bekleme modundan sonra internetin gitmesini düzeltir, Wi-Fi ve Ethernet değişikliklerini
  izler, ana bilgisayar adlı endpoint'leri yeniden çözümler, tünel onarılamadığında ve kill switch kapalıyken normal
  ağa döner (açıkça korumasız olarak işaretlenir)
- IPv6 endpoint'leri destekleniyor
- Otomatik başlatma en fazla 5 kez yeniden dener; uygulama son açılış sonucunu gösterir
- Yükleyici yalnızca yerel ağdaki istemcileri kabul eder ve DNS sunucularını kaydeder; düz HTTP kullanımı belgelendi
- Betikler ve web dosyaları Windows'ta da her zaman LF ile checkout edilir (`.gitattributes`)
- Yeni TV arayüzü: durum kartı, tek Bağlan / Bağlantıyı kes düğmesi, kill switch anahtarı, sızıntı testi içeren
  Ayrıntılar ekranı, yükleme URL'si için QR kodu, TV yerel ayarına göre dil, uzaktan izlemeye uygun (10-foot)
  boyutlandırma
- TV uygulamasına ve artık tarayıcı dilini izleyen yükleme sayfasına Türkçe eklendi; tüm düğmelerde çizgi (outline)
  simgeler

### 1.0.8

- Eski webOS motorlarında yanıt vermeyen arayüz, ES5 değişken tanımlamaları kullanılarak düzeltildi (teşekkürler @mastrogippo, PR #8)
- webOS 3.9.3 üzerinde iki kullanıcı tarafından kurulum, yapılandırma yükleme, VPN başlatma/durdurma, root durumu ve otomatik başlatma dahil çalıştığı doğrulandı
- Kararlı sürüm, 1.0.8-rc.1 olarak test edilen IPK'nın aynısını kullanır; resmi katalogdaki en düşük sürüm webOS 5.0 olarak kalır

### 1.0.7

- WireGuard ve yükleme sunucusu başlatılmadan önce servisten devralınan dosya tanımlayıcıları kapatıldı
- Arka plan daemon'larının, servis sonlandıktan sonra Homebrew Luna bağlantılarını açık tutması engellendi
- Daemon PID takibi, günlükler ve yükleme sunucusunun başlatma ayarları korundu

### 1.0.6

- Proje bağlantıları ve bakımcı bilgisi RodriguezCF olarak güncellendi
- TV arayüzü sadeleştirildi

### 1.0.5

Düzeltilenler:

- IPv6 trafiğinin yalnızca IPv4 kullanan VPN yapılandırmalarını atlatması engellendi
- Özgün IPv6 durumunun tünel yeniden başlatmalarında ve başarısız başlatmalarda korunup geri yüklenmesi sağlandı
- Üst üste binen tünel işlemlerini önlemek için başlatma ve durdurma işlemleri sıraya alındı
- Kısa ömürlü başlatıcısı yerine uzun ömürlü `wireguard-go` işlemi takip edilmeye başlandı
- Otomatik başlatmada ağ için en fazla 60 saniye beklenmesi ve zaman aşımında açık bir hata bildirilmesi sağlandı

### 1.0.3

Düzeltilenler:

- Ok tuşları ve OK/Enter için açık, beş yönlü kumanda gezinmesi eklendi
- Yükleme penceresi için Geri tuşu desteği eklendi

### 1.0.2

Değişenler:

- İkili dosyalar ve betikler uygulama dizininde tutuluyor; payload kopyalanmak yerine bunlara bağlantı veriliyor
- Uygulama kaldırıldığında VPN'in başlatılmaya devam etmemesi için sembolik bağlantılı bir açılış hook'u kullanılıyor
- `/var/lib/webosbrew/wireguard` altında yalnızca yapılandırma, günlükler ve çalışma zamanı durumu tutuluyor
- Dört haneli PIN yerine sekiz karakterlik rastgele bir erişim kodu kullanılıyor
- Yükleme sunucusu bir başarılı yüklemeden veya on dakikadan sonra duruyor, beş hatalı koddan sonra kilitleniyor
- Sürümler, özel bir IPK oluşturucu yerine standart `ares-package` aracıyla paketleniyor

### 1.0.1

Düzeltilenler:

- Uygulama ve paket tutarlı biçimde `com.github.cfernande1470.wireguard` olarak yeniden adlandırıldı
- Hazır gelen tüm çalıştırılabilir dosyalar 32 bit ARMv7 uyumluluğu için yeniden derlendi
- MIT lisansı ve yeniden üretilebilir derleme, paketleme ve sürüm doğrulama betikleri eklendi

### 1.0.0

İlk kararlı sürüm.

Eklenenler:

- WireGuard için LG webOS Homebrew uygulaması
- `wireguard-go` ile userspace WireGuard desteği
- Hazır gelen `wg`, `wireguard-go` ve `wg-upload`
- Elle çalıştırılan Kur / güncelle akışı
- Uygulama açılışında otomatik payload kurulumu yok
- İki dilli arayüz: İngilizce ve İspanyolca
- İki dilli yükleme web sunucusu
- PIN korumalı `wg0.conf` yüklemesi
- Başlatma, durdurma, durum, rotalar, yapılandırma ve günlük işlemleri
- Açılışta isteğe bağlı otomatik başlatma
- Runtime kaldırma işlemi

Notlar:

- WireGuard çekirdek modülü LG webOS fabrika çekirdeklerinde normalde bulunmadığı için WireGuard userspace'te çalışır.
- Mevcut hazır ikili dosyalar 32 bit `linux/armv7` için derlenmiştir.
- IPv6 ve DNS işleme bu sürümde uygulanmamıştır.

---

## Lisans

Uygulamaya özgü kod [MIT Lisansı](LICENSE) altında lisanslanmıştır. Hazır gelen WireGuard bileşenleri kendi lisanslarını korur:

```text
wireguard-go/LICENSE
wireguard-tools/COPYING
```
