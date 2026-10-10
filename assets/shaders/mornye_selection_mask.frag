#include <flutter/runtime_effect.glsl>

uniform vec4 uRect;
uniform vec2 uScale;
uniform float uRadius;
uniform vec4 uColor;

out vec4 fragColor;

void main() {
  vec2 center = uRect.xy + uRect.zw * 0.5;
  vec2 halfSize = uRect.zw / uScale * 0.5;
  vec2 position = (FlutterFragCoord().xy - center) / uScale;
  vec2 corner = abs(position) - halfSize + vec2(uRadius);
  float distance = length(max(corner, vec2(0.0)))
      + min(max(corner.x, corner.y), 0.0) - uRadius;
  float coverage = 1.0 - smoothstep(-0.5, 0.5, distance);
  fragColor = vec4(uColor.rgb * uColor.a, uColor.a) * coverage;
}
