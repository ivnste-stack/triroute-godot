#include "tr_label_layout.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector4.hpp>
#include <cmath>

namespace godot {

void TRLabelLayout::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_instances", "count"), &TRLabelLayout::set_instances);
	ClassDB::bind_method(D_METHOD("set_instance", "i", "bounds", "uv"), &TRLabelLayout::set_instance);
	ClassDB::bind_method(D_METHOD("set_towns", "xz", "order", "min_ppu", "caps", "mk", "lb"), &TRLabelLayout::set_towns);
	ClassDB::bind_method(D_METHOD("set_town_size", "pid", "s", "w", "h", "has_marker"), &TRLabelLayout::set_town_size);
	ClassDB::bind_method(D_METHOD("set_points", "xz", "inst"), &TRLabelLayout::set_points);
	ClassDB::bind_method(D_METHOD("set_point_picture", "k", "size", "bounds", "uv"), &TRLabelLayout::set_point_picture);
	ClassDB::bind_method(D_METHOD("set_chip", "k", "x", "z", "pid", "near_i", "far_i", "lx", "w_near", "h_near", "w_far", "h_far"), &TRLabelLayout::set_chip);
	ClassDB::bind_method(D_METHOD("clear_chips"), &TRLabelLayout::clear_chips);
	ClassDB::bind_method(D_METHOD("layout", "view_proj", "viewport", "dpr", "ppu", "cp_size", "far"), &TRLabelLayout::layout);
	ClassDB::bind_method(D_METHOD("buffer"), &TRLabelLayout::buffer);
}

void TRLabelLayout::set_instances(int count) {
	inst_.assign(size_t(count), Inst());
	buf_.resize(int64_t(count) * 12);
	float *b = buf_.ptrw();
	for (int64_t i = 0; i < buf_.size(); i++) b[i] = 0.f;
}

void TRLabelLayout::set_instance(int i, const Rect2 &bounds, const Rect2 &uv) {
	if (i < 0 || i >= int(inst_.size())) return;
	inst_[size_t(i)] = {float(bounds.position.x), float(bounds.position.y), float(bounds.size.x), float(bounds.size.y),
		float(uv.position.x), float(uv.position.y), float(uv.size.x), float(uv.size.y)};
}

void TRLabelLayout::set_towns(const PackedFloat32Array &xz, const PackedInt32Array &order, const PackedFloat32Array &min_ppu, const PackedInt32Array &caps,
		const PackedInt32Array &mk, const PackedInt32Array &lb) {
	const int n = int(xz.size() / 2);
	towns_.assign(size_t(n), Town());
	for (int i = 0; i < n; i++) {
		Town &t = towns_[size_t(i)];
		t.x = xz[i * 2];
		t.z = xz[i * 2 + 1];
		t.min_ppu = i < min_ppu.size() ? min_ppu[i] : 0.f;
		t.cap = i < caps.size() && caps[i] != 0;
		t.mk = i < mk.size() ? mk[i] : -1;
		t.lb = i < lb.size() ? lb[i] : -1;
	}
	order_.assign(order.ptr(), order.ptr() + order.size());
}

void TRLabelLayout::set_town_size(int pid, float s, float w, float h, bool has_marker) {
	if (pid < 0 || pid >= int(towns_.size())) return;
	Town &t = towns_[size_t(pid)];
	t.s = s;
	t.w = w;
	t.h = h;
	t.has_mk = has_marker;
}

void TRLabelLayout::set_points(const PackedFloat32Array &xz, const PackedInt32Array &inst) {
	const int n = int(xz.size() / 2);
	points_.assign(size_t(n), Point());
	for (int i = 0; i < n; i++) points_[size_t(i)] = {xz[i * 2], xz[i * 2 + 1], i < inst.size() ? inst[i] : -1};
}

void TRLabelLayout::set_point_picture(int k, float size, const Rect2 &bounds, const Rect2 &uv) {
	if (k >= int(cp_sizes_.size())) {
		cp_sizes_.resize(size_t(k + 1));
		cp_inst_.resize(size_t(k + 1));
	}
	cp_sizes_[size_t(k)] = size;
	cp_inst_[size_t(k)] = {float(bounds.position.x), float(bounds.position.y), float(bounds.size.x), float(bounds.size.y),
		float(uv.position.x), float(uv.position.y), float(uv.size.x), float(uv.size.y)};
}

void TRLabelLayout::clear_chips() { chips_.clear(); }

void TRLabelLayout::set_chip(int k, float x, float z, int pid, int near_i, int far_i, float lx, float w_near, float h_near, float w_far, float h_far) {
	if (k >= int(chips_.size())) chips_.resize(size_t(k + 1));
	chips_[size_t(k)] = {x, z, pid, near_i, far_i, lx, w_near, w_far, h_near, h_far};
}

// one instance: hidden (zero scale) or its rectangle at the anchor, on whole pixels so the text stays sharp.
// 2D MultiMesh buffer: x.x, y.x, pad, origin.x, x.y, y.y, pad, origin.y, then the custom data (the atlas rect)
void TRLabelLayout::put(int i, bool on, float ax, float ay, const Inst *pic) {
	if (i < 0 || i >= int(inst_.size())) return;
	const Inst &q = pic ? *pic : inst_[size_t(i)];
	float *b = buf_.ptrw() + int64_t(i) * 12;
	if (!on) {
		b[0] = b[5] = 0.f;
		b[3] = b[7] = -1e5f;
		return;
	}
	b[0] = q.bw;
	b[1] = 0.f;
	b[2] = 0.f;
	b[3] = std::round(ax + q.bx);
	b[4] = 0.f;
	b[5] = q.bh;
	b[6] = 0.f;
	b[7] = std::round(ay + q.by);
	b[8] = q.u;
	b[9] = q.v;
	b[10] = q.uw;
	b[11] = q.vh;
}

// Camera3D.unproject_position: clip space → the viewport; false when the point is behind the camera
static inline bool project(const Projection &vp, const Vector2 &size, float x, float z, Vector2 &out) {
	const Vector4 c = vp.xform(Vector4(x, 0, z, 1));
	if (c.w <= 1e-6f) return false;
	out.x = (c.x / c.w * 0.5f + 0.5f) * size.x;
	out.y = (-c.y / c.w * 0.5f + 0.5f) * size.y;
	return true;
}

PackedFloat32Array TRLabelLayout::layout(const Projection &view_proj, const Vector2 &viewport, float dpr, float ppu, float cp_size, bool far) {
	PackedFloat32Array out;
	const float W = viewport.x * dpr, H = viewport.y * dpr;
	auto on_screen = [&](float x, float z, float mx, float my, Vector2 &c) {
		if (!project(view_proj, viewport, x, z, c)) return false;
		c *= dpr;
		return c.x >= -mx && c.y >= -my && c.x <= W + mx && c.y <= H + my;
	};
	// border checkpoints: the picture of the nearest size
	const Inst *cp_pic = nullptr;
	float best = 1e9f;
	for (size_t k = 0; k < cp_sizes_.size(); k++) {
		const float d = std::fabs(cp_sizes_[k] - cp_size);
		if (d < best) {
			best = d;
			cp_pic = &cp_inst_[k];
		}
	}
	for (const Point &p : points_) {
		Vector2 c;
		const bool vis = cp_size > 0 && cp_pic && on_screen(p.x, p.z, 20, 20, c);
		put(p.i, vis, c.x, c.y, cp_pic);
	}
	// settlements
	struct Box {
		float x0, y0, x1, y1;
	};
	std::vector<Box> boxes;
	boxes.reserve(256);
	for (int pid : order_) {
		if (pid < 0 || pid >= int(towns_.size())) continue;
		const Town &t = towns_[size_t(pid)];
		Vector2 c;
		if (!(ppu > t.min_ppu && on_screen(t.x, t.z, 60, 60, c))) {
			put(t.mk, false, 0, 0);
			put(t.lb, false, 0, 0);
			continue;
		}
		put(t.mk, t.has_mk, c.x, c.y);
		if (t.cap) {   // capitals use the country chip
			put(t.lb, false, 0, 0);
			continue;
		}
		const float lx = c.x + t.s + 5 * dpr, ly = c.y - t.h / 2;
		bool hit = false;
		for (const Box &b : boxes) {
			if (lx < b.x1 && lx + t.w > b.x0 && ly < b.y1 && ly + t.h > b.y0) {
				hit = true;
				break;
			}
		}
		if (hit) {
			put(t.lb, false, 0, 0);
			continue;
		}
		boxes.push_back({lx, ly, lx + t.w, ly + t.h});
		out.append_array(PackedFloat32Array({float(pid), lx, ly, t.w, t.h}));
		put(t.lb, true, lx, ly);
	}
	// country chips over everything
	for (const Chip &ch : chips_) {
		Vector2 c;
		const bool vis = on_screen(ch.x, ch.z, 80, 40, c);
		put(ch.near, vis && !far, c.x, c.y);
		put(ch.far, vis && far, c.x, c.y);
		if (vis && ch.pid >= 0) {
			const float w = far ? ch.w_far : ch.w_near, h = far ? ch.h_far : ch.h_near;
			out.append_array(PackedFloat32Array({float(ch.pid), c.x - 10 * dpr, c.y - h / 2, ch.lx + w + 10 * dpr, h}));
		}
	}
	return out;
}

} // namespace godot
