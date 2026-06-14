use smithay::reexports::wayland_protocols::xdg::shell::client::xdg_toplevel;

use super::*;

#[test]
fn xdg_toplevel_advertises_minimize_capability() {
    let mut f = Fixture::new();
    f.add_output(1, (1920, 1080));

    let id = f.add_client();
    let window = f.client(id).create_window();
    let surface = window.surface.clone();
    window.commit();
    f.double_roundtrip(id);

    let window = f.client(id).window(&surface);
    assert!(window
        .wm_capabilities
        .contains(&xdg_toplevel::WmCapabilities::Minimize));
}
