module shader;

import vulkan;
import util;
import image_array;

import std.algorithm;

class Shader {
	private {
		ubyte[] _vertexData, _fragmentData;
		VkShaderModule _vertex, _fragment;
	}

	public {
		UniformImage[] images;
		UniformBuffer[] uniforms;

		// Uniform buffer
		VkDescriptorPool descriptorPool;
		VkDescriptorSet descriptorSet;
	}

	this(string vertexSourceFile, string fragmentSourceFile) {
		File vert = internal("shaders\\" ~ vertexSourceFile);
		File frag = internal("shaders\\" ~ fragmentSourceFile);
        _vertexData = vert.rawRead(new ubyte[cast(size_t)vert.size()]);
        _fragmentData = frag.rawRead(new ubyte[cast(size_t)frag.size()]);
        
		vert.close(); frag.close();
	}

	Shader setUniforms(UniformBuffer[] uniforms) {
		if(this.uniforms !is null)
			delete this.uniforms;

		this.uniforms = new UniformBuffer[uniforms.length];
		uniforms.copy(this.uniforms);

		return this;
	}

	Shader setImages(UniformImage[] images) {
		if(this.images !is null)
			delete this.images;

		this.images = new UniformImage[images.length];
		images.copy(this.images);

		return this;
	}

	void generate() {
		_makeShaderModule(_vertex, _vertexData);
		_makeShaderModule(_fragment, _fragmentData);
	}

	// Generate descriptor pool to accomodate for all uniform objects
	void generatePool() {
		VkDescriptorPoolSize[] poolSize =  getPoolSize();

        VkDescriptorPoolCreateInfo poolInfo = {
			poolSizeCount: cast(uint)poolSize.length,
			pPoolSizes: poolSize.ptr,
			maxSets: cast(uint)poolSize.length
        };
        vkCreateDescriptorPool(Window.device, &poolInfo, null, &descriptorPool).enforceVK;

		foreach(uni; uniforms) {
			uni.generateNewPage();
		}
		foreach(image; images) {
			image.generate(10, vec2i(1024, 1024));
		}
	}

	VkPipelineShaderStageCreateInfo[] getStageInfo() {
		VkPipelineShaderStageCreateInfo vertex = {stage: VK_SHADER_STAGE_VERTEX_BIT,
			_module: _vertex,
			pName: "main"};
		VkPipelineShaderStageCreateInfo fragment = {stage: VK_SHADER_STAGE_FRAGMENT_BIT,
			_module: _fragment,
			pName: "main"};
		return [vertex, fragment];
	}

	VkDescriptorPoolSize[] getPoolSize() {
		VkDescriptorPoolSize[] poolSize;

		foreach(uniform; uniforms) {
            VkDescriptorPoolSize temp = {
				type: uniform.dynamic ? VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
				descriptorCount:1
            };
            poolSize ~= temp;
        }
		foreach(image; images) {
			VkDescriptorPoolSize temp = {
				type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
				descriptorCount: 1};
			poolSize ~= temp;
		}
		return poolSize;
	}

	private void _makeShaderModule(out VkShaderModule shader, ubyte[] data) {
        VkShaderModuleCreateInfo createInfo = {
		codeSize: data.length,
		pCode: cast(uint*)data.ptr
        };

        vkCreateShaderModule(Window.device, &createInfo, null, &shader).enforceVK;
	}
}

// Represents an sampler2DArray in the shader
class UniformImage {
	private Shader _shader;
    private size_t _binding;

	public VkDescriptorSetLayout setLayout;
	public VkDescriptorSet set;
	public ImageArray array;
	alias array this;

	// Texture image
    public VkSampler textureSampler;

	this(Shader shader, size_t binding) {
		_shader = shader;
		_binding = binding;
	}

	void generateLayout() {
		VkDescriptorSetLayoutBinding layoutBinding = {
			binding: cast(uint)_binding,
			descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
			descriptorCount: 1,
			stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT,
			pImmutableSamplers: null
		};

        VkDescriptorSetLayoutCreateInfo layoutInfo = {
			bindingCount: 1,
			pBindings: &layoutBinding
        };
        vkCreateDescriptorSetLayout(Window.device, &layoutInfo, null, &setLayout).enforceVK;
	}

	void generate(size_t length, vec2i dimension) {
		array = new ImageArray(length, dimension);
		array.generate();

		// Setup Texture sampler
        VkSamplerCreateInfo samplerInfo = {
			magFilter: VK_FILTER_LINEAR,
			minFilter: VK_FILTER_LINEAR,
			addressModeU: VK_SAMPLER_ADDRESS_MODE_REPEAT,
			addressModeV: VK_SAMPLER_ADDRESS_MODE_REPEAT,
			addressModeW: VK_SAMPLER_ADDRESS_MODE_REPEAT,
			anisotropyEnable: true,
			maxAnisotropy: 16,
			borderColor: VK_BORDER_COLOR_INT_OPAQUE_BLACK,
			unnormalizedCoordinates: false,
			compareEnable: false,
			compareOp: VK_COMPARE_OP_ALWAYS,
			mipmapMode: VK_SAMPLER_MIPMAP_MODE_LINEAR,
			mipLodBias: 0.0f,
			minLod: 0.0f,
			maxLod: 0.0f
        };

        vkCreateSampler(Window.device, &samplerInfo, null, &textureSampler).enforceVK;

		// Create image descritor
        VkDescriptorSetAllocateInfo allocInfo = {
			descriptorPool: _shader.descriptorPool,
			descriptorSetCount: 1,
			pSetLayouts: &setLayout
        };
        vkAllocateDescriptorSets(Window.device, &allocInfo, &set).enforceVK;

        VkDescriptorImageInfo imageInfo = {
			imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
			imageView: array.view,
			sampler: textureSampler
        };

        VkWriteDescriptorSet[] descriptorWrites = [
            {dstSet: set,
				dstBinding: 0,
				dstArrayElement: 0,
				descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
				descriptorCount: 1,
				pBufferInfo: null,
				pImageInfo: &imageInfo,
				pTexelBufferView: null}
        ];

        vkUpdateDescriptorSets(Window.device, cast(uint)descriptorWrites.length, descriptorWrites.ptr, 0, null);
	}
}

private struct UniformVariable_Page {
	public StagingBuffer buffer;
	bool[] used;
	size_t free;
	public VkDescriptorSet set;
}

// Represent a uniform buffer in shader
class UniformBuffer {
	private Shader _shader;

    private size_t _binding;
    private VkShaderStageFlags _shaderStage; // VK_SHADER_STAGE_VERTEX_BIT VK_SHADER_STAGE_FRAGMENT_BIT
    private bool _dynamic;
    private VkDeviceSize _size; // Element size
	private size_t _elementPerPage;

	public VkDescriptorSetLayout setLayout = VK_NULL_ND_HANDLE;
	public UniformVariable_Page[] pages;
	alias pages this;

	this(Shader shader, size_t binding, VkShaderStageFlags shaderStage, bool dynamic = false) {
		this._binding = binding;
		this._shaderStage = shaderStage;
		this._dynamic = dynamic;
		this._shader = shader;
	}

	size_t binding() @property { return _binding; }
	VkShaderStageFlags shaderStage() @property { return _shaderStage; }
	bool dynamic() @property { return _dynamic; }
	ref VkDeviceSize elementSize() @property { return _size; }

	void setElementInfo(VkDeviceSize size, size_t elementPerPage) {
		_size = size;
		_elementPerPage = elementPerPage;
	}

	// Add new element to buffer, size is data to copy and offset is the data offset for the element
	vec2i append(void *data = null, size_t size = 0, size_t offset = 0) {
		bool pageFindNextFree(ref UniformVariable_Page page) {
			if(page.free == _elementPerPage) return false;
			foreach(i; page.free + 1 .. _elementPerPage) {
				if(page.used[i] == false) {
					page.free = i;
					return true;
				}
			}
			page.free = _elementPerPage;
			return false;
		}

		foreach(i, ref page; pages) {
			if(page.free != _elementPerPage) {
				set(vec2i(cast(uint)i, cast(uint)page.free), data, size, offset);
				size_t j = page.free;
				pageFindNextFree(page);

				return vec2i(cast(uint)i, cast(uint)j);
			}
		}

		return vec2i(0, 0);
	}

	// Replace data within buffer, size is data to copy and offset is the data offset for the element
	void set(vec2i pos, void *data, size_t size, size_t offset = 0) {
		if(data !is null) pages[pos.x].buffer.set(data, size, cast(size_t)(offset + _size * pos.y));
		pages[pos.x].used[pos.y] = true;
	}

	void generateLayout() {
		if(setLayout) return;
		VkDescriptorSetLayoutBinding layoutBinding = {
			binding: cast(uint)_binding,
			descriptorType: _dynamic ? VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
			descriptorCount: 1,
			stageFlags: _shaderStage,
			pImmutableSamplers: null
		};

        VkDescriptorSetLayoutCreateInfo layoutInfo = {
			bindingCount: 1,
			pBindings: &layoutBinding
        };
        vkCreateDescriptorSetLayout(Window.device, &layoutInfo, null, &setLayout).enforceVK;
	}

	void generateNewPage() {
		UniformVariable_Page page; page.free = 0;
		page.used = new bool[_elementPerPage]; page.used[] = false;

		page.buffer = new StagingBuffer(VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, _size * _elementPerPage);
		page.buffer.main = new Buffer(VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, _size * _elementPerPage);

		VkDescriptorSetAllocateInfo allocInfo = {
			descriptorPool: _shader.descriptorPool,
			descriptorSetCount: 1,
			pSetLayouts: &setLayout
        };
        vkAllocateDescriptorSets(Window.device, &allocInfo, &page.set).enforceVK;

        VkDescriptorBufferInfo bufferInfo = {
			buffer: page.buffer.main,
			offset: 0,
			range: _size
		};

        VkWriteDescriptorSet descriptorWrite = {
			dstSet: page.set,
			dstBinding: cast(uint)_binding,
			dstArrayElement: 0,
			descriptorType: _dynamic ? VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
			descriptorCount: 1,
			pBufferInfo: &bufferInfo,
			pImageInfo: null,
			pTexelBufferView: null
		};

        vkUpdateDescriptorSets(Window.device, 1, &descriptorWrite, 0, null);

		pages ~= page;
	}
}