module pipeline;

import std.stdio;

import vulkan;
import window;
import util;
import shader;

class Pipeline {
    private {
        bool _initialized = false, _generateFramebuffer = false;
        bool _enableDepthTesting = true;
        Shader _shader;

        alias VertexInfoFunTemplate = VkVertexInputAttributeDescription[] function(out VkVertexInputBindingDescription[]);
        VertexInfoFunTemplate _vertexInfoFun;

        VkRenderPass _renderPass;

        VkPipelineLayout _pipelineLayout;
        VkPipeline _pipeline;
    }

    this(string vertexShader, string fragmentShader) {
        _shader = new Shader(vertexShader, fragmentShader);
    }

    bool toggleDepthTesting() {
        _enableDepthTesting = !_enableDepthTesting;
        return _enableDepthTesting;
    }

    void setVertexInfoCallback(VertexInfoFunTemplate infoFunc) {
        _vertexInfoFun = infoFunc;
    }

    void generate(bool generateFramebuffer = false) {
        _generateRenderPass();

		_shader.generate();
        _generatePipeline();

		if(generateFramebuffer) generateSwapChainFramebuffer();
		
        _initialized = true;
    }

    static public VkFormat _findSupportedDepthFormat(VkFormat[] candidates, VkImageTiling tiling, VkFormatFeatureFlags features) {
        foreach(format; candidates) {
            VkFormatProperties props;
            vkGetPhysicalDeviceFormatProperties(Window.physicalDevice, format, &props);

            if (tiling == VK_IMAGE_TILING_LINEAR && (props.linearTilingFeatures & features) == features) {
                return format;
            } else if (tiling == VK_IMAGE_TILING_OPTIMAL && (props.optimalTilingFeatures & features) == features) {
                return format;
            }
        }
        throw new Exception("Not supported depth format found");
    }

    private void _generateRenderPass() {
        VkAttachmentDescription colorAttachment = {
            format: Window.swapChainImageFormat,
            samples: VK_SAMPLE_COUNT_1_BIT,
            loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
            storeOp: VK_ATTACHMENT_STORE_OP_STORE,
            stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
            initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
            finalLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        VkAttachmentDescription depthAttachment = {
            format: _findSupportedDepthFormat([VK_FORMAT_D32_SFLOAT, VK_FORMAT_D32_SFLOAT_S8_UINT, VK_FORMAT_D24_UNORM_S8_UINT], VK_IMAGE_TILING_OPTIMAL, VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT),
            samples: VK_SAMPLE_COUNT_1_BIT,
            loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
            storeOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
            stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
            initialLayout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
            finalLayout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };

        VkAttachmentReference colorAttachmentRef = {
            attachment: 0,
            layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        VkAttachmentReference depthAttachmentRef = {
            attachment: 1,
            layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        };

        VkSubpassDescription subpass = {
            pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
            colorAttachmentCount: 1,
            pColorAttachments: &colorAttachmentRef,
            pDepthStencilAttachment: _enableDepthTesting ? &depthAttachmentRef : null
        };

        VkSubpassDependency dependency = {
            srcSubpass: VK_SUBPASS_EXTERNAL,
            dstSubpass: 0,
            srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            srcAccessMask: 0,
            dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
        };

        VkAttachmentDescription[] attachments = [colorAttachment];
        if(_enableDepthTesting) attachments ~= depthAttachment;

        VkRenderPassCreateInfo renderPassInfo = {
            attachmentCount: attachments.length,
            pAttachments: attachments.ptr,
            subpassCount: 1,
            pSubpasses: &subpass,
            dependencyCount: 1,
            pDependencies: &dependency
        };

        vkCreateRenderPass(Window.device, &renderPassInfo, null, &_renderPass).enforceVK;
    }

    private void _generatePipeline() {
        VkVertexInputBindingDescription[] bindingDescription;
        VkVertexInputAttributeDescription[] attributeDescriptions = _vertexInfoFun(bindingDescription);

        VkPipelineVertexInputStateCreateInfo vertexInputInfo = {
            vertexBindingDescriptionCount: cast(size_t)bindingDescription.length,
            pVertexBindingDescriptions: bindingDescription.ptr,
            vertexAttributeDescriptionCount: cast(size_t)attributeDescriptions.length,
            pVertexAttributeDescriptions: attributeDescriptions.ptr
        };

        VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
            topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            primitiveRestartEnable: false
        };

        VkViewport viewport = {
            x: 0.0f,
            y: 0.0f,
            width: cast(float)Window.swapChainExtent.width,
            height: cast(float)Window.swapChainExtent.height,
            minDepth: 0.0f,
            maxDepth: 1.0f
        };

        VkRect2D scissor = {
            offset: {0, 0},
            extent: Window.swapChainExtent
        };

        VkPipelineViewportStateCreateInfo viewportState = {
            viewportCount: 1,
            pViewports: &viewport,
            scissorCount: 1,
            pScissors: &scissor
        };

        VkPipelineRasterizationStateCreateInfo rasterizer = {
            depthClampEnable: false,
            rasterizerDiscardEnable: false,
            polygonMode: VK_POLYGON_MODE_FILL,
            lineWidth: 1.0f,
            cullMode: VK_CULL_MODE_BACK_BIT,
            frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE,
            depthBiasEnable: false,
            depthBiasConstantFactor: 0,
            depthBiasClamp: 0,
            depthBiasSlopeFactor: 0
        };

        VkPipelineMultisampleStateCreateInfo multisampling = {
            sampleShadingEnable: false,
            rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
            minSampleShading: 1,
            pSampleMask: null,
            alphaToCoverageEnable: false,
            alphaToOneEnable: false
        };

        // VkPipelineDepthStencilStateCreateInfo
        VkPipelineColorBlendAttachmentState colorBlendAttachment = {
            colorWriteMask: VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
            blendEnable: false, /* true */
            srcColorBlendFactor: VK_BLEND_FACTOR_ONE, /* VK_BLEND_FACTOR_SRC_ALPHA */
            dstColorBlendFactor: VK_BLEND_FACTOR_ZERO, /* VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA */
            colorBlendOp: VK_BLEND_OP_ADD,
            srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE,
            dstAlphaBlendFactor: VK_BLEND_FACTOR_ZERO,
            alphaBlendOp: VK_BLEND_OP_ADD
        };

        VkPipelineColorBlendStateCreateInfo colorBlending = {
            logicOpEnable: false,
            logicOp: VK_LOGIC_OP_COPY,
            attachmentCount: 1,
            pAttachments: &colorBlendAttachment
        };

		// Uniform variables setup
		VkDescriptorSetLayout[] setLayouts;

		foreach(image; _shader.images) {
			image.generateLayout();
			setLayouts ~= image.setLayout;
		}
		foreach(uni; _shader.uniforms) {
			uni.generateLayout();
			setLayouts ~= uni.setLayout;
		}

		VkPushConstantRange pushConstant = {
			stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT,
			offset: 0,
			size: int.sizeof
		};

        VkPipelineLayoutCreateInfo pipelineLayoutInfo = {
            setLayoutCount: setLayouts.length,
            pSetLayouts: setLayouts.ptr,
            pushConstantRangeCount: 1,
            pPushConstantRanges: &pushConstant,
        };

        vkCreatePipelineLayout(Window.device, &pipelineLayoutInfo, null, &_pipelineLayout).enforceVK;

        VkPipelineDepthStencilStateCreateInfo depthStencil = {
            depthTestEnable: _enableDepthTesting,
            depthWriteEnable: true,
            depthCompareOp: VK_COMPARE_OP_LESS,
            depthBoundsTestEnable: false,
            minDepthBounds: 0.0f,
            maxDepthBounds: 1.0f,
            stencilTestEnable: false,
        };

		auto shaderStages = _shader.getStageInfo();
        VkGraphicsPipelineCreateInfo pipelineInfo = {
            stageCount: shaderStages.length,
            pStages: shaderStages.ptr,
            pVertexInputState: &vertexInputInfo,
            pInputAssemblyState: &inputAssembly,
            pViewportState: &viewportState,
            pRasterizationState: &rasterizer,
            pMultisampleState: &multisampling,
            pDepthStencilState: &depthStencil, // Optional
            pColorBlendState: &colorBlending,
            pDynamicState: null, // Optional
            layout: _pipelineLayout,
            renderPass: _renderPass,
            subpass: 0,
            basePipelineHandle: VK_NULL_ND_HANDLE,
            basePipelineIndex: -1,
        };

        vkCreateGraphicsPipelines(Window.device, VK_NULL_ND_HANDLE, 1, &pipelineInfo, null, &_pipeline).enforceVK;
    }

	public void generateSwapChainFramebuffer() {
		// Create depth image
		if(Window.depthImage !is null)
			delete Window.depthImage;
		VkFormat depthFormat = _findSupportedDepthFormat([VK_FORMAT_D32_SFLOAT, VK_FORMAT_D32_SFLOAT_S8_UINT, VK_FORMAT_D24_UNORM_S8_UINT], VK_IMAGE_TILING_OPTIMAL, VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT);
        Window.depthImage = new Image(ImageProperties(Window.swapChainExtent.width, Window.swapChainExtent.height, 1, depthFormat, VK_IMAGE_TILING_OPTIMAL, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT));
        Window.depthImage.generateImageView(VK_IMAGE_ASPECT_DEPTH_BIT);

        Window.depthImage.changeLayout(VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL);

		// Create swap chain framebuffers
		Window.swapChainFramebuffers.length = Window.swapChainImage.length;

        foreach(i; 0 .. Window.swapChainImage.length) {
            VkImageView[2] attachments = [Window.swapChainImage[i].view, Window.depthImage.view];

            VkFramebufferCreateInfo framebufferInfo = {
				renderPass: renderPass,
				attachmentCount: attachments.length,
				pAttachments: attachments.ptr,
				width: Window.swapChainExtent.width,
				height: Window.swapChainExtent.height,
				layers: 1
            };
            vkCreateFramebuffer(Window.device, &framebufferInfo, null, &Window.swapChainFramebuffers[i]).enforceVK;
        }

		_generateFramebuffer = true;
	}

    public VkRenderPass renderPass() @property { return _renderPass; }
    public VkPipelineLayout pipelineLayout() @property { return _pipelineLayout; }
    public VkPipeline pipeline() @property { return _pipeline; }
	public Shader shader() @property { return _shader; }

	private void cleanup() {
        if(_initialized == false) return;

		vkDestroyPipeline(Window.device, _pipeline, null);
		vkDestroyRenderPass(Window.device, _renderPass, null);

		_initialized = false;
	}

	public void recreate() {
		cleanup();

		_generateRenderPass();
        _generatePipeline();

		if(_generateFramebuffer) generateSwapChainFramebuffer();

		_initialized = true;
	}

    ~this() {
		cleanup();
    }
}
