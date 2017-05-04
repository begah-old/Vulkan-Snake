#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(location = 0) in vec2 UV;

layout(set = 0, binding = 0) uniform sampler2DArray texSampler;

layout(push_constant) uniform PushConstant {
	int textureID;
} pConstant;

layout(location = 0) out vec4 outColor;

void main() {
	outColor = texture(texSampler, vec3(UV, pConstant.textureID));
}