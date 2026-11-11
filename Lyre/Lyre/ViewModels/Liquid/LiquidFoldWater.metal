//
//  LiquidFoldWater.metal
//  Lyre
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The water at an open iPhone Duo's fold (see LiquidFoldWater.swift).

// A bubble pushed through the surface, seen through the water: the part past the fold
// (`fold`, along the bubble's own way in: x, or y when `across`) bends with a gentle,
// moving waver, is a shade darker and cooler, and a bright line marks the surface where
// it crosses it. The rest of the bubble is as it is.
[[ stitchable ]] half4 foldRefraction(float2 position, SwiftUI::Layer layer,
                                      float fold, float across, float time) {
    float along = across > 0.5 ? position.y : position.x;
    float side = across > 0.5 ? position.x : position.y;
    float depth = fold - along;
    if (depth <= -3.0) { return layer.sample(position); }
    // The surface line itself, bright, either side of the crossing.
    float line = exp(-(depth * depth) / 5.0);
    if (depth <= 0.0) {
        half4 c = layer.sample(position);
        c.rgb += half(line * 0.3) * c.a;
        return c;
    }
    float k = saturate(depth / 14.0);
    float waver = sin(side * 0.11 + time * 5.0) * 2.4 + sin(side * 0.23 - time * 3.1) * 1.1;
    float2 offset = across > 0.5 ? float2(waver, depth * 0.08) : float2(depth * 0.08, waver);
    half4 c = layer.sample(position + offset * k);
    c.rgb *= half(1.0 - 0.12 * k);
    c.rgb += half(0.06 * k) * half3(0.55, 0.75, 1.0) * c.a;
    c.rgb += half(line * 0.3) * c.a;
    return c;
}

static float foldHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float foldNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(foldHash(i), foldHash(i + float2(1.0, 0.0)), u.x),
               mix(foldHash(i + float2(0.0, 1.0)), foldHash(i + float2(1.0, 1.0)), u.x), u.y);
}

static float foldFBM(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * foldNoise(p);
        p = p * 2.03 + 17.0;
        amplitude *= 0.5;
    }
    return value;
}

// A bubble's colour spreading through Now Playing like ink dropped in water, from where
// it went in (`origin`, in the page's points), as `progress` goes from 0 to 1: an uneven
// front pushed out by slow noise, threaded with darker tendrils, thinning to nothing over
// the last half so the cover underneath (the album now playing) comes through.
[[ stitchable ]] half4 inkSpread(float2 position, half4 color, float2 size, float2 origin,
                                 float progress, float seed) {
    float d = distance(position, origin);
    float reach = length(size) * 1.15;
    float n = foldFBM(position * 0.011 + seed);
    float front = progress * reach * (0.6 + 0.8 * n);
    float body = 1.0 - smoothstep(front - 36.0, front, d);
    float tendrils = smoothstep(0.35, 0.75, foldFBM(position * 0.03 + seed * 2.0 + progress));
    float alpha = body * mix(0.65, 1.0, tendrils);
    alpha *= 1.0 - smoothstep(0.5, 1.0, progress);
    alpha *= 0.85;
    return half4(color.rgb * half(alpha), half(alpha));
}
