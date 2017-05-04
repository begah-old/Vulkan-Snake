module model;

import std.stdio : writeln;
import std.string;
import std.algorithm.iteration : map;

import kxml.xml;

import vulkan;
import pipeline;
import buffer;
import util;
import image;
import commands;
import boundingbox;

class Model {
	private {
		Pipeline _pipeline;
		string _name;
		StagingBuffer _vertices, _normals, _textCoords, _indices;
		Image _image;
		size_t _count, _imageIndex;

		BoundingCube _boundingBox;
	}

	public vec3[] VERTICES_TEMP;
	public vec3i[] INDICES_TEMP;

	this(Pipeline pipeline, string name) {
		_pipeline = pipeline;
		_name = name;
	}

	private XmlNode findNode(XmlNode mainNode, string nodeName) {
		foreach(node; mainNode.getChildren()) {
			if(node.getName() == nodeName) {
				return node;
			}
		}
		return null;
	}

	private float[] getNodeData(XmlNode main) {
		foreach(node; main.getChildren()) {
			if(node.getName() == "float_array") {
				string rawcount = node.getAttributes["count"];
				string rawdata = node.getCData();

				size_t count = rawcount.to!size_t;
				float[] data = new float[count];
				ptrdiff_t index;
				foreach(ref d; data) {
					ptrdiff_t i = rawdata[index .. $ - 1].indexOf(' ');
					if(i == -1) {
						if(index != rawdata.length)
							i = rawdata.length - index;
						else
							break;
					}
					d = rawdata[index .. index + i].to!float;
					index += i + 1;
					if(index >= rawdata.length)
						break;
				}
				return data;
			}
		}
		return null;
	}

	Model load(bool inverseY = true) {
		File f = internal(_name);
		auto data = f.rawRead(new char[cast(size_t)f.size()]);
		f.close();

		XmlNode main = readDocument(cast(immutable)data);
		XmlNode collada = findNode(main, "COLLADA");
		assert(collada !is null, "Could not find collada node in file! : " ~ _name);

		// Load image
		XmlNode imageLibrary = findNode(collada, "library_images");
		if(imageLibrary !is null) {
			XmlNode imageNode = findNode(imageLibrary, "image");
			if(imageNode !is null) {
				_image = new Image(ImageProperties(imageNode.getChildren()[0].getCData()));
				_imageIndex = _pipeline.shader.images[0].append(_image);
			}
		}

		// Load geometry
		XmlNode geometryLibrary = findNode(collada, "library_geometries");
		assert(geometryLibrary !is null, "Could not find library_geometries node in file! : " ~ _name);

		XmlNode geometry = findNode(geometryLibrary, "geometry");
		assert(geometry !is null, "Could not find geometry node in file! : " ~ _name);
		XmlNode mesh = findNode(geometry, "mesh");
		assert(mesh !is null, "Could not find mesh node in file! : " ~ _name);

		XmlNode normal, textcoord, vertices, indices;
		foreach(node; mesh.getChildren()) {
			string* id = "id" in node.getAttributes;
			if(id !is null && indexOf(*id, "position") != -1) {
				vertices = node;
				continue;
			} if(id !is null && indexOf(*id, "normal") != -1) {
				normal = node;
				continue;
			} if(id !is null && indexOf(*id, "map") != -1) {
				textcoord = node;
				continue;
			} if(node.getName() == "polylist") {
				indices = node;
				continue;
			}
		}

		assert(vertices !is null, "Could not find vertices data!");
		assert(indices !is null, "Could not find indices data!");


		float[] vertData = getNodeData(vertices);
		float[] normData = null, textData = null;
		if(normal !is null)
			normData = getNodeData(normal);
		if(textcoord !is null)
			textData = getNodeData(textcoord);

		size_t vert_offset, norm_offset, text_offset;
		int[] indData;
		foreach(node; indices.getChildren()) {
			if(node.getName() == "input") {
				switch(node.getAttributes["semantic"]) {
				case "VERTEX":
					vert_offset = node.getAttributes["offset"].to!size_t;
					break;
				case "NORMAL":
					norm_offset = node.getAttributes["offset"].to!size_t;
					break;
				case "TEXCOORD":
					text_offset = node.getAttributes["offset"].to!size_t;
					break;
				default:break;
				}
			} else if(node.getName() == "p") {
				indData = new int[indices.getAttributes["count"].to!size_t * 9];
				string rawdata = node.getCData();
				ptrdiff_t index;
				foreach(ref ind; indData) {
					ptrdiff_t i = rawdata[index .. $ - 1].indexOf(' ');
					if(i == -1 && index != rawdata.length)
						i = rawdata.length - index;
					ind = rawdata[index .. index + i].to!int;
					index += i + 1;
					if(index >= rawdata.length) {
						break;
					}
				}
			}
		}

		if(normData !is null && textData !is null) {
			IndexFix!(3).work(inverseY, indData, [IndexFix!(3).DataElement(3, vertData), IndexFix!(3).DataElement(3, normData), IndexFix!(3).DataElement(2, textData)]);

			delete indData;
			delete vertData;
			delete normData;
			delete textData;

			indData = IndexFix!(3).IndicesOutput;
			vertData = IndexFix!(3).DataOutput[0];
			normData = IndexFix!(3).DataOutput[1];
			textData = IndexFix!(3).DataOutput[2];
		} else if(normData !is null) {
			IndexFix!(2).work(inverseY, indData, IndexFix!(2).DataElement(3, vertData), IndexFix!(2).DataElement(3, normData));
			delete indData;
			delete vertData;
			delete normData;

			indData = IndexFix!(2).IndicesOutput;
			vertData = IndexFix!(2).DataOutput[0];
			normData = IndexFix!(2).DataOutput[1];
		} else if(textData !is null) {
			IndexFix!(2).work(inverseY, indData, IndexFix!(2).DataElement(3, vertData), IndexFix!(2).DataElement(2, textData));
			delete indData;
			delete vertData;
			delete textData;

			indData = IndexFix!(2).IndicesOutput;
			vertData = IndexFix!(2).DataOutput[0];
			textData = IndexFix!(2).DataOutput[1];
		}

		VERTICES_TEMP.length = vertData.length / 3;
		VERTICES_TEMP[] = (cast(vec3[])vertData);
		INDICES_TEMP.length = indData.length / 3;
		INDICES_TEMP[] = (cast(vec3i[])indData);

		_boundingBox = BoundingCube.fromPoints(cast(vec3[])vertData);

		_vertices = new StagingBuffer(vertData.ptr, vertData.length * float.sizeof);
		_indices = new StagingBuffer(indData.ptr, indData.length * int.sizeof);
		if(normData !is null)
			_normals = new StagingBuffer(normData.ptr, normData.length * float.sizeof);
		if(textData !is null)
			_textCoords = new StagingBuffer(textData.ptr, textData.length * float.sizeof);

		_count = indData.length;

		return this;
	}

	public void bind(Command cmd) {
		vkCmdPushConstants(cmd, _pipeline.pipelineLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, int.sizeof, &_imageIndex);

		VkBuffer[] vertexBuffers = [vertices.main, normals.main, textcoords.main];
		VkDeviceSize[] offsets = [0, 0, 0];
		vkCmdBindVertexBuffers(cmd, 0, cast(uint)vertexBuffers.length, vertexBuffers.ptr, offsets.ptr);

		vkCmdBindIndexBuffer(cmd, indices.main, 0, VK_INDEX_TYPE_UINT32);
	}

	size_t indicesCount() @property { return _count; }
	ref size_t imageIndex() @property { return _imageIndex; }
	StagingBuffer indices() @property { return _indices; }
	StagingBuffer vertices() @property { return _vertices; }
	StagingBuffer normals() @property { return _normals; }
	StagingBuffer textcoords() @property { return _textCoords; }
}

class ModelInstance {
	private {
		Model _model;
		BoundingCube _boundingBox;

		vec3 _position, _rotation, _scale;
		bool dirty;
	}

	public mat4 transform, transformTransposed;

	this(Model model, vec3 position) {
		_model = model;
		_position = position;
		_boundingBox = new BoundingCube(model._boundingBox);
		_rotation = vec3(0);
		_scale = vec3(1);

		dirty = true;
	}

	public void translate(vec3 translation) {
		_position += translation;
		dirty = true;
	}

	public void setPosition(vec3 position) {
		_position = position;
		dirty = true;
	}

	public void rotate(vec3 rotation) {
		_rotation += rotation;
		dirty = true;
	}

	public void setRotation(vec3 rotation) {
		_rotation = rotation;
		dirty = true;
	}

	public void setScale(vec3 scale) {
		_scale = scale;
	}

	public void updateMatrix() {
		if(dirty == false) return;
		transform = mat4.identity.scale(_scale.x, _scale.y, _scale.z);
		transform = transform.rotatex(_rotation.x).rotatey(2 * PI - _rotation.y).rotatez(_rotation.z);
		transform = transform.translate(_position); // Doing it after transposed to accommodate for the inversion of the y axis 
		dirty = false;

		transformTransposed = transform.transposed();

		_boundingBox.copy(_model._boundingBox).apply(transform);
	}

	public Model model() @property { return _model; }
	public vec3 position() @property { return _position; }
	public vec3 rotation() @property { return _rotation; }
	public vec3 scale() @property { return _scale; }
	public BoundingCube boundingBox() @property { return _boundingBox; }
}

private template IndexFix(int N) {
	float[][N] DataOutput;
	int[] IndicesOutput;

	struct DataElement {
		size_t elementSize;
		float[] data;
	}

	size_t toIndice(size_t i) {
		return i * N;
	}

	void work(bool inverseY, int[] Indices, DataElement[N] Data...) {
		foreach(i, d; Data) {
			DataOutput[i].reserve = d.data.length * 2;
		}

		IndicesOutput = new int[Indices.length / Data.length];
		int[int[N]] storage;

		foreach(i; 0 .. Indices.length / N) {
			int[N] c; c[0 .. N] = Indices[toIndice(i) .. toIndice(i + 1)];
			int* test = c in storage;

			if(test !is null)
				IndicesOutput[i] = *test;
			else {
				IndicesOutput[i] = cast(uint)(DataOutput[0].length / Data[0].elementSize);
				storage[c] = IndicesOutput[i];
				foreach(j, d; Data) {
					DataOutput[j] ~= d.data[Indices[toIndice(i) + j] * d.elementSize .. (Indices[toIndice(i) + j] + 1) * d.elementSize];
					if(d.elementSize == 3) {
						float y = DataOutput[j][$ - 1] * (inverseY ? -1 : 1);
						DataOutput[j][$ - 1] = DataOutput[j][$ - 2];
						DataOutput[j][$ - 2] = y;
					}
				}
			}
		}
	}
}