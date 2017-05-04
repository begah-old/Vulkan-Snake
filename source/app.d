module app;

import std.stdio;
import core.stdc.stdio : printf;
import core.stdc.string : strlen;
import std.container.rbtree;
import std.exception;
import std.algorithm;
import std.conv;
import std.math : atan, abs;
import std.random;

import vulkan;
import window;
import timer;
import buffer;
import util;
import commands;
import shader;
import model;
import image;
import image_array;
import camera;
import boundingbox;

Timer globalTimer;

Pipeline mainPipeline;
Command[] renderingCommands;
VkSemaphore imageAvailableSemaphore, renderFinishedSemaphore;

float x = 0.0, y = 0, z = -0.1f;

StagingBuffer globalUniform;
UniformBuffer modelUniform;

CameraController controller;

void updateView(long elapsedTime){
    float time = globalTimer.elapsedTime;

    mat4 view = mat4.look_at(vec3(x, y, z), vec3(0), vec3(0, -1, 0)).transposed();

    globalUniform.set(&view, mat4.sizeof, mat4.sizeof);
    globalUniform.transferDataTo(globalUniform.main);
}

extern(C) void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods) nothrow
{
	try {
    if (key == GLFW_KEY_ESCAPE)
        glfwSetWindowShouldClose(window, true);
	else {
		controller.keyCallback(key, action, mods);
	}
    if (key == GLFW_KEY_W && action != GLFW_RELEASE) {
        snake[0].changeDirection(Body.Direction.Up);
    }
    else if(key == GLFW_KEY_S && action != GLFW_RELEASE) {
        snake[0].changeDirection(Body.Direction.Down);
    }

    if (key == GLFW_KEY_A && action != GLFW_RELEASE) {
        snake[0].changeDirection(Body.Direction.Left);
    }
    else if(key == GLFW_KEY_D && action != GLFW_RELEASE) {
        snake[0].changeDirection(Body.Direction.Right);
    }
	}catch(Exception ex) {}
}

class Body {
    enum Direction {
        Left,
        Right,
        Up,
        Down
    }
    struct SyncPoint {
        vec3 start;
        Direction direction;
    }

    static const int RESOLUTION = 16;
    static const float BODY_SIZE = 10;
    static const float SPEED = BODY_SIZE / RESOLUTION;

	ModelInstance instance;
    Direction direction;
    SyncPoint[] syncPoints;
    Body child;
	vec2i uniformPosition; // Position in shader model matrix buffer

    this(float x, float y, Model model) {
        direction = Direction.Right;
		instance = new ModelInstance(model, vec3(x, 0, y));
		uniformPosition = modelUniform.append();
    }

    void transferSyncPointToChild() {
        if(child !is null) {
            child.syncPoints ~= syncPoints[0];
        }
        instance.setPosition(syncPoints[0].start);
        direction = syncPoints[0].direction;
        syncPoints = syncPoints[1..$];
    }

    void changeDirection(Direction direction) {
        if(child !is null)
            child.syncPoints ~= SyncPoint(instance.position, direction);
        this.direction = direction;
    }

	private float getDirectionRotation(Direction dir) {
		switch(dir) {
			case Direction.Left:
				return PI / 2.0f;
			case Direction.Down:
				return PI;
			case Direction.Right:
				return 3.0 * PI / 2.0f;
			case Direction.Up:
				return 0;
			default: return 0;
		}
	}

	void updateRotation() {
		float rotation = getDirectionRotation(direction);

		if(syncPoints.length > 0 && (syncPoints[0].start - instance.position).magnitude < 0.2f) {
			float ratio = 1 - (0.2f - (syncPoints[0].start - instance.position).magnitude) * 5;

			float otherRotation = getDirectionRotation(syncPoints[0].direction);
			if(direction == Direction.Up && syncPoints[0].direction == Direction.Right)
				rotation = 2.0f * PI; // Replace going from 0 to 3PI/2 with 2PI to 3PI/2
			if(syncPoints[0].direction == Direction.Up && direction == Direction.Right)
				otherRotation = 2.0f * PI; // Replace going from 3PI/2 to 0 with 3PI/2 to 2P
			rotation = rotation * ratio + otherRotation * (1 - ratio);
		}

		instance.setRotation(vec3(0, rotation, 0));
	}

    void update(float Fps) {
        float dPos = SPEED / Fps;
        switch(direction) {
			case Direction.Left:
				instance.translate(vec3(-dPos, 0, 0));

				if(syncPoints.length > 0 && instance.position.x < syncPoints[0].start.x)
					transferSyncPointToChild();
				break;
			case Direction.Right:
				instance.translate(vec3(dPos, 0, 0));

				if(syncPoints.length > 0 && instance.position.x > syncPoints[0].start.x)
					transferSyncPointToChild();
				break;
			case Direction.Up:
				instance.translate(vec3(0, 0, dPos));

				if(syncPoints.length > 0 && instance.position.z > syncPoints[0].start.z)
					transferSyncPointToChild();
				break;
			case Direction.Down:
				instance.translate(vec3(0, 0, -dPos));

				if(syncPoints.length > 0 && instance.position.z < syncPoints[0].start.z)
					transferSyncPointToChild();
				break;
			default: assert(0);
        }

		updateRotation();
		instance.updateMatrix();
    }

    static void addLength() nothrow {
        Body temp;
        try { temp = new Body(snake[$ - 1].instance.position.x, snake[$ - 1].instance.position.z, snake_body); 
        temp.direction = snake[$ - 1].direction;
        snake[$ - 1].child = temp;

		float Size = max(snake[$ - 1].instance.boundingBox.max.x - snake[$ - 1].instance.boundingBox.min.x,
							 snake[$ - 1].instance.boundingBox.max.y - snake[$ - 1].instance.boundingBox.min.y);
		switch(snake[$ - 1].direction) {
			case Direction.Up:
				temp.instance.translate(vec3(0, 0, -Size));
				break;
			case Direction.Down:
				temp.instance.translate(vec3(0, 0, Size));
				break;
			case Direction.Left:
				temp.instance.translate(vec3(Size, 0, 0));
				break;
			case Direction.Right:
				temp.instance.translate(vec3(-Size, 0, 0));
				break;
			default: assert(0);
		}} catch(Exception ex) {}

        snake ~= temp;
    }
}
Body[] snake;
VkDeviceSize modelBufferOffset;

Model snake_head, snake_body;
ModelInstance coin, terrain;
vec2i coinUniformPosition, terrainUniformPosition; // Position in shader model matrix buffer

void recordCommand(int index, Command command) {
    command.record();

    VkRenderPassBeginInfo renderPassInfo = {
        renderPass: mainPipeline.renderPass,
        framebuffer: Window.swapChainFramebuffers[index],
        renderArea: {
            offset: {0, 0},
            extent: Window.swapChainExtent,
        },
    };

    VkClearValue[2] clearValues;
    clearValues[0].color.float32 = [0.0f, 0.0f, 0.0f, 1.0f];
    clearValues[1].depthStencil.depth = 1.0f; clearValues[1].depthStencil.stencil = 0;

    renderPassInfo.clearValueCount = clearValues.length;
    renderPassInfo.pClearValues = clearValues.ptr;

    vkCmdBeginRenderPass(command.buffer, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);

    vkCmdBindPipeline(command.buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, mainPipeline.pipeline);

	VkDescriptorSet[] sets;
	uint[] uniform_offset;

	// Draw head
	snake_head.bind(command);

	sets = [mainPipeline.shader.images[0].set, mainPipeline.shader.uniforms[0][0].set, mainPipeline.shader.uniforms[1][0].set];
	uniform_offset = [cast(uint)(modelBufferOffset * snake[0].uniformPosition.y)];
	vkCmdBindDescriptorSets(command.buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, mainPipeline.pipelineLayout, 0, sets.length, sets.ptr, uniform_offset.length, uniform_offset.ptr);
	vkCmdDrawIndexed(command.buffer, snake_head.indicesCount, 1, 0, 0, 0);

	// Draw body
	snake_body.bind(command);

	foreach(i; 1 .. snake.length) {
		sets = [mainPipeline.shader.images[0].set, mainPipeline.shader.uniforms[0][0].set, mainPipeline.shader.uniforms[1][0].set];
		uniform_offset = [cast(uint)(modelBufferOffset * snake[i].uniformPosition.y)];

		vkCmdBindDescriptorSets(command.buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, mainPipeline.pipelineLayout, 0, sets.length, sets.ptr, uniform_offset.length, uniform_offset.ptr);
		vkCmdDrawIndexed(command.buffer, snake_body.indicesCount, 1, 0, 0, 0);
	}

	// Draw coin
	coin.model.bind(command);

	sets = [mainPipeline.shader.images[0].set, mainPipeline.shader.uniforms[0][0].set, mainPipeline.shader.uniforms[1][0].set];
	uniform_offset = [cast(uint)(modelBufferOffset * coinUniformPosition.y)];

	vkCmdBindDescriptorSets(command.buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, mainPipeline.pipelineLayout, 0, sets.length, sets.ptr, uniform_offset.length, uniform_offset.ptr);
	vkCmdDrawIndexed(command.buffer, coin.model.indicesCount, 1, 0, 0, 0);

	// Draw terrain
	terrain.model.bind(command);

	sets = [mainPipeline.shader.images[0].set, mainPipeline.shader.uniforms[0][0].set, mainPipeline.shader.uniforms[1][0].set];
	uniform_offset = [cast(uint)(modelBufferOffset * terrainUniformPosition.y)];

	vkCmdBindDescriptorSets(command.buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, mainPipeline.pipelineLayout, 0, sets.length, sets.ptr, uniform_offset.length, uniform_offset.ptr);
	vkCmdDrawIndexed(command.buffer, terrain.model.indicesCount, 1, 0, 0, 0);

    vkCmdEndRenderPass(command.buffer);

    vkEndCommandBuffer(command.buffer).enforceVK;
}

int main() {
	Window("Isolated", 1000, 1000);
	GraphicsPool = new CommandPool(Window.graphicsQueue, Window.queueFamilies.graphics);
	ComputePool = new CommandPool(Window.computeQueue, Window.queueFamilies.compute);
    
	renderingCommands = GraphicsPool.generateCommands(Window.swapChainImage.length);

    glfwSetKeyCallback(Window.window, &key_callback);

	// Create uniform buffer
	modelBufferOffset = mat4.sizeof;
	
	// Check if there is a limit on minimun size of uniform offset
	if (Window.physicalDeviceProperties.limits.minUniformBufferOffsetAlignment)
		modelBufferOffset = (modelBufferOffset + Window.physicalDeviceProperties.limits.minUniformBufferOffsetAlignment - 1) &
		~(Window.physicalDeviceProperties.limits.minUniformBufferOffsetAlignment - 1);

	// Create a pipeline object
    mainPipeline = new Pipeline("vert.spv", "frag.spv"); Window.pipelines ~= mainPipeline;
	mainPipeline.shader.setUniforms([new UniformBuffer(mainPipeline.shader, 1, VK_SHADER_STAGE_VERTEX_BIT), new UniformBuffer(mainPipeline.shader, 2, VK_SHADER_STAGE_VERTEX_BIT, true)]);
    mainPipeline.shader.setImages([new UniformImage(mainPipeline.shader, 0)]);
	mainPipeline.setVertexInfoCallback(&Vertex.describeVertex); // Set the description of the vertex shader inputs
	
	// Set size of element and number of elements to create for each uniforms
	mainPipeline.shader.uniforms[0].setElementInfo(mat4.sizeof * 2, 1); 
	mainPipeline.shader.uniforms[1].setElementInfo(modelBufferOffset, 12);

    mainPipeline.generate(true);

	//
	mainPipeline.shader.generatePool();

	// Create semaphores
	VkSemaphoreCreateInfo semaphoreInfo = {};

	vkCreateSemaphore(Window.device, &semaphoreInfo, null, &imageAvailableSemaphore).enforceVK;
	vkCreateSemaphore(Window.device, &semaphoreInfo, null, &renderFinishedSemaphore).enforceVK;

	globalUniform = mainPipeline.shader.uniforms[0].pages[0].buffer;
    modelUniform = mainPipeline.shader.uniforms[1];

	snake_body = new Model(mainPipeline, "snake_body.dae"); snake_body.load();
	snake_head = new Model(mainPipeline, "snake_head.dae"); snake_head.load();
	Model coinModel = new Model(mainPipeline, "coin.dae"); coinModel.load();
	coin = new ModelInstance(coinModel, vec3(0, 0, -5)); coin.setScale(vec3(1, 1, 0.5f));
	coinUniformPosition = modelUniform.append();

	Model terrainModel = new Model(mainPipeline, "terrain.dae"); terrainModel.load(false);
	terrain = new ModelInstance(terrainModel, vec3(0, 4, 0)); terrain.setScale(vec3(10)); terrain.updateMatrix();
	terrainUniformPosition = modelUniform.append(&terrain.transformTransposed, mat4.sizeof);

	mainPipeline.shader.images[0].array.flush();

	controller = new CameraController(new PerspectiveCamera(vec3(0, -11.35f, 0)));
	controller.camera.rotate(PI, -PI / 2.0f);

    Timer timer = Timer();
    int frameCount;
    double fps=3000;

    globalTimer = Timer();

    snake = [new Body(0, 0, snake_head)];

    timer = timer.reset();

	while (!glfwWindowShouldClose(Window.window)) {
		glfwPollEvents();

		// Update camera
		controller.camera.calculate();
		globalUniform.set(&controller.camera.projectionMatrix, mat4.sizeof, 0);
		globalUniform.set(&controller.camera.viewMatrix, mat4.sizeof, mat4.sizeof);
		globalUniform.transferDataTo(globalUniform.main);

		uint imageIndex;
		vkAcquireNextImageKHR(Window.device, Window.swapChain, uint.max, imageAvailableSemaphore, VK_NULL_ND_HANDLE, &imageIndex);

		// Update model matrix
		terrain.updateMatrix();
		modelUniform.set(terrainUniformPosition, &terrain.transformTransposed, mat4.sizeof);

		// Update coin matrix
		coin.rotate(vec3(0, 0.0005f, 0));
		coin.updateMatrix();
		modelUniform.set(coinUniformPosition, &coin.transformTransposed, mat4.sizeof);

		// Update snake head and body matrices
        foreach(i; 0 .. snake.length) {
            snake[i].update(fps);
            modelUniform.set(snake[i].uniformPosition, &snake[i].instance.transformTransposed, mat4.sizeof);
        }

		// Check if head intersects with coin
		if(snake[0].instance.boundingBox.intersects(coin.boundingBox)) {
			// Move coin to anohter position : while coin is still touching the snake head, keep moving it to another location
			do {
				// Make sure coin is within terrain boundaries
				float halfDist = max(coin.boundingBox.max.x, coin.boundingBox.max.y) / 2.0f;
				vec2 origin = terrain.boundingBox.min.xz + vec2(halfDist);
				vec2 size = terrain.boundingBox.max.xz - origin - vec2(halfDist);

				coin.setPosition(vec3(uniform(origin.x, origin.x + size.x), 0, uniform(origin.y, origin.y + size.y)));
				coin.updateMatrix();
			}while(snake[0].instance.boundingBox.intersects(coin.boundingBox));

			Body.addLength();
		}

		// Transfer all changed matrices to gpu
        modelUniform[0].buffer.transferDataTo(modelUniform[0].buffer.main);

		// Record current frame command
		recordCommand(imageIndex, renderingCommands[imageIndex]);

		VkSemaphore[1] waitSemaphores = [imageAvailableSemaphore];
		VkPipelineStageFlags[1] waitStages = [VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT];
		VkSemaphore[1] signalSemaphores = [renderFinishedSemaphore];
		VkSubmitInfo submitInfo = {
			waitSemaphoreCount: 1,
			pWaitSemaphores: waitSemaphores.ptr,
			pWaitDstStageMask: waitStages.ptr,
			commandBufferCount: 1,
			pCommandBuffers: &renderingCommands[imageIndex].buffer(),
			signalSemaphoreCount: 1,
			pSignalSemaphores: signalSemaphores.ptr
		};

		vkQueueSubmit(Window.graphicsQueue, 1, &submitInfo, VK_NULL_ND_HANDLE).enforceVK;

		VkSwapchainKHR[1] swapChains = [Window.swapChain];
		VkPresentInfoKHR presentInfo = {
			waitSemaphoreCount: 1,
			pWaitSemaphores: signalSemaphores.ptr,
			swapchainCount: 1,
			pSwapchains: swapChains.ptr,
			pImageIndices: &imageIndex,
			pResults: null
		};

		vkQueuePresentKHR(Window.presentQueue, &presentInfo);

        frameCount++;

		// Update FPS
        if(timer.elapsedTime() > 250) {
            fps = frameCount / (timer.elapsedTime() / 1000.0);
            frameCount = 0;
            timer = timer.reset();
			writeln(fps, " fps");
        }
	}

	vkDeviceWaitIdle(Window.device);

	glfwDestroyWindow(Window.window);

	glfwTerminate();

	readln();

	return 0;
}
