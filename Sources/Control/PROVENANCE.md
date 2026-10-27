# Control source provenance

The control implementation was copied from the local `mks_tweak` checkout at
`25f8a70d880f76de5681889ce3562065844b8b09`, for the APIs consumed by GoScrcpy main
at `f8ba1546cb7d90b4daec07747f6e2fc692d962a3`.

- Screen, device information, settings, HTTP/JSON validation, WebSocket input,
  HID injection and command execution were copied from `pccontrol`.
- `headers/GCDWebServers` and `libs/libGCDWebServers.a` are bundled copies of
  the existing HTTP/WebSocket dependency, without requiring the old package.
  Library SHA256: `aa53767ad3938f3fc35a85669953621525118b38c46e01082ffc00b55e677a41`.
- `../../RootHelper` derives from `mks_tweak/roothelp`; its installed executable
  is renamed to `phonevideo-roothelp`.
- `../Keyboard/PMKeyboard.m` adapts the text, delete, cursor and keyboard
  notification handling from `appdelegate/UIKeyboard.xm`. It receives once per
  process and dispatches every UIKit operation to the main thread.

Custom classes/functions and the keyboard notification are prefixed for
PhoneVideo. The server binds only to loopback on device port 27185, retaining
the existing JSON schemas. GoScrcpy selects this service first, then legacy
`mks_tweak:8081` only when the new control port cannot be connected. An API
instance pins its provider, and never replays failed HTTP commands on another
provider. Video remains on port 27184.

Application-specific settings were intentionally excluded: one-click region
settings only apply system language, locale and time zone. The copied server
does not read/write GPT application preferences or process carrier parameters.
The desktop sends an empty JSON object with the three system query parameters,
including when falling back to the legacy plugin. Carrier presets are removed.

Original copyright/license comments are retained, including the GPL-2.0
notices in HID sources and BSD notices in the bundled GCDWebServer headers.
Unrelated MKS APIs (app management, location, advertising identifiers, keychain,
VPN, web UI and account switching) are not part of GoScrcpy main's contract.
