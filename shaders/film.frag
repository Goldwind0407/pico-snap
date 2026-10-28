#version 460 core

// A filter's full look on the GPU, for the live viewfinder: the same 3D LUT,
// softening, halation and density grain as finishFilm() in color_grade.dart.

#include <flutter/runtime_effect.glsl>

precision highp float;

// Set by the engine: the size of the filtered picture, in pixels.
uniform vec2 uSize;
// soften, halation, grain, unused.
uniform vec4 uFx;
// Halation colour.
uniform vec3 uGlow;
// Set by the engine: the picture being filtered.
uniform sampler2D uInput;
// The LUT as 33 slices side by side: x = blue slice * 33 + red, y = green.
uniform sampler2D uLut;

out vec4 fragColor;

const float N = 33.0;

vec4 src(vec2 px) {
  vec2 uv = clamp(px, vec2(.5), uSize - .5) / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uInput, uv);
}

float luma(vec3 c) {
  return dot(c, vec3(.2126, .7152, .0722));
}

vec3 grade(vec3 c) {
  c = clamp(c, 0.0, 1.0) * (N - 1.0);
  float b0 = min(floor(c.b), N - 2.0);
  vec2 rg = c.rg + .5;
  vec2 scale = vec2(1.0 / (N * N), 1.0 / N);
  vec3 lo = texture(uLut, vec2(b0 * N + rg.x, rg.y) * scale).rgb;
  vec3 hi = texture(uLut, vec2((b0 + 1.0) * N + rg.x, rg.y) * scale).rgb;
  return mix(lo, hi, c.b - b0);
}

// Hash noise in -1..1, fixed per pixel so the grain doesn't crawl.
float noise(vec2 p) {
  p = fract(p * vec2(.1031, .1030));
  p += dot(p, p.yx + 33.33);
  return fract((p.x + p.y) * p.x) * 2.0 - 1.0;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec4 c0 = src(px);
  // Straight colour; the camera is opaque, but keep edges right.
  vec3 c = c0.a > 0.0 ? c0.rgb / c0.a : vec3(0.0);
  if (uFx.x > 0.0) {
    // A small blur mixed in, like the photo's box blur.
    float r = max(1.0, max(uSize.x, uSize.y) / 1100.0);
    vec3 b = c0.rgb;
    for (int y = -1; y <= 1; y++) {
      for (int x = -1; x <= 1; x++) {
        if (x != 0 || y != 0) b += src(px + vec2(float(x), float(y)) * r).rgb;
      }
    }
    b /= 9.0;
    c = mix(c, c0.a > 0.0 ? b / c0.a : b, uFx.x * .55);
  }
  c = grade(c);
  if (uFx.y > 0.0) {
    // Bright parts of the original spread out in rings, then screen-blended.
    float reach = .035 * min(uSize.x, uSize.y);
    float m = smoothstep(.7, .97, luma(c0.rgb)) * 2.0, w = 2.0;
    for (int i = 0; i < 3; i++) {
      for (int k = 0; k < 8; k++) {
        float a = (float(k) + float(i) * .5) * .7853982;
        float wt = 1.0 - float(i) * .25;
        vec3 s = src(px + vec2(cos(a), sin(a)) * reach * (.6 + float(i) * .7)).rgb;
        m += smoothstep(.7, .97, luma(s)) * wt;
        w += wt;
      }
    }
    vec3 g = clamp(m / w * uFx.y * 1.6 * uGlow, 0.0, 1.0);
    c = 1.0 - (1.0 - c) * (1.0 - g);
  }
  if (uFx.z > 0.0) {
    // Mid tones carry the most grain, like silver halide density.
    float l = luma(c);
    float a = uFx.z * 30.0 / 255.0 * (.2 + 3.2 * l * (1.0 - l));
    vec2 ip = floor(px);
    c += (noise(ip) * .7 + noise(floor(ip * .5) + 9173.0) * .3) * a;
  }
  fragColor = vec4(clamp(c, 0.0, 1.0) * c0.a, c0.a);
}
