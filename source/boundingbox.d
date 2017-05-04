module boundingbox;

import std.math : sqrt;
import gl3n.math : max, abs;

import gl3n.linalg;
import std.conv;

@safe @nogc nothrow:

interface BoundingBox {
	static BoundingBox fromPoints(vec3[] points...);
	static BoundingBox fromPoints(float[] points...);

	void expand(float[3] points);

	bool intersects(BoundingBox box);
	bool intersects(vec3 point);
}

class BoundingSphere : BoundingBox {
	private {
		vec3 totalPoints;
		int numberOfPoints;
	}

	vec3 center;
	float squaredRaduis, raduis;

	static BoundingSphere fromPoints(vec3[] points...) {
		if(points.length == 0) {
			return null;
		}

		BoundingSphere sphere = new BoundingSphere();

		sphere.center = points[0];

		foreach(v; points[1..$]) {
			sphere.expand(v.vector);
		}

		return sphere;
	}

	static BoundingSphere fromPoints(float[] points...)  in { assert(points.length % 3 == 0, "Number of points should be divisible by 3"); } 
	body {
		if(points.length == 0) {
			return null;
		}

		BoundingSphere sphere = new BoundingSphere();

		sphere.center = vec3(points[0 .. 3]);

		for(int i = 1; i < points.length / 3; i++) {
			sphere.expand(to!(float[3])(points[i * 3 .. (i + 1) * 3]));
		}

		return sphere;
	}

	void expand(float[3] points) {
		float lengthSquare = lengthSquareFrom(points);

		if(lengthSquare > squaredRaduis) {
			totalPoints += vec3(points);
			numberOfPoints++;
			vec3 newcenter = totalPoints / numberOfPoints;

			float length = sqrt(lengthSquare);
			vec3 v = newcenter - center;

			float aX = center.x + v.x / length * raduis;
			float aY = center.y + v.y / length * raduis;
			float aZ = center.z + v.z / length * raduis;

			aX -= 2 * (aX - center.x); // Furthest point of old circle from new center
			aY -= 2 * (aY - center.y);
			aZ -= 2 * (aZ - center.z);

			center = newcenter;

			lengthSquare = lengthSquareFrom(points); // Length of new point from new center
			float lengthSquare2 = lengthSquareFrom([aX, aY, aZ]); // Length of point on old circle from new center

			squaredRaduis = max(lengthSquare, lengthSquare2);
			raduis = sqrt(squaredRaduis);
		}
	}

	private float lengthSquareFrom(float[3] points) {
		return (points[0] - center.x) * (points[0] - center.x) + (points[1] - center.y) * (points[1] - center.y) + (points[2] - center.z) * (points[2] - center.z);
	}

	bool intersects(BoundingBox box) {
		return false;
	}

	bool intersects(vec3 point) {
		return false;
	}
}

class BoundingCube : BoundingBox {
	vec3 min, max;

	this() {

	}

	this(BoundingCube cube) {
		min = cube.min;
		max = cube.max;
	}

	static BoundingCube fromPoints(vec3[] points...) {
		if(points.length == 0) {
			return null;
		}

		BoundingCube cube = new BoundingCube();

		cube.min = points[0];
		cube.max = points[0];
		foreach(v; points[1..$]) {
			cube.expand(v.vector);
		}

		return cube;
	}

	static BoundingCube fromPoints(float[] points...)  in { assert(points.length % 3 == 0, "Number of points should be divisible by 3"); } 
	body {
		if(points.length == 0) {
			return null;
		}

		BoundingCube cube = new BoundingCube();

		cube.min = vec3(points[0..3]);
		cube.max = vec3(points[0..3]);

		for(int i = 1; i < points.length / 3; i++) {
			cube.expand(to!(float[3])(points[i * 3 .. (i + 1) * 3]));
		}

		return cube;
	}

	void expand(float[3] points) {
		if (points[0] > max.x) max.x = points[0];
		if (points[1] > max.y) max.y = points[1];
		if (points[2] > max.z) max.z = points[2];
		if (points[0] < min.x) min.x = points[0];
		if (points[1] < min.y) min.y = points[1];
		if (points[2] < min.z) min.z = points[2];
	}

	BoundingCube copy(BoundingCube cube) {
		min = cube.min;
		max = cube.max;
		return this;
	}

	void apply(mat4 transformation) {
		vec3 min = this.min, max = this.max;

		this.min = this.max = (transformation * vec4(min, 1.0f)).xyz;
		expand((transformation * vec4(min.x, min.y, max.z, 1.0f)).xyz.vector); expand((transformation * vec4(min.x, max.y, min.z, 1.0f)).xyz.vector);
		expand((transformation * vec4(min.x, max.y, max.z, 1.0f)).xyz.vector); expand((transformation * vec4(max.x, max.y, max.z, 1.0f)).xyz.vector);
		expand((transformation * vec4(max.x, min.y, min.z, 1.0f)).xyz.vector); expand((transformation * vec4(max.x, min.y, max.z, 1.0f)).xyz.vector); expand((transformation * vec4(max.x, max.y, min.z, 1.0f)).xyz.vector);
	}

	bool intersects(BoundingCube box) {
		vec3 halfDist = (max - min) / 2.0f + (box.max - box.min) / 2.0f;
		vec3 dist = (max + min) / 2.0f - (box.max + box.min) / 2.0f;
		if(abs(dist.x) > halfDist.x) return false;
		if(abs(dist.y) > halfDist.y) return false;
		if(abs(dist.z) > halfDist.z) return false;

		return true;
	}

	bool intersects(BoundingBox box) {
		return false;
	}

	bool intersects(vec3 point) {
		if(min.x <= point.x && point.x <= max.x &&
		   min.y <= point.y && point.y <= max.y &&
		   min.z <= point.z && point.z <= max.z)
			return true;
		return false;
	}
}