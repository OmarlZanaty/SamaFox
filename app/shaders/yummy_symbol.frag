#version 460 core
#include <flutter/runtime_effect.glsl>

// YUMMY: draws one symbol texture with a moving glint and an optional win
// flash, in one pass (no saveLayer per cell). The glint only lands on the
// symbol's own pixels because it is scaled by the texture's alpha.

uniform vec2 uOrigin;      // top-left of the cell in canvas pixels
uniform vec2 uSize;        // drawn size in pixels
uniform float uProgress;   // glint position 0..1 (outside = none)
uniform float uFlash;      // 0..1 extra brightness for wins
uniform float uAlpha;      // overall opacity
uniform sampler2D uImage;

out vec4 fragColor;

void main() {
    vec2 uv = (FlutterFragCoord().xy - uOrigin) / uSize;
    vec4 c = texture(uImage, clamp(uv, 0.0, 1.0));
    float d = (uv.x * 0.8 + uv.y * 0.45) / 1.25;
    float center = mix(-0.25, 1.25, uProgress);
    float dist = abs(d - center);
    float band = (1.0 - smoothstep(0.0, 0.16, dist)) * 0.55
               + (1.0 - smoothstep(0.0, 0.035, dist)) * 0.45;
    vec3 rgb = c.rgb + vec3(1.0, 0.97, 0.88) * c.a * (band * 0.85 + uFlash * 0.35);
    fragColor = vec4(min(rgb, vec3(c.a)), c.a) * uAlpha;
}
