#version 460 core
#include <flutter/runtime_effect.glsl>

// Bloom for the crash game's flight layer.
//
// Runs as a post-process: the flight art (curve, plane, trail) is rendered to a
// half-resolution texture, this shader extracts the bright parts and blurs them
// in a two-ring spiral, and the result is composited back with BlendMode.plus.
// Half res is deliberate — the output is blurry by definition, so the lost
// detail costs nothing and the tap count stays affordable on mid-range phones.

uniform vec2 uSize;        // texture size in pixels
uniform float uIntensity;  // overall bloom strength
uniform float uThreshold;  // luminance below which nothing blooms
uniform float uRadius;     // blur radius in pixels
uniform sampler2D uTexture;

out vec4 fragColor;

const float TAU = 6.2831853;
const int ANGLES = 8;

// Keeps only what is brighter than the threshold, easing in so the bloom does
// not pop on as the multiplier brightens the curve.
vec3 brightPass(vec3 c) {
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    return c * smoothstep(uThreshold, uThreshold + 0.28, l);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;

    vec3 bloom = brightPass(texture(uTexture, uv).rgb);
    float total = 1.0;

    // Two rings of taps. The inner ring carries most of the weight; the outer
    // one spreads the halo. Offset each ring's angle so the taps interleave
    // instead of lining up into spokes.
    for (int r = 1; r <= 2; r++) {
        float radius = uRadius * float(r);
        float weight = 1.0 / float(r);
        float phase = float(r) * 0.3927; // half-step the second ring

        for (int i = 0; i < ANGLES; i++) {
            float a = phase + TAU * float(i) / float(ANGLES);
            vec2 off = vec2(cos(a), sin(a)) * radius / uSize;
            bloom += brightPass(texture(uTexture, uv + off).rgb) * weight;
            total += weight;
        }
    }

    bloom = bloom / total * uIntensity;

    // Premultiplied output for additive compositing.
    float a = clamp(max(max(bloom.r, bloom.g), bloom.b), 0.0, 1.0);
    fragColor = vec4(bloom, a);
}
