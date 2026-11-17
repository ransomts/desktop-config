// Silk: slow, lit folds. Height field from domain-warped noise, coloured by the ramp.
float height(vec2 p, float t) {
    vec2 q = vec2(fbm(p + vec2(0.0, t * 0.60)), fbm(p + vec2(5.2, 1.3) - t * 0.45));
    vec2 r = vec2(fbm(p + 3.0 * q + vec2(1.7, 9.2) + t * 0.30), fbm(p + 3.0 * q + vec2(8.3, 2.8) - t * 0.25));
    return fbm(p + 3.2 * r);
}
void main() {
    vec2 px = layoutPx();
    // long diagonal ribbons rather than round blobs; each desktop is a different stretch of cloth
    vec2 p = mat2(0.82, -0.57, 0.57, 0.82) * (px / unit) * vec2(0.55, 1.25) + vec2(env.z * 0.9, env.z * 0.35);
    float h = height(p, time) + wake(px, 280.0) * 0.07 + audio.x * 0.035 * sin(p.x * 3.0 + time * 40.0);
    float t = clamp((h - 0.20) / 0.60, 0.0, 1.0);
    vec3 col = ramp(t);
    // light the surface as if h were a height: soft shading plus a sheen on the folds
    vec2 g = vec2(dFdx(h), dFdy(h)) * unit;
    vec3 n = normalize(vec3(-g * relief * (1.0 + audio.y * 0.5), 1.0));
    float lit = dot(n, normalize(vec3(-0.45, -0.60, 0.66)));
    col *= 0.62 + 0.58 * lit;
    col += c4.rgb * pow(max(lit, 0.0), 14.0) * (0.10 + 0.25 * audio.w);
    fragColor = finish(col);
}
