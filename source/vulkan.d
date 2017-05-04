module vulkan;

import std.conv : to;
import util;

public import erupted;
public import derelict.glfw3;
public import gl3n.linalg;
public import gl3n.math : PI;

mixin DerelictGLFW3_VulkanBind;

static this() {
    // load GLFW3 functions
    DerelictGLFW3.load;

    // load GLFW3 vulkan support functions into current scope
    DerelictGLFW3_loadVulkan();

    glfwInit();
}

void enforceVK(string message = "")(VkResult res) {
    import std.exception : enforce;
    enforce(res == VkResult.VK_SUCCESS, message != "\n" ? message ~ "\n" ~ res.to!string : res.to!string);
}

uint searchMemoryType(VkPhysicalDevice physicalDevice, uint typeFilter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties);

    foreach(uint i; 0 .. memProperties.memoryTypeCount) {
        if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return cast(uint)i;
        }
    }
    return 0;
}

public import window;
public import buffer;
public import commands;
public import image;
public import image_array;
public import pipeline;

struct Vertex {
    vec3 position;
	vec3 normal;
	vec2 uv;

    static VkVertexInputAttributeDescription[] describeVertex(out VkVertexInputBindingDescription[] inputBinding) {
        VkVertexInputBindingDescription[] temp = [
			{binding: 0,
            stride: vec3.sizeof,
            inputRate: VK_VERTEX_INPUT_RATE_VERTEX},
			{binding: 1,
			stride: vec3.sizeof,
			inputRate: VK_VERTEX_INPUT_RATE_VERTEX},
			{binding: 2,
			stride: vec2.sizeof,
			inputRate: VK_VERTEX_INPUT_RATE_VERTEX}];
        inputBinding = temp;

        VkVertexInputAttributeDescription[] attributeDescriptions = [
            {binding: 0,
            location: 0,
            format: VK_FORMAT_R32G32B32_SFLOAT,
            offset: 0},
			{binding: 1,
			location: 1,
			format: VK_FORMAT_R32G32B32_SFLOAT,
			offset: 0},
			{binding: 2,
			location: 2,
			format: VK_FORMAT_R32G32_SFLOAT,
			offset: 0}
        ];
        return attributeDescriptions;
    }
}

static ~this() {
    glfwTerminate();
}
