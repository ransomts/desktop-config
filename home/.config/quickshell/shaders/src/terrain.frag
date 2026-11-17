// Terrain: the real land around Clemson as a contour map (assets/terrain-clemson.png:
// height packed in red/green, lakes in blue), drifting very slowly. Lines every 20 m,
// every fifth in the accent; Hartwell, Keowee and Jocassee are flat fills.
layout(binding = 1) uniform sampler2D terrain;

vec2 texel(ivec2 i, ivec2 n) {                  // metres, water 0..1
    ivec2 m = n * 2, j = ((i % m) + m) % m;     // mirrored repeat past the map's edge
    j = min(j, m - 1 - j);
    vec4 t = texelFetch(terrain, j, 0);
    return vec2(100.0 + (t.r * 65280.0 + t.g * 255.0) / 65535.0 * 2000.0, t.b);
}
vec2 land(vec2 uv) {
    ivec2 n = textureSize(terrain, 0);
    vec2 p = uv * vec2(n) - 0.5, f = fract(p);
    ivec2 i = ivec2(floor(p));
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(texel(i, n), texel(i + ivec2(1, 0), n), f.x),
               mix(texel(i + ivec2(0, 1), n), texel(i + ivec2(1, 1), n), f.x), f.y);
}
void main() {
    vec2 px = layoutPx();
    vec2 n = vec2(textureSize(terrain, 0));
    float s = max(2.0, box.z / n.x);            // screen px per map px: the whole layout fits the map's width
    // the middle of the layout looks at the lakes and the escarpment north-west of Clemson
    vec2 look = vec2(0.50, 0.44) + vec2(sin(time * 0.9), cos(time * 0.7)) * 0.03 + vec2(env.z * 0.04, 0.0);
    vec2 uv = look + (px - (box.xy + box.zw * 0.5)) / (s * n);
    vec2 l = land(uv);
    float m = l.x + wake(px, 300.0) * 12.0;
    float shade = clamp((dFdx(m) - dFdy(m)) * 0.02 / max(s * 0.4, 0.5), -1.0, 1.0);   // lit from the north-west

    float v = m / 20.0, fw = fwidth(v);
    float minor = (1.0 - smoothstep(0.0, 1.3 * fw, abs(fract(v - 0.5) - 0.5))) * smoothstep(0.45, 0.12, fw);
    float vi = m / 100.0, fwi = fwidth(vi);
    float index = (1.0 - smoothstep(0.0, 1.5 * fwi, abs(fract(vi - 0.5) - 0.5))) * smoothstep(0.60, 0.20, fwi);
    // a slow survey sweep: lines near one rising elevation glow a little
    float sweep = exp(-pow((m - (180.0 + 900.0 * fract(time * 1.5))) / 30.0, 2.0));

    vec3 col = mix(c0.rgb, c1.rgb, smoothstep(150.0, 1300.0, m));
    col += shade * 0.035 * (c2.rgb + 0.3);
    col = mix(col, mix(c0.rgb, c2.rgb, 0.48 + sweep * 0.35), minor * 0.80);
    col = mix(col, mix(c4.rgb, c3.rgb, smoothstep(250.0, 500.0, m) * 0.75), index * (0.80 + audio.w * 0.3));
    float lake = smoothstep(0.35, 0.65, l.y);
    col = mix(col, mix(c0.rgb, c3.rgb, 0.34), lake);
    float fl = fwidth(l.y);
    col = mix(col, c3.rgb, (1.0 - smoothstep(0.0, 1.5 * fl + 1e-4, abs(l.y - 0.5))) * step(1e-4, fl) * 0.8);
    fragColor = finish(col);
}
