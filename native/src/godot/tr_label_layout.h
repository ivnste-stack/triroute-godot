// TRLabelLayout: where the town markers, labels, checkpoints and country chips of the map go for a view of the
// camera, written straight into the buffer of one MultiMesh (one draw call for the whole layer). Every piece is
// drawn once into an atlas texture (TownLayer); here, every frame the camera moves, the anchors are projected,
// what is off screen or too small for the zoom is dropped, a label that would cover a more important one is
// skipped (drawBoardTowns of the HTML version) and each instance gets its screen rectangle and atlas rectangle.
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/projection.hpp>
#include <vector>

namespace godot {

class TRLabelLayout : public RefCounted {
	GDCLASS(TRLabelLayout, RefCounted)

	// an instance of the MultiMesh: its rectangle around the anchor (pixels) and in the atlas (0..1)
	struct Inst {
		float bx = 0, by = 0, bw = 0, bh = 0;
		float u = 0, v = 0, uw = 0, vh = 0;
	};
	std::vector<Inst> inst_;
	struct Town {
		float x = 0, z = 0, min_ppu = 0;
		bool cap = false, has_mk = true;
		float s = 0, w = 0, h = 0;    // marker half size, label size (pixels)
		int mk = -1, lb = -1;          // instances
	};
	std::vector<Town> towns_;
	std::vector<int> order_;
	struct Point {                     // checkpoints: one instance, the picture of the nearest size
		float x = 0, z = 0;
		int i = -1;
	};
	std::vector<Point> points_;
	std::vector<float> cp_sizes_;      // the sizes the checkpoint picture was drawn at
	std::vector<Inst> cp_inst_;        // and their rectangles
	struct Chip {                      // country chips: a near and a far picture
		float x = 0, z = 0;
		int pid = -1, near = -1, far = -1;
		float lx = 0, w_near = 0, w_far = 0, h_near = 0, h_far = 0;
	};
	std::vector<Chip> chips_;
	PackedFloat32Array buf_;

	void put(int i, bool on, float ax, float ay, const Inst *pic = nullptr);

protected:
	static void _bind_methods();

public:
	void set_instances(int count);
	void set_instance(int i, const Rect2 &bounds, const Rect2 &uv);
	void set_towns(const PackedFloat32Array &xz, const PackedInt32Array &order, const PackedFloat32Array &min_ppu, const PackedInt32Array &caps,
			const PackedInt32Array &mk, const PackedInt32Array &lb);
	void set_town_size(int pid, float s, float w, float h, bool has_marker);
	void set_points(const PackedFloat32Array &xz, const PackedInt32Array &inst);
	void set_point_picture(int k, float size, const Rect2 &bounds, const Rect2 &uv);
	void set_chip(int k, float x, float z, int pid, int near_i, int far_i, float lx, float w_near, float h_near, float w_far, float h_far);
	void clear_chips();
	// fills the buffer; returns the clickable rectangles: pid, x, y, w, h (labels, then chips on top)
	PackedFloat32Array layout(const Projection &view_proj, const Vector2 &viewport, float dpr, float ppu, float cp_size, bool far);
	PackedFloat32Array buffer() const { return buf_; }
};

} // namespace godot
