#version 460 core
#include <flutter/runtime_effect.glsl>

// YUMMY: a diagonal glint that sweeps across whatever it masks (the cabinet
// frame, the logo). Used through a ShaderMask with BlendMode.srcATop, so it
// only lights pixels the child already covers. Output is premultiplied.

uniform vec2 uSize;        // mask bounds in pixels
uniform float uProgress;   // 0..1 position of the sweep; outside = no glint
uniform float uWidth;      // band half-width as a fraction of the diagonal
uniform float uIntensity;  // 0..1

out vec4 fragColor;

void main() {
    vec2 p = FlutterFragCoord().xy / uSize;
    // Diagonal coordinate, top-left 0 → bottom-right 1, tilted like a window.
    float d = (p.x * 0.8 + p.y * 0.45) / 1.25;
    float center = mix(-uWidth, 1.0 + uWidth, uProgress);
    float dist = abs(d - center);
    float soft = 1.0 - smoothstep(0.0, uWidth, dist);
    float core = 1.0 - smoothstep(0.0, uWidth * 0.22, dist);
    float a = clamp((soft * 0.45 + core * 0.55) * uIntensity, 0.0, 1.0);
    fragColor = vec4(vec3(1.0, 0.97, 0.86) * a, a);
}
