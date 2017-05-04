module window;

import std.stdio : File, writeln;
import std.conv;
import std.container.rbtree;
import std.algorithm.comparison;
public import core.stdc.string: memcpy;
import std.exception;

import vulkan;
import pipeline;
import buffer;
import commands;
import image;

import imageformats;

private extern (Windows) VkBool32 debugCallback(VkDebugReportFlagsEXT flags, VkDebugReportObjectTypeEXT objType, uint64_t obj, size_t location, int32_t code, const char* layerPrefix, const char* msg, void* userData) nothrow @nogc{
	import core.stdc.stdio : printf;
	printf("%s\n", msg);
	return VK_FALSE;
}

struct QueueFamilyIndices {
    int graphics = -1;
	int compute = -1;
    int present = -1;

    bool isComplete() {
        return graphics >= 0 && compute >= 0 && present >= 0;
    }
}

struct MVP {
    mat4 model, view, proj;
}

private struct SwapChainSupportDetails {
    VkSurfaceCapabilitiesKHR capabilities;
	VkSurfaceFormatKHR[] formats;
	VkPresentModeKHR[] presentModes;
}

SwapChainSupportDetails querySwapChainSupport(VkPhysicalDevice device, VkSurfaceKHR surface) {
    SwapChainSupportDetails details;

	vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities);

	uint formatCount;
	vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, null);

	if (formatCount != 0) {
		details.formats.length = formatCount;
		vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, details.formats.ptr);
	}

	uint presentModeCount;
	vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, null);

	if(presentModeCount != 0) {
		details.presentModes.length = presentModeCount;
		vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, details.presentModes.ptr);
	}

    return details;
}

VkSurfaceFormatKHR chooseSwapSurfaceFormat(VkSurfaceFormatKHR[] availableFormats) {
    if(availableFormats.length == 1 && availableFormats[0].format == VK_FORMAT_UNDEFINED) {
        return VkSurfaceFormatKHR(VK_FORMAT_B8G8R8A8_UNORM, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR);
    }

    foreach(availableFormat; availableFormats) {
        if(availableFormat.format == VK_FORMAT_B8G8R8A8_UNORM && availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            return availableFormat;
        }
    }

    return availableFormats[0];
}

VkPresentModeKHR chooseSwapPresentMode(VkPresentModeKHR[] availablePresentModes) {
    foreach(availablePresentMode; availablePresentModes) {
        if(availablePresentMode == VK_PRESENT_MODE_MAILBOX_KHR) {
            return availablePresentMode;
        }
    }

    return VK_PRESENT_MODE_FIFO_KHR;
}

VkExtent2D chooseSwapExtent(VkSurfaceCapabilitiesKHR capabilities) {
    if (capabilities.currentExtent.width != uint.max) {
        return capabilities.currentExtent;
    } else {
        VkExtent2D actualExtent = {
			width: max(capabilities.minImageExtent.width, min(capabilities.maxImageExtent.width, 800)),
			height: max(capabilities.minImageExtent.height, min(capabilities.maxImageExtent.height, 600))
		};

        return actualExtent;
    }
}

private const(char*)[] instanceExtensions = [VK_EXT_DEBUG_REPORT_EXTENSION_NAME];
private const(char*)[] instanceLayers = ["VK_LAYER_LUNARG_standard_validation"];
private const(char*)[] deviceExtensions = [VK_KHR_SWAPCHAIN_EXTENSION_NAME];

bool checkValidationLayerSupport() {
	import core.stdc.string : strcmp;
    uint layerCount;
    vkEnumerateInstanceLayerProperties(&layerCount, null);

	VkLayerProperties[] availableLayers = new VkLayerProperties[layerCount];
    vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr);

	bool layerFound = false;

	foreach(layerProperties; availableLayers) {
		if (strcmp("VK_LAYER_LUNARG_standard_validation".ptr, layerProperties.layerName.ptr) == 0) {
			layerFound = true;
			break;
		}
	}

	if (!layerFound) {
		return false;
	}

	return true;
}

__gshared struct Window {
	public static {
		string title;
		int width, height;
		GLFWwindow* window;

		VkInstance instance; // Connection between your application and the Vulkan library
		VkSurfaceKHR surface; // Wrapper for the window
		VkPhysicalDevice physicalDevice; // Physical hardware, the graphic card
		VkPhysicalDeviceProperties physicalDeviceProperties;
		VkQueueFamilyProperties[] queueFamilyProperties;
		QueueFamilyIndices queueFamilies; //
		VkDevice device; // Application’s view of the physical device

		VkQueue graphicsQueue, computeQueue; // Graphic and Compute queue, Interface to the execution engines of a device
		VkQueue presentQueue; // Presentation queue, show image to window, Interface to the execution engines of a device
		VkSwapchainKHR swapChain; // An abstraction for an array of presentable images that are associated with a surface
		VkExtent2D swapChainExtent; // Size of the swapChain's images
		VkFormat swapChainImageFormat; // Format of the swapChain's images
		Image[] swapChainImage; // Image views of the swapChain's images

		VkFramebuffer[] swapChainFramebuffers;

		// Depth buffer
		Image depthImage;

		Pipeline[] pipelines;
	}
	private static VkDebugReportCallbackEXT debugCallbacks;

	this(string title, int width, int height) {
		glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
		glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);

		window = glfwCreateWindow(width, height, title.ptr, null, null);

		glfwSetWindowSizeCallback(window, &onResize);

		// load global level functions with glfw
		loadGlobalLevelFunctions( cast( typeof( vkGetInstanceProcAddr ))glfwGetInstanceProcAddress( null, "vkGetInstanceProcAddr" ));

		assert(checkValidationLayerSupport(), "No validation layer is supported!");

		this.title = title;
		this.width = width;
		this.height = height;

		setupApplication();
		setupDebugLayer();

		/* Creating surface */
		glfwCreateWindowSurface(instance, window, null, &surface).enforceVK!"Unable to create window surface";

		queueFamilyProperties = choosePhysicalDevice(physicalDevice, queueFamilies);
	
		setupLogicalDevice();
		setupSwapchain();
	}

	private void setupApplication() {
		VkApplicationInfo appInfo = {
			sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
			pApplicationName: title.ptr,
			applicationVersion: VK_MAKE_VERSION(1, 0, 3),
			pEngineName: "Isolated",
			engineVersion: VK_MAKE_VERSION(1, 0, 3),
			apiVersion: VK_MAKE_VERSION(1, 0, 3)
		};

		uint glfwExtensionCount = 0;
		const(char*)* glfwExtensions;
		glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);
		const(char*)[] extensions;
		foreach(i; 0 .. glfwExtensionCount) {
			extensions ~= glfwExtensions[i];
		} foreach(i; 0 .. instanceExtensions.length) {
			extensions ~= instanceExtensions[i];
		}

		VkInstanceCreateInfo createInfo = {
			pApplicationInfo: &appInfo,
			enabledExtensionCount: cast(uint)extensions.length,
			ppEnabledExtensionNames: extensions.ptr,
			enabledLayerCount: cast(uint)instanceLayers.length,
			ppEnabledLayerNames: instanceLayers.ptr
		};

		vkCreateInstance(&createInfo, null, &instance).enforceVK!"Could not create vulkan instance";

		loadInstanceLevelFunctions(instance);
	}

	private void cleanupApplication() {
		vkDestroyInstance(instance, null);
	}

	private void setupDebugLayer() {
		/* Setting up debug info */
		VkDebugReportCallbackCreateInfoEXT debugInfo = {
			sType: VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
			flags: VK_DEBUG_REPORT_ERROR_BIT_EXT | VK_DEBUG_REPORT_WARNING_BIT_EXT,
			pfnCallback: &debugCallback
		};

		vkCreateDebugReportCallbackEXT(instance, &debugInfo, null, &debugCallbacks).enforceVK!"Failed to set up debug callback";
	}

	private void cleanupDebugLayer() {
		vkDestroyDebugReportCallbackEXT(instance, debugCallbacks, null);
	}

	private VkQueueFamilyProperties[] choosePhysicalDevice(out VkPhysicalDevice physicalDevice, out QueueFamilyIndices familyIndices) {
		uint deviceCount = 0;
		vkEnumeratePhysicalDevices(instance, &deviceCount, null);
		VkPhysicalDevice[] devices = new VkPhysicalDevice[deviceCount];
		vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr);

		VkQueueFamilyProperties[] current;
		uint currentScore;
		foreach(d; devices) {
			int score;
			VkPhysicalDeviceProperties deviceProperties;
			VkPhysicalDeviceFeatures deviceFeatures;
			vkGetPhysicalDeviceProperties(d, &deviceProperties);
			vkGetPhysicalDeviceFeatures(d, &deviceFeatures);

			if(deviceProperties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU)
				score += 100;
			score += deviceProperties.limits.maxImageDimension2D;

			uint queueFamilyCount = 0;
			vkGetPhysicalDeviceQueueFamilyProperties(d, &queueFamilyCount, null);

			VkQueueFamilyProperties[] queueFamilies = new VkQueueFamilyProperties[queueFamilyCount];
			vkGetPhysicalDeviceQueueFamilyProperties(d, &queueFamilyCount, queueFamilies.ptr);

			QueueFamilyIndices family;
			foreach(i,queue; queueFamilies) {
				if(queue.queueCount > 0 && queue.queueFlags & VK_QUEUE_GRAPHICS_BIT) {
					family.graphics = cast(int)i;
				}
				if(queue.queueCount > 0 && queue.queueFlags & VK_QUEUE_COMPUTE_BIT) {
					family.compute = cast(int)i;
				}

				VkBool32 presentSupport = false;
				vkGetPhysicalDeviceSurfaceSupportKHR(d, cast(uint)i, surface, &presentSupport);

				if (queue.queueCount > 0 && presentSupport) {
					family.present = cast(int)i;
				}
			}
			if(!family.isComplete()) continue;

			// Check if device extensions are supported
			uint extensionCount;
			vkEnumerateDeviceExtensionProperties(d, null, &extensionCount, null);

			VkExtensionProperties[] availableExtensions = new VkExtensionProperties[extensionCount];
			vkEnumerateDeviceExtensionProperties(d, null, &extensionCount, availableExtensions.ptr);

			bool extensionAvailable = true;
			foreach(requiredExtension; deviceExtensions) {
				import core.stdc.string : strlen, strncmp;
				size_t len = strlen(requiredExtension);
				bool found = false;
				foreach(extension; availableExtensions) {
					if(strncmp(requiredExtension, extension.extensionName.ptr, len) == 0) {
						found = true;
						break;
					}
				}
				if(!found) {
					extensionAvailable = false;
					break;
				}
			}

			if(!extensionAvailable) continue;

			// Check for swap chain support
			SwapChainSupportDetails swapChainSupport;
			vkGetPhysicalDeviceSurfaceCapabilitiesKHR(d, surface, &swapChainSupport.capabilities);

			uint formatCount;
			vkGetPhysicalDeviceSurfaceFormatsKHR(d, surface, &formatCount, null);

			if (formatCount != 0) {
				swapChainSupport.formats.length = formatCount;
				vkGetPhysicalDeviceSurfaceFormatsKHR(d, surface, &formatCount, swapChainSupport.formats.ptr);
			}

			uint presentModeCount;
			vkGetPhysicalDeviceSurfacePresentModesKHR(d, surface, &presentModeCount, null);

			if(presentModeCount != 0) {
				swapChainSupport.presentModes.length = presentModeCount;
				vkGetPhysicalDeviceSurfacePresentModesKHR(d, surface, &presentModeCount, swapChainSupport.presentModes.ptr);
			}

			bool swapChainAdequate = swapChainSupport.formats.length != 0 && swapChainSupport.presentModes.length != 0;
			if(!swapChainAdequate) continue;

			if(score >= currentScore) {
				currentScore = score;
				physicalDevice = d;
				current = queueFamilies;
				familyIndices = family;
                physicalDeviceProperties = deviceProperties;
			}
		}

		return current;
	}

	private void setupLogicalDevice() {
		/* Create logical device */
		float queuePriority = 1.0f;
		auto rbTree = redBlackTree(queueFamilies.graphics, queueFamilies.compute, queueFamilies.present);
		VkDeviceQueueCreateInfo[] queueCreateInfos = new VkDeviceQueueCreateInfo[rbTree.length()];

		foreach(i; 0 .. rbTree.length()) {
			VkDeviceQueueCreateInfo queueCreateInfo = {
				queueFamilyIndex: rbTree.front(),
				queueCount: 1,
				pQueuePriorities: &queuePriority
			};
			queueCreateInfos[i] = queueCreateInfo;
		}

		VkPhysicalDeviceFeatures deviceFeatures = {};

		VkDeviceCreateInfo deviceCreateInfo = {
			pQueueCreateInfos: queueCreateInfos.ptr,
			queueCreateInfoCount: cast(uint)queueCreateInfos.length,
			pEnabledFeatures: &deviceFeatures,
			enabledExtensionCount: cast(uint)deviceExtensions.length,
			ppEnabledExtensionNames: deviceExtensions.ptr,
			enabledLayerCount: cast(uint)instanceLayers.length,
			ppEnabledLayerNames: instanceLayers.ptr
		};

		vkCreateDevice(physicalDevice, &deviceCreateInfo, null, &device).enforceVK;

		loadDeviceLevelFunctions(device);

		vkGetDeviceQueue(device, queueFamilies.graphics, 0, &graphicsQueue);
		vkGetDeviceQueue(device, queueFamilies.compute, 0, &computeQueue);
		vkGetDeviceQueue(device, queueFamilies.present, 0, &presentQueue);
	}

	private void cleanupLogicalDevice() {

	}

	private static void setupSwapchain() {
		/* Creating swap chain */
		SwapChainSupportDetails swapChainSupport = querySwapChainSupport(physicalDevice, surface);

		VkSurfaceFormatKHR surfaceFormat = chooseSwapSurfaceFormat(swapChainSupport.formats);
		swapChainImageFormat = surfaceFormat.format;
		VkPresentModeKHR presentMode = chooseSwapPresentMode(swapChainSupport.presentModes);
		swapChainExtent = chooseSwapExtent(swapChainSupport.capabilities);

		uint imageCount = swapChainSupport.capabilities.minImageCount + 1;
		if (swapChainSupport.capabilities.maxImageCount > 0 && imageCount > swapChainSupport.capabilities.maxImageCount) {
			imageCount = swapChainSupport.capabilities.maxImageCount;
		}

		VkSwapchainCreateInfoKHR swapChainCreateInfo = {
			surface: surface,
			minImageCount: imageCount,
			imageFormat: surfaceFormat.format,
			imageColorSpace: surfaceFormat.colorSpace,
			imageExtent: swapChainExtent,
			imageArrayLayers: 1,
			imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
			preTransform: swapChainSupport.capabilities.currentTransform,
			compositeAlpha: VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
			presentMode: presentMode,
			clipped: VK_TRUE,
			oldSwapchain: swapChain
		};

		uint[] queueFamilyIndices = [cast(uint) queueFamilies.graphics, cast(uint) queueFamilies.compute, cast(uint) queueFamilies.present];

		if (queueFamilies.graphics != queueFamilies.present) {
			swapChainCreateInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
			swapChainCreateInfo.queueFamilyIndexCount = queueFamilyIndices.length;
			swapChainCreateInfo.pQueueFamilyIndices = queueFamilyIndices.ptr;
		} else {
			swapChainCreateInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
			swapChainCreateInfo.queueFamilyIndexCount = 0; // Optional
			swapChainCreateInfo.pQueueFamilyIndices = null; // Optional
		}

		VkSwapchainKHR oldSwapChain = swapChain;
		vkCreateSwapchainKHR(device, &swapChainCreateInfo, null, &swapChain).enforceVK;

		if(oldSwapChain != 0)
			vkDestroySwapchainKHR(device, oldSwapChain, null);

		// Get images of swap chain
		uint imagesCount;
		vkGetSwapchainImagesKHR(device, swapChain, &imagesCount, null);
		VkImage[] temp = new VkImage[imagesCount];
		vkGetSwapchainImagesKHR(device, swapChain, &imagesCount, temp.ptr);

		// Creating image views
        swapChainImage = Image.generateImageView(swapChainImageFormat, VK_IMAGE_ASPECT_COLOR_BIT, temp);
	}

	private static void cleanupSwapchain() {

	}

	private extern(C) static void onResize(GLFWwindow* window, int width, int height) nothrow {
		if (width == 0 || height == 0) return;

		this.width = width;
		this.height = height;

		try {
			vkDeviceWaitIdle(device);

			setupSwapchain();

			foreach(pipeline; pipelines)
				pipeline.recreate();
		} catch(Exception e){}
	}
}