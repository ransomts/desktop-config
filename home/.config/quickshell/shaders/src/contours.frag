// Contours: a topographic map whose terrain slowly morphs. Every fifth line is the accent.
void main() {
    vec2 px = layoutPx();
    vec2 p = px / unit * 1.25 + vec2(env.z * 0.7, 0.0);
    float h = fbm(p + vec2(time * 0.50, -time * 0.30)) * 0.70 + fbm(p * 0.5 - time * 0.20) * 0.50
            + wake(px, 300.0) * 0.07 + audio.x * 0.025;
    float v = h * 38.0;
    float fw = fwidth(v);
    float line = 1.0 - smoothstep(0.0, 1.4 * fw, abs(fract(v - 0.5) - 0.5));
    float lvl = floor(v + 0.5);
    float m = mod(lvl, 5.0);
    vec3 col = mix(c0.rgb, c1.rgb, smoothstep(0.35, 0.95, h));
    vec3 lc = mix(c0.rgb, c2.rgb, 0.42);
    float wgt = 0.80;
    if (m < 0.5) { lc = c4.rgb; wgt = 0.95 + audio.w * 0.3; }
    else if (abs(m - 2.0) < 0.5) { lc = c3.rgb; wgt = 0.85; }
    col = mix(col, lc, clamp(line * wgt, 0.0, 1.0));
    fragColor = finish(col);
}
