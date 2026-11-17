// Ink: dye carried along a slowly changing swirl (curl noise) and read as bands, so it curls,
// stretches and thins like marbled ink on water.
vec2 curl(vec2 q) {
    float e = 0.06;
    float n1 = fbm(q + vec2(0.0, e)), n2 = fbm(q - vec2(0.0, e));
    float n3 = fbm(q + vec2(e, 0.0)), n4 = fbm(q - vec2(e, 0.0));
    return vec2(n1 - n2, n4 - n3) / (2.0 * e);
}
void main() {
    vec2 px = layoutPx();
    vec2 p = px / unit * 1.1 + vec2(env.z * 0.9, env.z * 0.3);
    float t = time * 1.6;
    vec2 q = p;
    q += normalize(px - pointer.xy + 0.001) * wake(px, 260.0) * 0.10;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        q += curl(q * 1.10 + vec2(t * 0.30, -t * 0.22) + fi * 1.7) * (0.24 + audio.x * 0.05);
    }
    float dye = fbm(q * 1.3 + 3.1);
    float s = dye * 9.0 + fbm(q * 0.6 - 5.2 + t * 0.05) * 3.0;
    float fw = fwidth(s);
    float band = fract(s), id = floor(s);
    float m = mod(id, 4.0);
    // each band is a sheet of one colour, shaded across its width; where the dye is thin, bare water
    vec3 sheet = m < 0.5 ? c2.rgb : m < 1.5 ? c1.rgb : m < 2.5 ? c3.rgb : c1.rgb * 0.8;
    sheet *= 0.70 + 0.45 * band;
    float edge = smoothstep(0.0, 1.5 * fw, band) * smoothstep(0.0, 1.5 * fw, 1.0 - band);
    vec3 col = mix(c0.rgb, sheet, smoothstep(0.34, 0.50, dye) * edge);
    // a thin bright seam where every fourth sheet begins
    float seam = (1.0 - smoothstep(0.0, 2.5 * fw + 0.03, band)) * step(m, 0.5) * smoothstep(0.40, 0.55, dye);
    col = mix(col, c4.rgb, clamp(seam * (0.9 + audio.w * 0.5), 0.0, 1.0));
    fragColor = finish(col);
}
