// Pulsar: a stacked ridgeline plot. Nearer lines hide the ones behind; music swells the peaks. Every eighth line is the accent.
const float ROW = 28.0;            // row spacing, px
const float HMAX = 6.8 * ROW;      // tallest possible peak, px (must stay under 7 rows for the 9-row loop)

float vnoise1(float x, float seed) {         // cheap 1D value noise, 0..1
    float i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(hash(vec2(i, seed)), hash(vec2(i + 1.0, seed)), f);
}

// Height of row k at x (noise units), 0..1 before the gain is applied.
float ridge(float x, float k, float jitter) {
    float e = gnoise(vec2(x * 1.5 + time * 0.25, k * 0.035 - time * 0.15));   // where the clusters are
    e = 0.035 + 0.965 * smoothstep(0.42, 0.70, e);
    float n = smoothstep(0.20, 0.85, gnoise(vec2(x * 26.0, k * 13.7 + time * 16.0)));   // the peaks
    float j = vnoise1(x * 95.0 + time * 5.0, k);                              // fine teeth
    return e * n * sqrt(n) * (1.0 - jitter * j);
}

void main() {
    vec2 px = layoutPx();
    float x = px.x / unit + env.z * 0.7;
    float gain = min(0.58 + audio.x * 0.34 + wake(px, 300.0) * 0.10, 1.0) * HMAX;
    float jitter = 0.30 + audio.z * 0.45;
    float kf = floor(px.y / ROW);
    vec3 base = mix(c0.rgb, c2.rgb, 0.55);
    vec3 acc = vec3(0.0);
    float T = 1.0;                             // how much of the rows behind still shows
    for (int i = 8; i >= 0; i--) {             // front (lower on screen) to back
        float k = kf + float(i);
        float h = ridge(x, k, jitter) * gain;
        float s = dFdx(h);
        float d = (px.y - (k * ROW - h)) / sqrt(1.0 + s * s);     // > 0 under the curve
        float line = 1.0 - smoothstep(0.6, 1.4, abs(d));
        float tall = smoothstep(0.12, 0.55, h / HMAX);
        vec3 lc = mix(base, c3.rgb, tall * (0.80 + audio.y * 0.20));
        float wgt = 0.80;
        if (mod(k, 8.0) < 0.5) { lc = mix(mix(c0.rgb, c4.rgb, 0.50), c4.rgb, tall); wgt = 0.85 + audio.w * 0.15; }
        acc += T * line * wgt * (lc - c0.rgb);
        T *= 1.0 - max(line, smoothstep(-0.5, 0.5, d));
    }
    fragColor = finish(c0.rgb + acc);
}
