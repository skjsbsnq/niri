use smithay::reexports::wayland_protocols::xdg::shell::client::xdg_toplevel;
use wayland_client::protocol::wl_surface::WlSurface;

use super::*;

fn create_window(f: &mut Fixture, id: client::ClientId) -> WlSurface {
    let window = f.client(id).create_window();
    let surface = window.surface.clone();
    window.commit();
    f.roundtrip(id);

    let window = f.client(id).window(&surface);
    window.attach_new_buffer();
    window.set_size(100, 100);
    window.ack_last_and_commit();
    f.double_roundtrip(id);

    surface
}

#[test]
fn xdg_toplevel_advertises_minimize_capability() {
    let mut f = Fixture::new();
    f.add_output(1, (1920, 1080));

    let id = f.add_client();
    let surface = create_window(&mut f, id);

    let window = f.client(id).window(&surface);
    assert!(window
        .wm_capabilities
        .contains(&xdg_toplevel::WmCapabilities::Minimize));
}

#[test]
fn xdg_toplevel_set_minimized_minimizes_window() {
    let mut f = Fixture::new();
    f.add_output(1, (1920, 1080));

    let id = f.add_client();
    let surface = create_window(&mut f, id);

    f.client(id).window(&surface).set_minimized();
    f.double_roundtrip(id);

    let mapped = f.niri().layout.windows().next().unwrap().1;
    assert!(mapped.is_minimized());
}
