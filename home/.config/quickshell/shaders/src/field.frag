// Field: field lines looping between a dozen slowly drifting charges, with faint equipotentials. Positive poles are accent dots.
// The charges repeat every FIELD_L units in x as an exact periodic sum (complex potential log sin), so there are no cell seams.
const float FIELD_L = 6.0;        // period in x, in units; wider than the whole layout
const float FIELD_K = 3.14159265 / FIELD_L;
const float FIELD_N = 15.0;       // lines leaving each pole; keep a multiple of 5 so the fifth-line colour survives the atan cut
const int FIELD_POLES = 12;       // even, signs alternate, so the net charge is zero

void main() {
    vec2 px = layoutPx();
    vec2 p = px / unit + vec2(env.z * 0.7, 0.0);
    float psi = 0.0, phi = 0.0;   // stream function (field lines) and potential
    vec2 g = vec2(0.0);           // analytic gradient, so no fwidth across the branch cut
    float mP = 1e9, mN = 1e9;     // squared distance to the nearest + and - pole
    for (int n = 0; n < FIELD_POLES; n++) {
        float i = float(n);
        float q = mod(i, 2.0) < 0.5 ? 1.0 : -1.0;
        vec2 h = vec2(hash(vec2(i, 1.3)), hash(vec2(i, 7.9)));
        vec2 c = vec2((i + 0.5) * FIELD_L / float(FIELD_POLES) + (h.x - 0.5) * 0.3,
                      0.14 + 1.0 * fract(i * 0.618034 + 0.1));
        c += 0.17 * vec2(sin(time * (0.55 + 0.5 * h.y) + h.x * 6.2831853),
                         cos(time * (0.45 + 0.5 * h.x) + h.y * 6.2831853));
        vec2 w = (p - c) * FIELD_K;
        float sa = sin(w.x), ca = cos(w.x);
        float e = exp(w.y);
        float sh = 0.5 * (e - 1.0 / e), ch = 0.5 * (e + 1.0 / e);
        float m = max(sa * sa + sh * sh, 1e-8);          // |sin(w)|^2, about (K r)^2 near the pole
        psi += q * atan(ca * sh, sa * ch + 1e-7);        // arg sin(w)
        phi += q * 0.5 * log(m);                         // log |sin(w)|
        g += q * vec2(sa * ca, -sh * ch) / m;            // cot(w)
        if (q > 0.0) mP = min(mP, m); else mN = min(mN, m);
    }
    float toPx = unit / FIELD_K;
    float rP = sqrt(mP) * toPx, rN = sqrt(mN) * toPx;    // px to the nearest pole of each sign
    float fade = smoothstep(9.0, 42.0, min(rP, rN));     // no bright knot where the lines converge

    // v changes by one per line; gv is its analytic rate per pixel, floored so saddles do not smear into blobs
    float gv = max(length(g) * FIELD_K / unit * FIELD_N / 6.2831853, 1e-5);
    float calm = smoothstep(0.0015, 0.0050, gv);     // where the field is nearly flat a line would swell into a band: fade it
    float wpx = 0.55 + audio.w * 0.35;
    float wk = wake(px, 300.0);

    float v = psi * FIELD_N / 6.2831853;
    float line = (1.0 - smoothstep(wpx, wpx + 1.2, abs(fract(v - 0.5) - 0.5) / gv)) * fade * calm;
    float u = phi * FIELD_N / 6.2831853 * 0.5;           // equipotentials at half the density
    float ring = (1.0 - smoothstep(0.4, 1.5, abs(fract(u - 0.5) - 0.5) / (gv * 0.5))) * fade * calm;

    vec3 col = mix(c0.rgb, c1.rgb, clamp(0.5 + 0.22 * phi, 0.0, 1.0) * 0.6);
    col = mix(col, mix(c0.rgb, c2.rgb, 0.5), ring * (0.22 + wk * 0.15));
    vec3 lc = mix(c0.rgb, c2.rgb, 0.50);
    float wgt = 0.80;
    if (mod(floor(v + 0.5), 5.0) < 0.5) { lc = c3.rgb; wgt = 0.85; }
    lc = mix(lc, c3.rgb, wk * 0.5);
    col = mix(col, lc, clamp(line * (wgt + wk * 0.2), 0.0, 1.0));

    // pole markers: a small accent dot on +, an open ring on -
    col = mix(col, c4.rgb, (1.0 - smoothstep(3.0, 4.5, rP)) * 0.9);
    col = mix(col, c3.rgb, (1.0 - smoothstep(0.5, 1.7, abs(rN - 5.0))) * 0.8);
    fragColor = finish(col);
}
