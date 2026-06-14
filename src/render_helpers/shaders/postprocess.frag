uniform float noise;
uniform float saturation;
uniform vec4 bg_color;
uniform vec4 tint_color;
uniform float tint_amount;
uniform float edge_highlight;
uniform float refraction;

// Sin-less white noise by David Hoskins (MIT License).
// https://www.shadertoy.com/view/4djSRW
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 saturate(vec3 color, float sat) {
    const vec3 w = vec3(0.2126, 0.7152, 0.0722);
    return mix(vec3(dot(color, w)), color, sat);
}

float glass_edge_strength(vec2 coords_geo) {
    vec2 coords = clamp(coords_geo, vec2(0.0), vec2(1.0));
    vec2 edge = min(coords, vec2(1.0) - coords);
    float edge_dist = min(edge.x, edge.y);
    float size = max(max(geo_size.x, geo_size.y), 1.0);
    float pixel = max(1.5 / size, 0.001);

    float rim = 1.0 - smoothstep(0.0, 0.075 + pixel * 8.0, edge_dist);
    float top_light = 1.0 - smoothstep(0.0, 0.32, coords.y);
    float left_light = 1.0 - smoothstep(0.0, 0.24, coords.x);

    return clamp(rim * 0.66 + top_light * 0.28 + left_light * 0.10, 0.0, 1.0);
}

vec2 niri_refraction_offset(vec2 coords_geo) {
    float amount = clamp(refraction, 0.0, 0.05);
    if (amount <= 0.0) {
        return vec2(0.0);
    }

    vec2 coords = clamp(coords_geo, vec2(0.0), vec2(1.0));
    vec2 center_dir = coords - vec2(0.5);
    vec2 normal = normalize(center_dir + vec2(0.0001, -0.0001));
    float edge = glass_edge_strength(coords);
    float shimmer = hash12(coords * geo_size * 0.08) - 0.5;

    return normal * amount * edge + vec2(shimmer, -shimmer) * amount * 0.18;
}

vec4 postprocess(vec4 color, vec2 coords_geo) {
    if (saturation != 1.0) {
        color.rgb = saturate(color.rgb, saturation);
    }

    if (noise > 0.0) {
        vec2 uv = gl_FragCoord.xy;
        color.rgb += (hash12(uv) - 0.5) * noise;
    }

    // Mix bg_color behind the texture (both premultiplied alpha).
    color = color + bg_color * (1.0 - color.a);

    float tint_mix = clamp(tint_amount * tint_color.a, 0.0, 1.0);
    if (tint_mix > 0.0) {
        color.rgb = mix(color.rgb, tint_color.rgb * color.a, tint_mix);
    }

    float highlight = glass_edge_strength(coords_geo) * clamp(edge_highlight, 0.0, 1.0);
    if (highlight > 0.0) {
        color.rgb += vec3(highlight * color.a * 0.22);
    }

    return color;
}
