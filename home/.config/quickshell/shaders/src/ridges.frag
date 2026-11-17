// Ridgelines: layered foothills under a sky that follows the real sun; haze drifts between the layers.
// c0 night sky (top), c1 night sky (low), c2 day sky (top), c3 day sky (low) and haze, c4 horizon glow.
void main() {
    vec2 px = layoutPx();
    float yN = qt_TexCoord0.y;
    float x = px.x / unit;
    float sun = env.y;
    float day = smoothstep(-0.10, 0.25, sun);
    float twilight = exp(-pow(sun / 0.17, 2.0));
    float hz = 0.56;
    vec3 skyTop = mix(c0.rgb, c2.rgb, day);
    vec3 skyLow = mix(c1.rgb, c3.rgb, day);
    vec3 col = mix(skyTop, skyLow, smoothstep(0.0, hz, yN));
    float band = exp(-pow((yN - hz + 0.02) / 0.15, 2.0));
    col = mix(col, c4.rgb, band * (0.24 + 0.60 * twilight + 0.10 * day) * (1.0 + audio.x * 0.3));
    vec2 cell = floor(px / 2.0);
    float star = step(0.9987, hash(cell)) * (0.55 + 0.45 * sin(time * 60.0 + hash(cell + 3.0) * 40.0));
    col += star * 0.6 * (1.0 - day) * smoothstep(hz, hz - 0.25, yN);
    vec3 far = mix(skyLow, mix(c2.rgb, c3.rgb, 0.4), 0.55);
    vec3 near = mix(c0.rgb * 0.60, c1.rgb * 0.7, day * 0.5);
    float fwy = 1.2 / size.y;
    for (int i = 0; i < 6; i++) {
        float t = float(i) / 5.0;
        // nearer layers slide further when the desktop changes
        float xs = x * (1.0 + t * 0.7) + env.z * (0.25 + t * 1.1) + float(i) * 13.7;
        float prof = fbm(vec2(xs * 1.5, float(i) * 5.0)) * 0.8 + gnoise(vec2(xs * 6.5, float(i) * 9.0)) * 0.12;
        float top = hz - 0.05 + t * 0.36 + (prof - 0.46) * (0.08 + 0.10 * t);
        // haze lying in front of the previous layer, drifting sideways
        float haze = fbm(vec2(xs * 0.7 + time * (1.5 + t * 2.0), float(i) * 3.0 + time * 0.3));
        col = mix(col, mix(skyLow, c4.rgb, 0.18 * twilight), (1.0 - t) * 0.30 * smoothstep(0.35, 0.75, haze)
                       * smoothstep(top - 0.10, top + 0.02, yN) * (1.0 + wake(px, 300.0)));
        vec3 rc = mix(far, near, pow(t, 0.8));
        rc += c3.rgb * 0.16 * exp(-max(yN - top, 0.0) / 0.012) * (1.0 - t * 0.6);      // light catching each crest
        col = mix(col, rc, smoothstep(top - fwy, top + fwy, yN));
    }
    fragColor = finish(col);
}
