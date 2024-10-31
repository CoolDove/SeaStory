#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;
in vec4 _oWorldPos;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

uniform float _time;

// Output fragment color
out vec4 finalColor;

// NOTE: Add here your custom variables

// NOTE: Render size values must be passed from code
const float renderWidth = 800;
const float renderHeight = 450;

float offset[3] = float[](0.0, 1.3846153846, 3.2307692308);
float weight[3] = float[](0.2270270270, 0.3162162162, 0.0702702703);

void main()
{
	vec4 color = texture(texture0, fragTexCoord);
	finalColor = fragColor * color;
}

