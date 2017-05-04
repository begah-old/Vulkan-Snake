module image_array;

import vulkan;
import image;

class ImageArray {
	private {
		size_t _length; // Number of layers available
		vec2i _size; // Dimension (width/height) of each individual images
		Image[] _images; // List of images stored in descriptor, null if slot empty
		bool[] _dirty; bool _isDirty;

		size_t _free; // Fist index free, or if all indexes are used, free = user.length
		Image _array;
	}

	this(size_t length, vec2i size, bool generate = true) {
		_length = length;
		_size = size;
	}

	public void generate() {
		if(_images !is null) return;

		_images = new Image[_length];
		foreach(ref image; _images)
			image = null;
		_dirty = new bool[_length];
		foreach(ref b; _dirty)
			b = false;
		_free = 0;
		_isDirty = false;

		_array = new Image(ImageProperties(_length, _size.x, _size.y));
		_array.generateImageView(VK_IMAGE_ASPECT_COLOR_BIT, VK_IMAGE_VIEW_TYPE_2D_ARRAY);
	}

	public size_t append(Image image) {
		if(_free < _length) {
			_images[_free] = image;
			_dirty[_free] = _isDirty = true;

			size_t r = _free;
			bool found = false;
			foreach(i; _free + 1 .. _length) {
				if(_images[i] is null) {
					found = true;
					_free = i;
					break;
				}
			}
			if(!found) {
				// Could not find anymore free places
			}
			return r;
		}
		// Could not find anymore free places

		return 0;
	}

	public void flush() {
		if(!_isDirty) return;

        _array.changeLayout(VK_IMAGE_LAYOUT_PREINITIALIZED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
		foreach(i, ref b; _dirty) {
			if(b) {
				_images[i].changeLayout(VK_IMAGE_LAYOUT_PREINITIALIZED, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
				_images[i].transferDataTo(_array, i);

				b = false;
			}
		}
        _array.changeLayout(VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
	}

	alias array this;
	public Image array() @property { return _array; }
}