in vec2 tex_coord;
layout (location = 0) out vec4 frag_color;
layout (binding = 0) uniform sampler2D provinces_texture_sampler;
layout (binding = 1) uniform sampler2D terrain_texture_sampler;
layout (binding = 3) uniform sampler2DArray terrainsheet_texture_sampler;
layout (binding = 4) uniform sampler2D water_normal;
layout (binding = 5) uniform sampler2D colormap_water;
layout (binding = 6) uniform sampler2D colormap_terrain;
layout (binding = 7) uniform sampler2D overlay;
layout (binding = 8) uniform sampler2DArray province_color;
layout (binding = 9) uniform sampler2D colormap_political;
layout (binding = 10) uniform sampler2D province_highlight;
layout (binding = 11) uniform sampler2D stripes_texture;
layout (binding = 13) uniform sampler2D province_fow;
layout (binding = 15) uniform usampler2D diag_border_identifier;

// location 0 : offset
// location 1 : zoom
// location 2 : screen_size
layout (location = 3) uniform vec2 map_size;
layout (location = 4) uniform float time;

layout (location = 11) uniform float gamma;
vec4 gamma_correct(vec4 colour) {
	return vec4(pow(colour.rgb, vec3(1.f / gamma)), colour.a);
}

// sheet is composed of 64 files, in 4 cubes of 4 rows of 4 columns
// so each column has 8 tiles, and each row has 8 tiles too
float xx = 1 / map_size.x;
float yy = 1 / map_size.y;
vec2 pix = vec2(xx, yy);

vec2 get_corrected_coords(vec2 coords) {
	coords.y -= (1 - 1 / 1.3) * 3 / 5;
	coords.y *= 1.3;
	return coords;
}

subroutine vec4 get_land_class();
layout(location = 0) subroutine uniform get_land_class get_land;

subroutine vec4 get_water_class();
layout(location = 1) subroutine uniform get_water_class get_water;

// The water effect
layout(index = 3) subroutine(get_water_class)
vec4 get_water_terrain()
{
	vec2 prov_id = texture(provinces_texture_sampler, tex_coord).xy;

	// Water effect taken from Vic2 fx/water/PixelShader_HoiWater_2_0
	const float WRAP = 0.8f;
	const float WaveModOne = 3.0f;
	const float WaveModTwo = 5.0f;
	const float SpecValueOne = 4.0f;
	const float SpecValueTwo = 2.0f;
	const float vWaterTransparens = 0.5f; //more transparance lets you see more of background
	const float vColorMapFactor = 1.0f; //how much colormap

	vec2 tex_coord = tex_coord;
	vec2 corrected_coord = get_corrected_coords(tex_coord);
	vec3 WorldColorColor = texture(colormap_water, corrected_coord).rgb;
	tex_coord *= 100.;
	tex_coord = tex_coord * 0.25 + time * 0.001f;

	const vec3 eyeDirection = vec3(0.0, 1.0, 1.0);
	const vec3 lightDirection = vec3(0.0, 1.0, 1.0);

	vec2 coordA = tex_coord * 3 + vec2(0.10, 0.10);
	vec2 coordB = tex_coord * 1 + vec2(0.00, 0.10);
	vec2 coordC = tex_coord * 2 + vec2(0.00, 0.15);
	vec2 coordD = tex_coord * 5 + vec2(0.00, 0.30);

	// Uses textureNoTile for non repeting textures,
	// probably unnecessarily expensive
	vec4 vBumpA = texture(water_normal, coordA);
	coordB += vec2(0.03, -0.02) * time;
	vec4 vBumpB = texture(water_normal, coordB);
	coordC += vec2(0.03, -0.01) * time;
	vec4 vBumpC = texture(water_normal, coordC);
	coordD += vec2(0.02, -0.01) * time;
	vec4 vBumpD = texture(water_normal, coordD);

	vec3 vBumpTex = normalize(WaveModOne * (vBumpA.xyz + vBumpB.xyz + vBumpC.xyz + vBumpD.xyz) - WaveModTwo);
	vec3 eyeDir = normalize(eyeDirection);
	float NdotL = max(dot(eyeDir, (vBumpTex / 2)), 0);

	NdotL = clamp((NdotL + WRAP) / (1 + WRAP), 0.f, 1.f);
	NdotL = mix(NdotL, 1.0, 0.0);

	vec3 OutColor = NdotL * (WorldColorColor * vColorMapFactor);

	vec3 reflVector = -reflect(lightDirection, vBumpTex);
	float specular = dot(normalize(reflVector), eyeDir);
	specular = clamp(specular, 0.f, 1.f);
	specular = pow(specular, SpecValueOne);
	OutColor += (specular / SpecValueTwo);
	OutColor.b *= 1.5f;
	OutColor *= texture(province_fow, prov_id).rgb;

	return vec4(OutColor, vWaterTransparens);
}

layout(index = 4) subroutine(get_water_class)
vec4 get_water_political() {
	vec4 color = vec4(0.76f, 0.71f, 0.64f, 1.f);
	vec2 corrected_coord = get_corrected_coords(tex_coord);
	vec3 water_color = texture(colormap_water, corrected_coord).rgb;
	color.rgb = mix(color.rgb, water_color, 0.11f);

	vec4 OverlayColor = texture(overlay, tex_coord * vec2(11., 11.*map_size.y/map_size.x));
	vec4 OutColor;
	OutColor.r = OverlayColor.r < .5 ? (2. * OverlayColor.r * color.r) : (1. - 2. * (1. - OverlayColor.r) * (1. - color.r));
	OutColor.g = OverlayColor.r < .5 ? (2. * OverlayColor.g * color.g) : (1. - 2. * (1. - OverlayColor.g) * (1. - color.g));
	OutColor.b = OverlayColor.b < .5 ? (2. * OverlayColor.b * color.b) : (1. - 2. * (1. - OverlayColor.b) * (1. - color.b));
	OutColor.a = OverlayColor.a;
	return OutColor;
}

// The terrain color from the current texture coordinate offset with one pixel in the "corner" direction
vec4 get_terrain(vec2 corner, vec2 offset) {
	float index = texture(terrain_texture_sampler, floor(tex_coord * map_size + vec2(0.5, 0.5)) / map_size + 0.5 * pix * corner).r;
	index = floor(index * 256);
	float is_water = step(64, index);
	vec4 colour = texture(terrainsheet_texture_sampler, vec3(offset, index));
	return mix(colour, vec4(0.), is_water);
}

vec4 get_terrain_mix() {
	// Pixel size on map texture
	vec2 scaling = fract(tex_coord * map_size + vec2(0.5, 0.5));

	vec2 offset = tex_coord / (16. * pix);

	vec4 colourlu = get_terrain(vec2(-1, -1), offset);
	vec4 colourld = get_terrain(vec2(-1, +1), offset);
	vec4 colourru = get_terrain(vec2(+1, -1), offset);
	vec4 colourrd = get_terrain(vec2(+1, +1), offset);

	// Mix together the terrains based on close they are to the current texture coordinate
	vec4 colour_u = mix(colourlu, colourru, scaling.x);
	vec4 colour_d = mix(colourld, colourrd, scaling.x);
	vec4 terrain = mix(colour_u, colour_d, scaling.y);

	// Mixes the terrains from "texturesheet.tga" with the "colormap.dds" background color.
	vec4 terrain_background = texture(colormap_terrain, get_corrected_coords(tex_coord));
	terrain.xyz = (terrain.xyz * 2. + terrain_background.xyz) / 3.;
	return terrain;
}

layout(index = 0) subroutine(get_land_class)
vec4 get_land_terrain() {
	return get_terrain_mix();
}

layout(index = 1) subroutine(get_land_class)
vec4 get_land_political_close() {
	vec4 terrain = get_terrain_mix();
	float is_land = terrain.a;

	// Make the terrain a gray scale color
	const vec3 GREYIFY = vec3( 0.212671, 0.715160, 0.072169 );
	float grey = dot(terrain.rgb, GREYIFY);
	terrain.rgb = vec3(grey);

	vec2 tex_coords = tex_coord;
	vec2 rounded_tex_coords = (floor(tex_coord * map_size) + vec2(0.5, 0.5)) / map_size;

	uint test = texture(diag_border_identifier, rounded_tex_coords).x;
	vec2 rel_coord = tex_coord * map_size - floor(tex_coord * map_size) - vec2(0.5);
	int shift = int(sign(rel_coord.x) + 2 * sign(rel_coord.y) + 3);

	rounded_tex_coords.y += (((test >> shift) & 1) != 0) && (abs(rel_coord.x) + abs(rel_coord.y) > 0.5) ? sign(rel_coord.y) / map_size.y : 0;

	vec2 prov_id = texture(provinces_texture_sampler, rounded_tex_coords).xy;

	// The primary and secondary map mode province colors
	vec4 prov_color = texture(province_color, vec3(prov_id, 0.));
	vec4 stripe_color = texture(province_color, vec3(prov_id, 1.));

	vec2 stripe_coord = tex_coord * vec2(512., 512. * map_size.y / map_size.x);

	// Mix together the primary and secondary colors with the stripes
	float stripeFactor = texture(stripes_texture, stripe_coord).a;
	float prov_highlight = texture(province_highlight, prov_id).r * (abs(cos(time * 3.f)) + 1.f);
	vec3 political = clamp(mix(prov_color, stripe_color, stripeFactor) + vec4(prov_highlight), 0.0, 1.0).rgb;
	political *= texture(province_fow, prov_id).rgb;
	// Mix together the terrain and map mode color
	terrain.rgb = mix(terrain.rgb, political, 0.77f);
	return terrain;
}

layout(index = 2) subroutine(get_land_class)
vec4 get_terrain_political_far() {
	vec4 terrain = get_terrain_mix();
	float is_land = terrain.a;
	vec2 prov_id = texture(provinces_texture_sampler, tex_coord).xy;

	// The primary and secondary map mode province colors
	vec4 prov_color = texture(province_color, vec3(prov_id, 0.));
	vec4 stripe_color = texture(province_color, vec3(prov_id, 1.));

	vec2 stripe_coord = tex_coord * vec2(512., 512. * map_size.y / map_size.x);

	// Mix together the primary and secondary colors with the stripes
	float stripeFactor = texture(stripes_texture, stripe_coord).a;
	float prov_highlight = texture(province_highlight, prov_id).r * (abs(cos(time * 3.f)) + 1.f);
	vec3 political = clamp(mix(prov_color, stripe_color, stripeFactor) + vec4(prov_highlight), 0.0, 1.0).rgb;

	political = mix(political, vec3(terrain.r), 0.11f);

	vec4 OverlayColor = texture(overlay, tex_coord * vec2(11., 11.*map_size.y/map_size.x));
	vec4 OutColor;
	OutColor.r = OverlayColor.r < .5 ? (2. * OverlayColor.r * political.r) : (1. - 2. * (1. - OverlayColor.r) * (1. - political.r));
	OutColor.g = OverlayColor.r < .5 ? (2. * OverlayColor.g * political.g) : (1. - 2. * (1. - OverlayColor.g) * (1. - political.g));
	OutColor.b = OverlayColor.b < .5 ? (2. * OverlayColor.b * political.b) : (1. - 2. * (1. - OverlayColor.b) * (1. - political.b));
	//OutColor.rgb = vec3(1.54f) * OverlayColor.rgb * political.rgb;
	//OutColor.a = OverlayColor.a;
	OutColor.rgb *= OutColor.rgb * OutColor.rgb * vec3(1.f);
	OutColor.rgb = mix(vec3(250.f/255.f, 247.f/255.f, 202.f/255.f), OutColor.rgb, 0.85f);
	OutColor.rgb = mix(vec3(0.63f, 0.41f, 0.32f), OutColor.rgb, 0.75f);
	OutColor.a = is_land;
	return OutColor;
}

// The terrain map
// No province color is used here
void main() {
	vec4 terrain = get_land();
	float is_land = terrain.a;
	vec4 water = vec4(0.21, 0.38, 0.55, 1.0f);
	water = get_water();

	frag_color = pow(mix(water, terrain, is_land), vec4(0.8f));
	frag_color.a = 1;

	frag_color = gamma_correct(frag_color);
}
