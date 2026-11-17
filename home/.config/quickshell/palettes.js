// Wallpaper palettes, shared by the wallpaper (WallState.qml) and the lock screen (lock/).
// Per scene, for dark and light mode: five colours low to high (c), and where the upper
// four sit on the colour ramp (s).
.pragma library

var palettes = {
        silk:     { dark:  { c: ["#0e0e12", "#1a1130", "#3f2269", "#6b2d86", "#f56600"], s: [0.42, 0.66, 0.82, 1.0] },
                    light: { c: ["#34195a", "#5b2a86", "#a8306c", "#e2500a", "#ff8f2e"], s: [0.30, 0.52, 0.74, 1.0] } },
        aurora:   { dark:  { c: ["#0b0b10", "#1a1130", "#522d80", "#a03a8a", "#f56600"], s: [0.3, 0.5, 0.75, 1.0] },
                    light: { c: ["#2a1650", "#4a2a7a", "#7a4ab0", "#c0508a", "#ff8f2e"], s: [0.3, 0.5, 0.75, 1.0] } },
        contours: { dark:  { c: ["#16161a", "#1d1830", "#6f6190", "#7a4fb0", "#f56600"], s: [0.3, 0.5, 0.75, 1.0] },
                    light: { c: ["#44266c", "#583392", "#b9a5d8", "#e9dcf2", "#ff8f2e"], s: [0.3, 0.5, 0.75, 1.0] } },
        ink:      { dark:  { c: ["#121216", "#1a1228", "#3f2269", "#7a3aa0", "#f56600"], s: [0.3, 0.5, 0.75, 1.0] },
                    light: { c: ["#3a1f66", "#4a2a7c", "#6f44a6", "#b05a9a", "#ff8f2e"], s: [0.3, 0.5, 0.75, 1.0] } },
        // the line scenes share the contours colours: ground, high ground, line, bright line, accent
        terrain:  { dark:  { c: ["#16161a", "#1f1a33", "#6f6190", "#7a4fb0", "#f56600"], s: [0.3, 0.5, 0.75, 1.0] },
                    light: { c: ["#44266c", "#583392", "#b9a5d8", "#e9dcf2", "#ff8f2e"], s: [0.3, 0.5, 0.75, 1.0] } },
        flow:     { dark:  { c: ["#16161a", "#1d1830", "#6f6190", "#7a4fb0", "#f56600"], s: [0.3, 0.5, 0.75, 1.0] },
                    light: { c: ["#44266c", "#583392", "#b9a5d8", "#e9dcf2", "#ff8f2e"], s: [0.3, 0.5, 0.75, 1.0] } },
        ripples:  { dark:  { c: ["#16161a", "#1d1830", "#6f6190", "#7a4fb0", "#f56600"], s: [0.3, 0.5, 0.75, 1.0] },
                    light: { c: ["#44266c", "#583392", "#b9a5d8", "#e9dcf2", "#ff8f2e"], s: [0.3, 0.5, 0.75, 1.0] } },
        field:    { dark:  { c: ["#16161a", "#1d1830", "#6f6190", "#7a4fb0", "#f56600"], s: [0.3, 0.5, 0.75, 1.0] },
                    light: { c: ["#44266c", "#583392", "#b9a5d8", "#e9dcf2", "#ff8f2e"], s: [0.3, 0.5, 0.75, 1.0] } },
        pulsar:   { dark:  { c: ["#131317", "#1d1830", "#6f6190", "#8a63c0", "#f56600"], s: [0.3, 0.5, 0.75, 1.0] },
                    light: { c: ["#44266c", "#583392", "#b9a5d8", "#e9dcf2", "#ff8f2e"], s: [0.3, 0.5, 0.75, 1.0] } },
        depths:   { dark:  { c: ["#121216", "#1e1832", "#5d4f80", "#4a2f78", "#f56600"], s: [0.3, 0.5, 0.75, 1.0] },
                    light: { c: ["#3b2062", "#52308a", "#8f78bf", "#7a56b0", "#ff8f2e"], s: [0.3, 0.5, 0.75, 1.0] } },
        // ridges, sky: night sky top / night sky low / day sky top / day sky low and haze / horizon glow
        ridges:   { dark:  { c: ["#0e0e14", "#2a1b40", "#3a2d63", "#6f5590", "#f56600"], s: [0.3, 0.5, 0.75, 1.0] },
                    light: { c: ["#161226", "#3a2560", "#5a549c", "#b58aa6", "#ff8f2e"], s: [0.3, 0.5, 0.75, 1.0] } },
        sky:      { dark:  { c: ["#0a0a10", "#1d1533", "#3a2d63", "#6f5590", "#f56600"], s: [0.3, 0.5, 0.75, 1.0] },
                    light: { c: ["#141024", "#34225a", "#5a549c", "#b58aa6", "#ff8f2e"], s: [0.3, 0.5, 0.75, 1.0] } }
    }
