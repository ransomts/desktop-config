#version 440
// Shared by every wallpaper scene (see ../Wallpaper.qml). Built by ./build.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;      // slow clock, in flow units
    float unit;      // pixels per noise unit
    float relief;    // lighting strength (silk); horizon height 0..1 (sky)
    vec2 origin;     // this screen's position in the whole layout, px
    vec2 size;       // this screen's size, px
    vec4 c0; vec4 c1; vec4 c2; vec4 c3; vec4 c4;     // the scene's colours, low to high
    vec4 stops;      // positions of c1..c4 on the ramp (c0 is at 0)
    vec4 audio;      // bass, mid, treble, overall level, each 0..1 (0 when nothing plays)
    vec4 pointer;    // xy pointer in layout px, z strength 0..1
    vec4 env;        // x time of day 0..1, y sin(sun altitude), z desktop number (animated), w dark 0..1
    vec4 wx;         // rain, fog, cloud, snow, each 0..1
    vec4 box;        // the whole monitor layout: x, y, width, height, px
};

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
vec2 grad(vec2 i) { float a = hash(i) * 6.2831853; return vec2(cos(a), sin(a)); }
float gnoise(vec2 p) {                       // gradient noise, about 0..1
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = dot(grad(i), f), b = dot(grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
    float c = dot(grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)), d = dot(grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.72 + 0.5;
}
float fbm(vec2 p) { return gnoise(p) * 0.72 + gnoise(p * 1.9 + vec2(17.1, 9.2)) * 0.28; }
vec3 ramp(float t) {
    vec3 c = mix(c0.rgb, c1.rgb, smoothstep(0.0, stops.x, t));
    c = mix(c, c2.rgb, smoothstep(stops.x, stops.y, t));
    c = mix(c, c3.rgb, smoothstep(stops.y, stops.z, t));
    return mix(c, c4.rgb, smoothstep(stops.z, stops.w, t));
}
vec2 layoutPx() { return origin + qt_TexCoord0 * size; }
// 0..1 bump around the pointer, radius in px
float wake(vec2 px, float radius) { vec2 d = px - pointer.xy; return pointer.z * exp(-dot(d, d) / (radius * radius)); }
vec4 finish(vec3 col) {
    col += (hash(qt_TexCoord0 * size) - 0.5) / 128.0;          // dither against banding
    return vec4(col, 1.0) * qt_Opacity;
}
