# Phase 0 Visual Parameters

Source references:

- `macOS-26-Tahoe-for-the-Web-main/Css/style.css`
- `macOS-26-Tahoe-for-the-Web-main/javascript/script.js`
- `macOS-26-Tahoe-for-the-Web-main/background/`
- `macOS-26-Tahoe-for-the-Web-main/icon/dock/`

Candidate values:

- Window corner radius: 18 px.
- Popup corner radius: 14 px.
- Dock radius: 24 px.
- Control Center radius: 24 px.
- Window shadow: offset `0 10`, softness `36`, spread `4`, color `#0006`.
- Panel fill: white at 20-72% alpha depending on layer.
- Dock fill: `#33ffffff` with `#59ffffff` border.
- Control Center fill: `#b8f5f6f8` with `#70ffffff` border.
- Compositor blur: 3 passes, offset 4, noise 0.025, saturation 1.35.
- Quickshell blur region radius: 24 px for Dock and Control Center.

Phase 1 shell UI components to finish:

- Real top bar status services for clock, network, sound, battery, and active app.
- Dock model with pinned apps plus `ToplevelManager.toplevels`.
- Window button component with activate/minimized state handling.
- Control Center overlay lifecycle, outside-click close, and real toggles.
- Launchpad grid backed by desktop entries and copied icons.
- Workspace display backed by `WindowManager.windowsets`.
- Central asset path and icon mapping service.
