module buffer;

import vulkan;
import window;
import commands;

import std.stdio;
import core.stdc.string : memcpy, memset;

class Buffer {
    private {
        bool generated = false;

        VkDeviceSize _size;
        VkBufferUsageFlags _usage;
        VkMemoryPropertyFlags _properties;

        VkBuffer _buffer;
        VkDeviceMemory _bufferMemory;
    }

    // Constructor to initialize buffer and allocated memory;
    this(VkBufferUsageFlags usage, VkMemoryPropertyFlags properties, VkDeviceSize size, bool generate = true) {
        _usage = usage;
        _properties = properties;
        _size = size;

        if(generate) _generate();
    }

    // Set buffer data, if size is 0 it is assumed to copy all data
    public Buffer set(void* src, VkDeviceSize size = 0, size_t offset = 0) {
        if(size == 0) size = _size;

        ubyte* data;
        vkMapMemory(Window.device, _bufferMemory, 0, size, 0, cast(void**)&data);
        memcpy(data + offset, src, cast(size_t)size);
        vkUnmapMemory(Window.device, _bufferMemory);

        return this;
    }

    public void transferDataTo(Buffer dest) {
        Command command = GraphicsPool.getSingleTimeCommand().record();

        VkBufferCopy copyRegion = {
            srcOffset: 0,
            dstOffset: 0,
            size: _size
        };
        vkCmdCopyBuffer(command.buffer, _buffer, dest._buffer, 1, &copyRegion);

        command.stop();
    }

    alias buffer this;
    public ref VkBuffer buffer() @property { return _buffer; }
    public ref VkDeviceMemory memory() @property { return _bufferMemory; }

    private void _generate() {
        VkBufferCreateInfo bufferInfo = {
            size: _size,
            usage: _usage,
            sharingMode: VK_SHARING_MODE_EXCLUSIVE
        };

        vkCreateBuffer(Window.device, &bufferInfo, null, &_buffer).enforceVK;

        VkMemoryRequirements memRequirements;
        vkGetBufferMemoryRequirements(Window.device, _buffer, &memRequirements);

        VkMemoryAllocateInfo allocInfo = {
            allocationSize: memRequirements.size,
            memoryTypeIndex: searchMemoryType(Window.physicalDevice, memRequirements.memoryTypeBits, _properties)
        };

        vkAllocateMemory(Window.device, &allocInfo, null, &_bufferMemory).enforceVK!"failed to allocate buffer memory!";

        vkBindBufferMemory(Window.device, _buffer, _bufferMemory, 0);

        generated = true;
    }

    private void _free() {
        if(!generated) return;
        vkFreeMemory(Window.device, _bufferMemory, null);
        vkDestroyBuffer(Window.device, _buffer, null);
    }

    public void destroy() {
        _free();
    }

    ~this() {
        _free();
    }
}

// Buffer that by defaults keep memory mapped and keeps track of changed memory not flushed to gpu buffer.
class StagingBuffer : Buffer {
    // Buffer to transfer data to
    public Buffer main;
    private {
        bool _dirty = false, _mapped = false;
        ubyte* _data;

        alias Vector!(ulong, 2) vecSizeT;
        vecSizeT _dirtyRange;
    }

	// Construct staging buffer as well as main buffer and set data
	this(void* data, VkDeviceSize size) {
		this(VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, size);
		main = new Buffer(VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, size);
		set(data, size);
		transferDataTo(main);
	}

    // Constructor to initialize buffer and allocated memory;
    this(VkBufferUsageFlags usage, VkMemoryPropertyFlags properties, VkDeviceSize size) {
        super(usage, properties, size, false);

        _generateStaging();
    }

    private void _generateStaging() {
        super._generate();

        vkMapMemory(Window.device, _bufferMemory, 0, _size, 0, cast(void**)&_data);
        _mapped = true;
    }

    // Set buffer data, if size is 0 it is assumed to copy all data
    public override StagingBuffer set(void* src, VkDeviceSize size = 0, size_t offset = 0) {
        if(size == 0) size = _size;

        memcpy(_data + offset, src, cast(size_t)size);

        if(!_dirty) {
            _dirtyRange = vecSizeT(offset, size);
            _dirty = true;
        } else {
            if(_dirtyRange.x > offset) {
                _dirtyRange.y += _dirtyRange.x - offset;
                _dirtyRange.x = offset;

                if(_dirtyRange.y < size)
                    _dirtyRange.y = size;
            }
            else if(_dirtyRange.y < size)
                _dirtyRange.y = size;
            else if(cast(ptrdiff_t)size - cast(ptrdiff_t)(_dirtyRange.x + _dirtyRange.y - offset) > 0)
                _dirtyRange.y += size - (_dirtyRange.x + _dirtyRange.y - offset);
        }

        return this;
    }

    public override void transferDataTo(Buffer dest) {
        if(_dirty == false) return;
        Command command = GraphicsPool.getSingleTimeCommand().record();

        VkBufferCopy copyRegion = {
            srcOffset: _dirtyRange.x,
            dstOffset: _dirtyRange.x,
            size: _dirtyRange.y
        };
        vkCmdCopyBuffer(command.buffer, _buffer, dest._buffer, 1, &copyRegion);

        command.stop();

        _dirty = false;
		_dirtyRange = vecSizeT(0);
    }

    public void clear() {
        memset(_data, 0, cast(size_t)_size);
        _dirtyRange = vecSizeT(0, _size);
        _dirty = true;
    }

    public void unMap() {
        if(_mapped == false) return;

        vkUnmapMemory(Window.device, _bufferMemory);
        _mapped = false;
    }

    ~this() {
        unMap();
    }
}
