#include <metal_stdlib>
using namespace metal;

struct RippleUniforms {
    float4 originProgress;
    float4 direction;
    float4 waveform;
};

struct RippleVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex RippleVertexOut readerRippleVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    constexpr float2 coordinates[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    RippleVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = coordinates[vertexID];
    return out;
}

fragment float4 readerRippleFragment(
    RippleVertexOut in [[stage_in]],
    texture2d<float> oldPage [[texture(0)]],
    texture2d<float> newPage [[texture(1)]],
    constant RippleUniforms &u [[buffer(0)]]) {
    constexpr sampler pageSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    float2 origin = u.originProgress.xy;
    float progress = clamp(u.originProgress.z, 0.0, 1.0);
    float softEdge = max(u.originProgress.w, 0.0005);
    float2 axis = normalize(u.direction.xy);
    float2 perpendicular = float2(-axis.y, axis.x);
    float frequency = u.direction.z;
    float phaseAdvance = u.direction.w;
    float amplitude = u.waveform.x;
    float decay = max(u.waveform.y, 0.0);

    float2 relative = in.uv - origin;
    float projected = dot(relative, axis);
    // The supported directions are unit cardinal/diagonal vectors; this margin
    // leaves the whole image on the old page at 0 and the new page at 1.
    float projectionExtent = abs(axis.x) + abs(axis.y);
    float front = mix(-projectionExtent - softEdge, projectionExtent + softEdge, progress);
    float distanceToFront = projected - front;
    float envelope = exp(-abs(distanceToFront) * decay);
    float phase = distanceToFront * frequency + progress * phaseAdvance;
    float lateral = dot(relative, perpendicular);
    float lateralFalloff = 0.55 + 0.45 * smoothstep(-0.75, 0.75, lateral);

    float displacement = sin(phase) * envelope * amplitude * lateralFalloff;
    float2 warpedUV = clamp(
        in.uv + perpendicular * displacement,
        float2(0.0),
        float2(1.0)
    );
    float edgeBlend = smoothstep(-softEdge, softEdge, distanceToFront);
    float4 oldColor = oldPage.sample(pageSampler, warpedUV);
    float4 newColor = newPage.sample(pageSampler, warpedUV);
    return mix(oldColor, newColor, edgeBlend);
}
