//
//  LiquidRipple.metal
//  Lyre
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The cover seen through water with rings running across it (see LiquidRipple.swift).
//
// Each drop is four floats: where it landed (x, y, in points), when (seconds, on the same
// clock as `time`), and how hard (0 to 1). A drop sends out a ring: a short train of
// crests behind a leading front, spreading at a steady speed, lower the further it has
// gone and the longer it has run. Nothing here draws the water itself. The cover is
// seen through it, bent where the surface slopes, and the slopes facing the light catch
// a glint, as a real ripple over a picture does.
[[ stitchable ]] half4 liquidRipple(float2 position, SwiftUI::Layer layer, float2 size,
                                    float time, device const float *drops, int count) {
    const float speed = 230.0;        // points a second the front travels
    const float wavelength = 26.0;    // crest to crest
    const float ahead = 14.0;         // how soon the water ahead of the front is still
    const float behind = 60.0;        // how long the train of crests behind it runs
    const float fade = 0.9;           // seconds for a ring to lose most of its height
    const float k = 2.0 * M_PI_F / wavelength;

    // The surface's slope, as a fraction of the steepest a ring of strength 1 gets.
    float2 slope = float2(0.0);
    for (int i = 0; i + 3 < count; i += 4) {
        float age = time - drops[i + 2];
        if (age < 0.0 || age > 3.0) { continue; }
        float2 out = position - float2(drops[i], drops[i + 1]);
        float d = length(out);
        if (d < 0.001) { continue; }
        float u = d - speed * age;
        float w = u > 0.0 ? ahead : behind;
        float envelope = exp(-(u * u) / (w * w));
        float height = drops[i + 3] * exp(-age / fade) * rsqrt(1.0 + d / 90.0);
        // d/dd of envelope × cos(k u), over k so a full crest's slope is about 1.
        float dEnvelope = -2.0 * u / (w * w) * envelope;
        float dh = height * (dEnvelope * cos(k * u) / k - envelope * sin(k * u));
        slope += (out / d) * dh;
    }

    // The light through the surface bends with its slope, up to a few points …
    float2 bent = clamp(position - slope * 7.0, float2(0.5), size - 0.5);
    half4 color = layer.sample(bent);
    // … and a slope turned toward the light (from above, a little to the left) is a
    // shade brighter, the steepest of them catching a glint; one turned away, darker.
    float facing = dot(slope, normalize(float2(-0.35, -1.0)));
    float shade = clamp(facing * 0.09, -0.07, 0.07);
    float glint = pow(saturate(facing), 5.0) * 0.28;
    color.rgb = color.rgb * half(1.0 + shade) + half(glint) * color.a;
    return color;
}
