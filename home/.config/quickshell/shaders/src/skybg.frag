// Backdrop for the real night sky (WallSky.qml draws the stars over it): sky gradient by the sun's
// altitude, a glow along the horizon, and the ground. relief = horizon height as a fraction of the
// whole layout's height. Colours as in ridges.frag.
void main() {
    vec2 px = layoutPx();
    float sun = env.y;
    float day = smoothstep(-0.10, 0.25, sun) * (1.0 - env.w * 0.85);       // dark mode keeps the sky dark
    float twilight = exp(-pow(sun / 0.17, 2.0));
    float yH = relief;                                  // layout px of the horizon, set by QML
    float up = (yH - px.y) / max(yH, 1.0);               // 0 at the horizon .. 1 at the top
    vec3 skyTop = mix(c0.rgb, c2.rgb, day);
    vec3 skyLow = mix(c1.rgb, c3.rgb, day);
    vec3 col = mix(skyLow, skyTop, smoothstep(0.0, 0.9, up));
    col = mix(col, c4.rgb, exp(-pow(up / 0.13, 2.0)) * (0.10 + 0.60 * twilight + 0.10 * day));
    // the ground: a low treeline silhouette
    float x = px.x / unit;
    float ridge = (fbm(vec2(x * 3.0, 1.0)) - 0.5) * 26.0 + (gnoise(vec2(x * 14.0, 4.0)) - 0.5) * 8.0;
    float g = smoothstep(-1.0, 1.0, px.y - (yH + ridge - 6.0));
    col = mix(col, mix(c0.rgb * 0.45, c1.rgb * 0.5, day), g);
    fragColor = finish(col);
}
