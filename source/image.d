module image;

import core.stdc.string : memcpy;

import imageformats;

import vulkan;
import window;
import commands;
import util;

struct ImageProperties {
	bool generated = false;

	string filename;
	size_t width, height;
	size_t layerCount;

	VkFormat format;
	VkImageTiling tiling;
	VkImageUsageFlags usage;
	VkMemoryPropertyFlags properties;

	this(string filename) {
		this.filename = filename;
		layerCount = 1;

		format = VK_FORMAT_R8G8B8A8_UNORM;
		tiling = VK_IMAGE_TILING_LINEAR;
		usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
		properties = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
	}

	this(size_t layerCount, size_t width, size_t height) {
		this(width, height, layerCount, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
	}

	this(size_t width, size_t height, size_t layerCount, VkFormat format, VkImageTiling tiling, VkImageUsageFlags usage, VkMemoryPropertyFlags properties) {
		this.layerCount = layerCount;
		this.width = width;
		this.height = height;

		this.format = format;
		this.tiling = tiling;
		this.usage = usage;
		this.properties = properties;
	}
}

class Image {
    private {
		ImageProperties _properties;

        VkImage _image;
        VkDeviceMemory _memory;
        VkImageView _view;
    }

    this(ImageProperties properties, bool generate = true) {
        _properties = properties;

		if(generate) {
			if(properties.filename !is null)
				_load();
			else
				_allocate();
		}
    }

    this(VkImage image, VkFormat format) {
        _properties.generated = true;
		_properties.layerCount = 1;
		_properties.format = format;

        _image = image;
    }

    public void transferDataTo(VkImage destImage, size_t destLayers = 0) {
        Command command = GraphicsPool.getSingleTimeCommand().record();

        VkImageSubresourceLayers src = {
            aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
            baseArrayLayer: 0,
            mipLevel: 0,
            layerCount: cast(uint)_properties.layerCount
        };
		VkImageSubresourceLayers dest = {
			aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
			baseArrayLayer: cast(uint)destLayers,
			mipLevel: 0,
			layerCount: cast(uint)_properties.layerCount
        };

        VkImageCopy region = {
            srcSubresource: src,
            dstSubresource: dest,
            srcOffset: {0, 0, 0},
            dstOffset: {0, 0, 0},
            extent: {
                width: cast(uint)_properties.width,
                height: cast(uint)_properties.height,
                depth: 1
            }
        };

        vkCmdCopyImage(command.buffer, _image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, destImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

        command.stop();
    }

    public void changeLayout(VkImageLayout oldLayout, VkImageLayout newLayout) {
        bool formatHasStencilComponent() {
            return _properties.format == VK_FORMAT_D32_SFLOAT_S8_UINT || _properties.format == VK_FORMAT_D24_UNORM_S8_UINT;
        }

        Command command = GraphicsPool.getSingleTimeCommand().record();

        VkImageMemoryBarrier barrier = {
            oldLayout: oldLayout,
            newLayout: newLayout,
            srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,
            image: _image,
            subresourceRange: {
                aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
                baseMipLevel: 0,
                levelCount: 1,
                baseArrayLayer: 0,
                layerCount: cast(uint)_properties.layerCount
            },
            srcAccessMask: 0,
            dstAccessMask: 0
        };

        if (newLayout == VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
            barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;

            if (formatHasStencilComponent()) {
                barrier.subresourceRange.aspectMask |= VK_IMAGE_ASPECT_STENCIL_BIT;
            }
        } else {
            barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        }

        if (oldLayout == VK_IMAGE_LAYOUT_PREINITIALIZED && newLayout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL) {
            barrier.srcAccessMask = VK_ACCESS_HOST_WRITE_BIT;
            barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        } else if (oldLayout == VK_IMAGE_LAYOUT_PREINITIALIZED && newLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
            barrier.srcAccessMask = VK_ACCESS_HOST_WRITE_BIT;
            barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        } else if (oldLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL && newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
            barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
            barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        } else if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && newLayout == VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
            barrier.srcAccessMask = 0;
            barrier.dstAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        } else {
            throw new Exception("WTF IS HAPPENING!");
        }

        vkCmdPipelineBarrier(command.buffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, 0, 0, null, 0, null, 1, &barrier);

        command.stop();
    }

    public Image generateImageView(VkImageAspectFlags aspectFlags, VkImageViewType viewType = VK_IMAGE_VIEW_TYPE_2D) {
         VkImageViewCreateInfo viewInfo = {
            image: _image,
            viewType: viewType,
            format: _properties.format,
            subresourceRange: {
                aspectMask: aspectFlags,
                baseMipLevel: 0,
                levelCount: 1,
                baseArrayLayer: 0,
                layerCount: cast(uint)_properties.layerCount
            }
        };
        vkCreateImageView(Window.device, &viewInfo, null, &_view).enforceVK;

        return this;
    }

    public static Image[] generateImageView(VkFormat format, VkImageAspectFlags aspectFlags, VkImage[] images...) {
        Image[] views = new Image[images.length];

        foreach(i, image; images) {
            views[i] = new Image(image, format);
            views[i].generateImageView(aspectFlags);
        }

        return views;
    }

    public size_t width() @property { return _properties.width; }
    public size_t height() @property { return _properties.height; }
    public VkImage image() @property { return _image; }
    public VkDeviceMemory memory() @property { return _memory; }
    public VkImageView view() @property { return _view; }

	alias image this;

	private void _allocate() {
		// Allocate VkImage
		VkImageCreateInfo imageInfo = {
			imageType: VK_IMAGE_TYPE_2D,
			extent: {
				width: cast(uint)_properties.width,
				height: cast(uint)_properties.height,
				depth: 1
			},
            mipLevels: 1,
            arrayLayers: cast(uint)_properties.layerCount,
            format: _properties.format,
            tiling: _properties.tiling,
            initialLayout: VK_IMAGE_LAYOUT_PREINITIALIZED,
            usage: _properties.usage,
            sharingMode: VK_SHARING_MODE_EXCLUSIVE,
            samples: VK_SAMPLE_COUNT_1_BIT,
            flags: 0
        };

        vkCreateImage(Window.device, &imageInfo, null, &_image).enforceVK;

		// Allocate VkDeviceMemory
        VkMemoryRequirements memRequirements;
        vkGetImageMemoryRequirements(Window.device, _image, &memRequirements);

        VkMemoryAllocateInfo allocInfo = {
			allocationSize: memRequirements.size,
			memoryTypeIndex: searchMemoryType(Window.physicalDevice, memRequirements.memoryTypeBits, _properties.properties),
        };

        vkAllocateMemory(Window.device, &allocInfo, null, &_memory).enforceVK;

        vkBindImageMemory(Window.device, _image, _memory, 0);
        _properties.generated = true;
	}

    private void _load() {
		File imageFile = internal(_properties.filename);
		ubyte[] rawData = imageFile.rawRead(new ubyte[cast(size_t)imageFile.size()]); imageFile.close();

		IFImage image = read_image_from_mem(rawData);
        _properties.width = cast(size_t) (image.pixels.length / image.h / 4.0f);
		_properties.height = cast(size_t)image.h;
        VkDeviceSize imageSize = _properties.width * _properties.height * 4;

		_allocate();

        VkImageSubresource subresource = {
			aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,
			mipLevel: 0,
			arrayLayer: 0
        };

        VkSubresourceLayout layout;
        vkGetImageSubresourceLayout(Window.device, _image, &subresource, &layout);

        ubyte* data;
        vkMapMemory(Window.device, _memory, 0, imageSize, 0, cast(void**)&data);

        if (layout.rowPitch == width * 4) {
            foreach(i; 0 .. _properties.height)
                memcpy(data + i * layout.rowPitch + layout.offset, image.pixels.ptr + (height - 1 - i) * _properties.width * 4, cast(size_t) (_properties.width * 4));
        }
        vkUnmapMemory(Window.device, _memory);
    }

    private void _destroy() {

    }

    ~this() {

    }
}