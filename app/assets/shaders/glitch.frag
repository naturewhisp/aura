#version 460 core
#include <flutter/runtime_effect.glsl>

// Uniforms injected from Flutter runtime
uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity; // Scaled by dissonance value
uniform sampler2D uTexture;

out vec4 fragColor;

float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    
    // Glitch noise calculation
    float scanline = sin(uv.y * 100.0 + uTime * 30.0);
    float noise = rand(vec2(floor(uv.y * 20.0), uTime));
    
    float shift = 0.0;
    if (noise < 0.15 * uIntensity) {
        // Horizontal displacement
        shift = sin(uTime * 50.0) * 0.03 * uIntensity;
    }
    
    // Add micro scanline shift
    shift += scanline * 0.002 * uIntensity;

    // Chromatic Aberration RGB Shift
    float r = texture(uTexture, vec2(uv.x + shift, uv.y)).r;
    float g = texture(uTexture, vec2(uv.x, uv.y)).g;
    float b = texture(uTexture, vec2(uv.x - shift, uv.y)).b;
    float a = texture(uTexture, vec2(uv.x, uv.y)).a;

    // Output final color
    fragColor = vec4(r, g, b, a);
}
