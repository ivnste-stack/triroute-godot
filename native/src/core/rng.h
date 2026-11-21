// Mulberry32 RNG and Perlin noise: exact ports of mulberry() in 03-core.js and makePerlin() in 04-map.js.
#pragma once
#include <cstdint>
#include <cmath>
#include <array>
#include "jsmath.h"

namespace tr {

class Mulberry {
public:
	explicit Mulberry(uint32_t seed) : a_(seed) {}
	// next value in [0,1)
	double operator()() {
		a_ = a_ + 0x6D2B79F5u;
		uint32_t t = (a_ ^ (a_ >> 15)) * (1u | a_);
		t = (t + ((t ^ (t >> 7)) * (61u | t))) ^ t;
		return double(t ^ (t >> 14)) / 4294967296.0;
	}

private:
	uint32_t a_;
};

class Perlin {
public:
	explicit Perlin(Mulberry &rng) {
		std::array<int, 256> perm;
		for (int i = 0; i < 256; i++) perm[i] = i;
		for (int i = 255; i > 0; i--) {
			int j = int(std::floor(rng() * (i + 1)));
			std::swap(perm[i], perm[j]);
		}
		for (int i = 0; i < 512; i++) p_[i] = uint8_t(perm[i & 255]);
		for (int i = 0; i < 16; i++) {
			double a = double(i) / 16 * PI * 2;
			gx_[i] = float(std::cos(a));   // Float32Array in the original
			gy_[i] = float(std::sin(a));
		}
	}
	double operator()(double x, double y) const {
		double xi = std::floor(x), yi = std::floor(y), xf = x - xi, yf = y - yi;
		int X = int(int64_t(xi) & 255), Y = int(int64_t(yi) & 255);
		double u = xf * xf * xf * (xf * (xf * 6 - 15) + 10), v = yf * yf * yf * (yf * (yf * 6 - 15) + 10);
		int a = p_[p_[X] + Y] & 15, b = p_[p_[X + 1] + Y] & 15, c = p_[p_[X] + Y + 1] & 15, d = p_[p_[X + 1] + Y + 1] & 15;
		double n00 = double(gx_[a]) * xf + double(gy_[a]) * yf, n10 = double(gx_[b]) * (xf - 1) + double(gy_[b]) * yf;
		double n01 = double(gx_[c]) * xf + double(gy_[c]) * (yf - 1), n11 = double(gx_[d]) * (xf - 1) + double(gy_[d]) * (yf - 1);
		double x1 = n00 + (n10 - n00) * u, x2 = n01 + (n11 - n01) * u;
		return x1 + (x2 - x1) * v;
	}

private:
	uint8_t p_[512];
	float gx_[16], gy_[16];
};

} // namespace tr
