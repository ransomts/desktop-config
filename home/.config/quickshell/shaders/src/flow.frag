// Flow: long thin strokes travelling along an invisible, slowly shifting current, like a wind map. A few are the accent.
void main() {
    vec2 px = layoutPx();
    vec2 p = px / unit * 1.25 + vec2(env.z * 0.7, 0.0);
    float w = wake(px, 300.0);

    // Stream function: a prevailing left-to-right current, bent by two slow noise fields.
    float n1 = fbm(p * vec2(0.80, 1.30) + vec2(time * 0.30, -time * 0.18));
    float n2 = fbm(p * 0.45 + vec2(-time * 0.12, time * 0.10) + 31.7);
    float psi = p.y + (n1 - 0.5) * 0.55 + (n2 - 0.5) * 0.90 + w * 0.04;

    // Streamlines are the contour lines of psi.
    float v = psi * 54.0;
    float fw = fwidth(v);
    float d = abs(fract(v - 0.5) - 0.5);
    float lvl = floor(v + 0.5);
    float h1 = hash(vec2(lvl, 3.7));        // length and speed
    float h2 = hash(vec2(lvl, 91.3));       // phase
    float h3 = hash(vec2(lvl, 47.1));       // colour and brightness

    // Break each line into strokes that slide downstream: faded tail, firmer head.
    float along = p.x + (n2 - 0.5) * 0.35;
    float t = fract(along * (1.6 + 1.8 * h1) - time * (5.0 + 7.0 * h2) + h2 * 13.0);
    float len = 0.22 + 0.50 * h3;
    float st = smoothstep(0.0, len * 0.75, t) * (1.0 - smoothstep(len * 0.88, len, t));

    // Thin anti-aliased line, narrowing toward the stroke's ends; drop it where lines crowd.
    float line = (1.0 - smoothstep(0.0, fw * (0.5 + 0.9 * st), d)) * st;
    line *= 1.0 - smoothstep(0.30, 0.60, fw);

    // Calmer and busier regions, so the pattern slowly re-forms.
    float gust = smoothstep(0.30, 0.70, n1);
    float wgt = (0.30 + 0.55 * gust) * (0.55 + 0.45 * h1) * (1.0 + w * 0.6) + audio.w * 0.10 + audio.x * 0.06;

    vec3 lc = mix(c0.rgb, c2.rgb, 0.50 + 0.30 * h1);
    if (h3 < 0.06) { lc = c4.rgb; wgt *= 1.15; }
    else if (h3 < 0.26) { lc = c3.rgb; }

    vec3 col = mix(c0.rgb, c1.rgb, smoothstep(0.35, 0.90, n2) * 0.8);
    col = mix(col, lc, clamp(line * wgt, 0.0, 1.0));
    fragColor = finish(col);
}
