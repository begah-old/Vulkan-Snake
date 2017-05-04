# Vulkan-Snake

A snake mini game made using D and the Vulkan Graphic API.

[![Preview](https://github.com/Begah/Vulkan-Snake/blob/master/Screenshot.png)](https://github.com/Begah/Vulkan-Snake)

# Controls

- WASD to control the snake direction
- Keypad arrows + Left shit and Space to control camera position
- Arrows to control camera rotation

# Install

Simply execute
'''
dub
'''
in the command line.

# Source code

The source code, as of now, is fairly poorly commented and documented.

The Pipeline class:
- Contains the vulkan pipeline and renderpass handles
- Contains a unique shader object

The Shader class:
- Contains the vulkan shader and shader layout handles
- Contains all different uniforms

The Uniform classes:
- **UniformBuffer**: Contains an array of uniform elements accessible using offsets
- **UniformImage**: Contains an array of images accessible using the push-constant textureID in the fragment shader

# Know issues ( that will probably not be fixed since this is a test)

- The game will be in a undefined state after than snake obtained a fixed length or more.

# Libraries used

- **kxml** : XML parsing
- **gl3n** : Math library
- **imageformats** : Decoders for PNG, TGA, BMP, JPEG and encoders for PNG, TGA, BMP.
- **derelict-glfw3** : Dynamic binding for GLFW 3
- **erupted** : Dynamic binding for Vulkan