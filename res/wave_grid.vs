#version 330

// Input vertex attributes
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;

// Input uniform values
uniform mat4 mvp;
uniform sampler2D texture0;
uniform mat4 _matCamera;
uniform float _time;

// Output vertex attributes (to fragment shader)
out vec2 fragTexCoord;
out vec4 fragColor;
out vec4 _oWorldPos;

// NOTE: Add here your custom variables


// Hash function to create pseudo-random gradients
float hash(vec2 p) {
	return fract(sin(dot(p ,vec2(127.1, 311.7))) * 43758.5453);
}

// Interpolation function
float fade(float t) {
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// Linear interpolation between two values
float lerp(float a, float b, float t) {
	return a + t * (b - a);
}

// Perlin noise function
float perlin(vec2 uv) {
	// Determine grid cell coordinates
	vec2 i = floor(uv);
	vec2 f = fract(uv);

	// Compute gradients
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	// Compute fade curves for the f values
	vec2 u = vec2(fade(f.x), fade(f.y));

	// Bilinear interpolation of dot products
	float res = lerp(
		lerp(a, b, u.x),
		lerp(c, d, u.x),
		u.y
	);

	return res;
}

void main()
{
	// Send vertex attributes to fragment shader
	fragTexCoord = vertexTexCoord;
	vec4 wpos = (mvp * inverse(_matCamera))*vec4(vertexPosition, 1.0);
	float noise = perlin(100*vec2(wpos.x, wpos.y)+vec2(_time, _time)*0.5);
	_oWorldPos = wpos;

	// uniforms
	fragColor = vertexColor;

	// Calculate final vertex position
	gl_Position = mvp*vec4(vertexPosition+0.05*vec3(noise,noise, 0), 1.0);

}
