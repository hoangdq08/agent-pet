//! Keep the pet window on a screen (port of the macOS fix in PR #67:
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

/// Like `keep_on_screen`, but only the part of the window that is actually
/// drawn (`visible`: x, y, w, h relative to the window origin) has to stay on a
/// screen. The pet window is 260x320 with a mostly transparent margin, so
/// requiring the whole window on screen kept shoving a pet that was dropped
/// next to an edge back by a few pixels (and again on every drop). With the
/// visible rect the transparent margin may hang off the screen, and the move is
/// only as large as needed to bring the sprite back. An empty/unknown rect
/// falls back to the whole window.
pub fn keep_visible_on_screen(
    origin: (i32, i32),
    size: (i32, i32),
    visible: (f64, f64, f64, f64),
    areas: &[Rect],
) -> (i32, i32) {
    let (vx, vy, vw, vh) = visible;
    if !(vw > 0.0 && vh > 0.0) {
        return keep_on_screen(origin, size, areas);
    }
    // Clamp inside the visible rect's own frame, then translate back.
    let vis = (vx.floor() as i32, vy.floor() as i32);
    let vsize = (vw.ceil() as i32, vh.ceil() as i32);
    let vorigin = (origin.0 + vis.0, origin.1 + vis.1);
    let moved = keep_on_screen(vorigin, vsize, areas);
    (moved.0 - vis.0, moved.1 - vis.1)
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

    // Sprite as the app reports it: ~38..222 across, ~97..223 down in the 260x320 window.
    const VIS: (f64, f64, f64, f64) = (38.0, 97.0, 184.0, 126.0);

    #[test]
    fn transparent_margin_may_hang_off_the_edge() {
        // Window x=2960 (20 px past 3200-260) but the sprite (x 2998..3182) is on screen: leave it.
        assert_eq!(keep_visible_on_screen((2960, 24), PET, VIS, &MONS), (2960, 24));
    }

    #[test]
    fn sprite_past_the_edge_is_pulled_back_only_as_far_as_needed() {
        // Window x=3100: sprite would span 3138..3322, so it moves left by 122 to end at 3200.
        assert_eq!(keep_visible_on_screen((3100, 24), PET, VIS, &MONS), (2978, 24));
    }

    #[test]
    fn sprite_below_the_bottom_comes_back() {
        // Sprite y = 800+97 .. 800+223 = 897..1023, 123 px too low.
        assert_eq!(keep_visible_on_screen((400, 800), PET, VIS, &MONS), (400, 677));
    }

    #[test]
    fn unknown_visible_rect_falls_back_to_the_whole_window() {
        assert_eq!(keep_visible_on_screen((3100, 100), PET, (0.0, 0.0, 0.0, 0.0), &MONS), (3200 - 260, 100));
    }

    #[test]
    fn visible_clamp_never_moves_a_correct_pet() {
        for x in [0, 500, 1340, 1600, 2000, 2940] {
            assert_eq!(keep_visible_on_screen((x, 100), PET, VIS, &MONS), (x, 100), "x={x}");
        }
    }

    #[test]
    fn no_monitors_leaves_origin() {
        assert_eq!(keep_on_screen((5, 6), PET, &[]), (5, 6));
        assert_eq!(nearest_rect_index((0, 0), &[]), None);
    }
}
