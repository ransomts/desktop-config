// Weather drawn over any scene: rain streaks, drifting fog, snow. Transparent where there is none.
void main() {
    vec2 px = layoutPx();
    float t = time * 80.0;                               // weather moves in real seconds, not flow time
    vec3 col = vec3(0.0); float a = 0.0;
    vec3 tint = mix(c3.rgb, vec3(1.0), 0.55);
    if (wx.x > 0.01) {                                   // rain: two layers of slanted streaks
        for (int i = 0; i < 2; i++) {
            float fi = float(i);
            vec2 q = vec2(px.x + px.y * 0.14, px.y) / (1.0 + fi * 0.6);
            float colx = floor(q.x / 5.0);
            float sp = 900.0 + 500.0 * hash(vec2(colx, fi));
            float yy = (q.y + t * sp * 0.012 + hash(vec2(colx, 7.0 + fi)) * 900.0) / 150.0;
            float drop = smoothstep(0.75, 1.0, fract(yy)) * step(1.0 - 0.10 - 0.30 * wx.x, hash(vec2(colx, floor(yy))));
            float thin = 1.0 - smoothstep(0.0, 0.9, abs(fract(q.x / 5.0) - 0.5) * 5.0);
            float s = drop * thin * (0.30 - 0.10 * fi) * wx.x;
            col += tint * s; a += s;
        }
    }
    if (wx.w > 0.01) {                                   // snow: slow drifting flakes
        for (int i = 0; i < 3; i++) {
            float fi = float(i); float sc = 46.0 + fi * 26.0;
            vec2 q = vec2(px.x + sin(t * 0.02 + px.y * 0.01 + fi) * 14.0, px.y - t * (0.5 + 0.25 * fi)) / sc;
            vec2 c = floor(q); vec2 f = fract(q) - 0.5;
            vec2 o = vec2(hash(c + fi) - 0.5, hash(c + 9.0 + fi) - 0.5) * 0.7;
            float flake = (1.0 - smoothstep(0.03, 0.07, length(f - o))) * step(1.0 - 0.45 * wx.w, hash(c + 21.0 + fi));
            float s = flake * (0.55 - 0.12 * fi);
            col += vec3(1.0) * s; a += s;
        }
    }
    if (wx.y > 0.01) {                                   // fog: soft banks drifting sideways
        float f = fbm(vec2(px.x / unit * 0.9 + t * 0.004, px.y / unit * 2.2 - t * 0.001));
        float s = smoothstep(0.30, 0.75, f) * 0.42 * wx.y * (0.55 + 0.45 * qt_TexCoord0.y);
        col += tint * s; a += s;
    }
    a = clamp(a, 0.0, 0.85);
    fragColor = vec4(min(col, vec3(a)), a) * qt_Opacity;
}
