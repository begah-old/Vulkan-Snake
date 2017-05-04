module commands;

import std.stdio;

import vulkan;
import window;

CommandPool ComputePool, GraphicsPool;

class CommandPool {
    private {
        bool generated = false;

        VkCommandPool _pool;
        VkQueue _queueFamily;
		size_t _queueFamilyIndex;

        Command[10] _singleTimeCommands;
        size_t singleTimeIndex;
        Command[] _commands;
    }

    this(VkQueue queueFamily, size_t queueFamilyIndex) {
        _queueFamily = queueFamily;
		_queueFamilyIndex = queueFamilyIndex;

        _generate();
    }

    private void _generate() {
        VkCommandPoolCreateInfo poolInfo = {
            queueFamilyIndex: _queueFamilyIndex,
            flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
        };

        vkCreateCommandPool(Window.device, &poolInfo, null, &_pool).enforceVK;

        VkCommandBuffer[10] commandBuffers;

        VkCommandBufferAllocateInfo allocInfo = {
            level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            commandPool: _pool,
            commandBufferCount: _singleTimeCommands.length,
        };

        vkAllocateCommandBuffers(Window.device, &allocInfo, commandBuffers.ptr);

        foreach(i; 0 .. _singleTimeCommands.length) {
            _singleTimeCommands[i] = new Command(this, VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT);
            _singleTimeCommands[i]._buffer = commandBuffers[i];
        }
    }

    Command getSingleTimeCommand() {
        if(_singleTimeCommands[singleTimeIndex]._recording == false) {
            size_t index = singleTimeIndex;
            singleTimeIndex++;
            if(singleTimeIndex == _singleTimeCommands.length)
                singleTimeIndex = 0;

            return _singleTimeCommands[index];
        } else {
            // Search for next available command
            size_t start = singleTimeIndex;
            do {
                singleTimeIndex++;
                if(singleTimeIndex == _singleTimeCommands.length)
                    singleTimeIndex = 0;
                if(_singleTimeCommands[singleTimeIndex]._recording == false) {
                    size_t index = singleTimeIndex;
                    singleTimeIndex++;
                    if(singleTimeIndex == _singleTimeCommands.length)
                        singleTimeIndex = 0;
                    return _singleTimeCommands[index];
                }
                if(singleTimeIndex == start) {
                    writeln("Could not find single time command!");
                    return null;
                }
            } while(1);
        }
    }

	Command[] generateCommands(size_t count) {
		Command[] commands = new Command[count];
		VkCommandBuffer[] buffers = new VkCommandBuffer[count];

		VkCommandBufferAllocateInfo allocInfo = {
			commandPool: _pool,
			level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,
			commandBufferCount: cast(uint)count
		};

		vkAllocateCommandBuffers(Window.device, &allocInfo, buffers.ptr).enforceVK;
		foreach(i, buffer; buffers) {
			commands[i] = new Command(this, VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT);
			commands[i]._buffer = buffer;
		}

		delete buffers;
		return commands;
	}

    alias pool this;
    public ref VkCommandPool pool() { return _pool; }
}

class Command {
    private {
        CommandPool _pool;
        bool _recording = false;

        VkCommandBufferUsageFlagBits _flag;
        VkCommandBuffer _buffer;
    }

    this(CommandPool pool, VkCommandBufferUsageFlagBits flag) {
        _pool = pool;
        _flag = flag;
    }

	alias buffer this;
    public ref VkCommandBuffer buffer() @property { return _buffer; }

    public Command record() {
        VkCommandBufferBeginInfo beginInfo = {flags:_flag};

        vkBeginCommandBuffer(_buffer, &beginInfo);

        _recording = true;

        return this;
    }

    public Command stop() {
        vkEndCommandBuffer(_buffer);

        VkSubmitInfo submitInfo = {
            commandBufferCount: 1,
            pCommandBuffers: &_buffer
        };

        vkQueueSubmit(_pool._queueFamily, 1, &submitInfo, VK_NULL_ND_HANDLE);
        vkQueueWaitIdle(_pool._queueFamily);

        _recording = false;

        return this;
    }

    private void _destroy() {
        vkFreeCommandBuffers(Window.device, _pool._pool, 1, &_buffer);
    }

    ~this() {
        _destroy();
    }
}
