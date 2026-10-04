//! Keep the pet window on a screen (port of the macOS dev fix c9a36dd:
//! "keep a dragged pet on screen when dropped past an edge"). Pure math on
//! physical-pixel rects so it can be unit-tested; lib.rs feeds it the
//! monitors' work areas.

/// (x, y, width, height) in physical pixels.
pub type Rect = (i32, i32, i32, i32);

/// Index of the rect closest to `p` (0 distance when inside), for a pet
/// dropped outside every screen. None only when `rects` is empty.
pub fn nearest_rect_index(p: (i32, i32), rects: &[Rect]) -> Option<usize> {
    let dist = |r: &Rect| {
        let (x, y, w, h) = *r;
        let dx = (x - p.0).max(0).max(p.0 - (x + w)) as i64;
        let dy = (y - p.1).max(0).max(p.1 - (y + h)) as i64;
        dx * dx + dy * dy
    };
    (0..rects.len()).min_by_key(|&i| dist(&rects[i]))
}

/// Origin that keeps a `size` window inside `area`. Top/left are fitted
/// first, then bottom/right win, so for a window bigger than the screen the
/// bottom (where the pet sprite sits) stays visible (macOS verticalOrigin).
pub fn clamp_into(origin: (i32, i32), size: (i32, i32), area: Rect) -> (i32, i32) {
    let (ax, ay, aw, ah) = area;
    let mut x = origin.0;
    let mut y = origin.1;
    if x < ax { x = ax; }
    if x + size.0 > ax + aw { x = ax + aw - size.0; }
    if y < ay { y = ay; }
    if y + size.1 > ay + ah { y = ay + ah - size.1; }
    (x, y)
}

/// Where the window should be: unchanged when it is already fully on some
/// screen, otherwise clamped into the screen nearest its centre.
pub fn keep_on_screen(origin: (i32, i32), size: (i32, i32), areas: &[Rect]) -> (i32, i32) {
    let centre = (origin.0 + size.0 / 2, origin.1 + size.1 / 2);
    let Some(i) = nearest_rect_index(centre, areas) else { return origin };
    clamp_into(origin, size, areas[i])
}

#[cfg(test)]
mod tests {
    use super::*;

    // Two monitors like the user's: 1600x900 primary + 1600x900 to its right.
    const MONS: [Rect; 2] = [(0, 0, 1600, 900), (1600, 0, 1600, 900)];
    const PET: (i32, i32) = (260, 320);

    #[test]
    fn on_screen_window_is_untouched() {
        assert_eq!(keep_on_screen((1200, 500), PET, &MONS), (1200, 500));
        assert_eq!(keep_on_screen((1700, 0), PET, &MONS), (1700, 0));
    }

    #[test]
    fn dropped_low_comes_back_up() {
        // Half the sprite below the bottom edge (the macOS bug report).
        assert_eq!(keep_on_screen((400, 750), PET, &MONS), (400, 900 - 320));
    }

    #[test]
    fn dropped_past_the_right_edge_of_the_last_screen() {
        assert_eq!(keep_on_screen((3100, 100), PET, &MONS), (3200 - 260, 100));
    }

    #[test]
    fn dropped_outside_every_screen_uses_the_nearest() {
        assert_eq!(keep_on_screen((-900, -900), PET, &MONS), (0, 0));
        assert_eq!(keep_on_screen((5000, 2000), PET, &MONS), (3200 - 260, 900 - 320));
    }

    #[test]
    fn straddling_two_screens_settles_on_the_one_holding_the_centre() {
        // Centre at x=1650 is on the right monitor.
        assert_eq!(keep_on_screen((1520, 100), PET, &MONS), (1600, 100));
    }

    #[test]
    fn window_taller_than_screen_keeps_the_bottom() {
        assert_eq!(clamp_into((0, -50), (260, 1000), (0, 0, 1600, 900)), (0, 900 - 1000));
    }

    #[test]
    fn no_monitors_leaves_origin() {
        assert_eq!(keep_on_screen((5, 6), PET, &[]), (5, 6));
        assert_eq!(nearest_rect_index((0, 0), &[]), None);
    }
}
