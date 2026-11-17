// Depths: a nautical depth chart in cut paper. Flat bands of a slowly morphing height field, stacked like sheets; every fifth edge is the accent.
const float LEVELS = 40.0;       // bands per unit of height; about 18 across the visible range
const float SHADOW_PX = 8.0;     // width of the shadow under each edge, px
const float SHADOW_AMT = 0.22;   // strength of that shadow

vec3 bandTone(float t) {         // t 0 (deepest) .. 1 (highest), stepped per band
    vec3 top = mix(c1.rgb, mix(c2.rgb, c3.rgb, 0.5), 0.38);
    vec3 c = mix(c0.rgb, c1.rgb, clamp(t / 0.6, 0.0, 1.0));
    return mix(c, top, clamp((t - 0.6) / 0.4, 0.0, 1.0));
}

void main() {
    vec2 px = layoutPx();
    vec2 p = px / unit * 0.95 + vec2(env.z * 0.7 + 31.7, -12.3);
    float h = fbm(p + vec2(-time * 0.42, time * 0.34)) * 0.70 + fbm(p * 0.55 + vec2(time * 0.22, time * 0.16)) * 0.50
            + wake(px, 300.0) * 0.07 + audio.x * 0.025;
    float v = h * LEVELS;
    float fw = max(fwidth(v), 1e-5);
    float band = floor(v);
    float f = v - band;

    // fill: one flat tone per band
    vec3 col = bandTone(clamp((band / LEVELS - 0.36) / 0.48, 0.0, 1.0));

    // shadow cast by the sheet above onto the top few pixels of this band
    float sw = min(SHADOW_PX * fw, 0.6);
    float sh = 1.0 - smoothstep(0.0, sw, 1.0 - f);
    col = mix(col, c0.rgb * 0.6, sh * sh * SHADOW_AMT);

    // edge line at each band boundary
    float line = 1.0 - smoothstep(0.0, 1.2 * fw, abs(fract(v - 0.5) - 0.5));
    vec3 lc = c2.rgb;
    float wgt = 0.55;
    if (mod(floor(v + 0.5), 5.0) < 0.5) { lc = c4.rgb; wgt = 0.85 + audio.w * 0.3; }
    col = mix(col, lc, clamp(line * wgt, 0.0, 1.0));
    fragColor = finish(col);
}
