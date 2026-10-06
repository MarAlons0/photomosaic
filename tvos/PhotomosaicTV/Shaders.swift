/*
 * Metal shaders, compiled at launch from source (no Metal Toolchain needed at build time).
 */
enum Shaders {
    static let source = """
// Tile rendering: one textured quad per tile, positioned in pixels.
// Small tiles sample a shared atlas (texture array of 96x54 micros); larger
// tiles and the full-screen photo sample their own texture.
#include <metal_stdlib>
using namespace metal;

struct TileInstance {
    float4 rect;    // x0, y0, x1, y1 in pixels, origin top-left
    float4 uv;      // u0, v0, u1, v1
    float  page;    // atlas slice
    float  alpha;
    float2 pad;
};

struct Uniforms {
    float2 viewport;
};

struct VOut {
    float4 position [[position]];
    float2 uv;
    float  page;
    float  alpha;
};

vertex VOut tileVertex(uint vid [[vertex_id]],
                       uint iid [[instance_id]],
                       constant TileInstance *tiles [[buffer(0)]],
                       constant Uniforms &u [[buffer(1)]]) {
    TileInstance t = tiles[iid];
    float2 corner = float2(vid & 1, vid >> 1);   // triangle strip (0,0) (1,0) (0,1) (1,1)
    float2 p = mix(t.rect.xy, t.rect.zw, corner);
    VOut o;
    o.position = float4(p.x / u.viewport.x * 2 - 1, 1 - p.y / u.viewport.y * 2, 0, 1);
    o.uv = mix(t.uv.xy, t.uv.zw, corner);
    o.page = t.page;
    o.alpha = t.alpha;
    return o;
}

fragment float4 atlasFragment(VOut in [[stage_in]],
                              texture2d_array<float> atlas [[texture(0)]],
                              sampler s [[sampler(0)]]) {
    return float4(atlas.sample(s, in.uv, uint(in.page)).rgb, in.alpha);
}

fragment float4 singleFragment(VOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               sampler s [[sampler(0)]]) {
    return float4(tex.sample(s, in.uv).rgb, in.alpha);
}
"""
}
