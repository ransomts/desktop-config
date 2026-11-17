// Aurora: three curtains with a bright lower fringe, fading upward, over a starry dusk.
void main() {
    vec2 px = layoutPx();
    float yN = qt_TexCoord0.y;                         // 0 top .. 1 bottom of this screen
    float x = px.x / unit + env.z * 0.8;
    float t = time * 5.0;
    vec3 col = mix(c0.rgb * 0.85, c1.rgb, smoothstep(0.25, 1.0, yN) * 0.75);
    vec2 cell = floor(px / 2.0);
    float star = step(0.9988, hash(cell)) * (0.55 + 0.45 * sin(time * 60.0 + hash(cell + 3.0) * 40.0));
    col += star * 0.55 * (1.0 - yN) * (0.6 + 0.4 * env.w);
    float glow = wake(px, 320.0);
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float xs = x * (1.15 + 0.45 * fi) + fi * 7.3;
        float base = 0.76 - 0.17 * fi + 0.34 * (fbm(vec2(xs * 0.55 + t * 0.05 * (1.0 + fi * 0.3), fi * 3.1 + t * 0.02)) - 0.5);
        float d = base - yN;                           // > 0 above the curtain's lower edge
        float rays = 0.50 + 0.50 * gnoise(vec2(xs * 11.0 + t * 0.10, t * 0.05 + fi * 4.0));
        float body = smoothstep(-0.014, 0.0, d) * exp(-max(d, 0.0) * (3.4 + fi * 1.2));
        float inten = body * rays * (0.62 - 0.13 * fi) * (1.0 + audio.x * 0.9 + glow * 0.6);
        vec3 ac = mix(c4.rgb, c3.rgb, smoothstep(0.0, 0.09, d));
        ac = mix(ac, c2.rgb, smoothstep(0.07, 0.40, d));
        col += ac * inten;
    }
    fragColor = finish(col);
}
