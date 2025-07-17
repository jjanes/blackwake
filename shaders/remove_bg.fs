// remove_bg.fs
#version 330

uniform sampler2D texture0;
uniform vec3 key_color;     // background color to remove
uniform float threshold;    // color distance tolerance

in vec2 fragTexCoord;
out vec4 fragColor;

void main() {
    vec4 color = texture(texture0, fragTexCoord);
    float dist = distance(color.rgb, key_color);

    if (dist < threshold)
        discard;  // Remove pixel (makes it transparent)
    else
        fragColor = color;
}
