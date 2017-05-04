#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(set = 1, binding = 1) uniform GlobalData {
    mat4 projection;
	mat4 view;
} gd;

layout(set = 2, binding = 2) uniform ModelData {
	mat4 model;
} md;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inUV;

layout(location = 0) out vec2 UV;

out gl_PerVertex {
    vec4 gl_Position;
};

void main() {
	vec4 temp = md.model * vec4(inPosition, 1.0);
    gl_Position = gd.projection * gd.view * vec4(-temp.xy, temp.zw);
	gl_Position.z = (gl_Position.z + gl_Position.w) / 2.0;
	UV = inUV;
}