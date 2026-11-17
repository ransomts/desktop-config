// Ripples: thin rings spreading from a few slowly wandering points; where the ring systems cross they make moire. Every fifth ring is the accent.
const float CELL    = 0.90;   // source grid pitch in units (one source per cell)
const float REACH   = 1.15;   // how far a source's rings carry, in cells (keep <= 1.2 so the 3x3 search is seamless)
const float SPACING = 26.0;   // ring spacing, px
const float SPEED   = 12.0;   // ring spacings travelled per unit of time
const float WANDER  = 0.35;   // source drift rate

// Line strength of one ring system at distance d (px): x ordinary, y bright, z accent.
vec3 rings(float d, float spacing, float phase, float amp) {
    float v = d / spacing - phase;
    float line = 1.0 - smoothstep(0.0, 1.4, abs(fract(v - 0.5) - 0.5) * spacing);
    float m = mod(floor(v + 0.5), 5.0);
    line *= amp * smoothstep(0.3, 1.6, d / spacing);          // no dot at the very centre
    if (m < 0.5) return vec3(0.0, 0.0, line);
    if (abs(m - 2.0) < 0.5) return vec3(0.0, line, 0.0);
    return vec3(line, 0.0, 0.0);
}

void main() {
    vec2 px = layoutPx();
    vec2 p = (px / unit + vec2(env.z * 0.7, 0.0)) / CELL;
    vec2 ci = floor(p), cf = p - ci;
    float cellPx = CELL * unit;
    vec3 acc = vec3(0.0);
    float glow = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 o = vec2(float(i), float(j));
            vec2 id = ci + o;
            float h1 = hash(id), h2 = hash(id + vec2(41.3, 17.9));
            vec2 src = 0.5 + 0.3 * vec2(cos(h1 * 6.2831853 + time * WANDER * (0.7 + 0.6 * h2)),
                                        sin(h2 * 6.2831853 + time * WANDER * (0.7 + 0.6 * h1)));
            float dc = length(o + src - cf);                   // distance in cells
            float fall = 1.0 - smoothstep(0.10, REACH, dc);
            fall *= fall;
            float sp = SPACING * (0.85 + 0.30 * h2);
            acc += rings(dc * cellPx, sp, time * SPEED * (0.85 + 0.30 * h1) + h1 * 5.0, fall);
            glow += fall * fall;
        }
    }
    if (pointer.z > 0.0) {                                     // the pointer is one more, smaller source
        float d = length(px - pointer.xy);
        float fall = pointer.z * exp(-d * d / (420.0 * 420.0));
        acc += rings(d, SPACING * 0.8, time * SPEED * 1.3, fall * 0.8);
    }
    vec3 col = mix(c0.rgb, c1.rgb, clamp(glow * 0.45, 0.0, 1.0));
    col = mix(col, mix(c0.rgb, c2.rgb, 0.42), clamp(acc.x * 0.80, 0.0, 1.0));
    col = mix(col, c3.rgb, clamp(acc.y * 0.70, 0.0, 1.0));
    col = mix(col, c4.rgb, clamp(acc.z * (0.75 + audio.w * 0.25 + audio.x * 0.10), 0.0, 1.0));
    fragColor = finish(col);
}
