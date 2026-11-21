// Compares the C++ world generator with reference dumps of the HTML version.
//   node legacy/tests/worldref.js <seed>              -> legacy/tests/ref/<seed>/
//   g++ -O2 -std=c++17 -I native/src native/tests/worldgen_test.cpp native/src/core/worldgen.cpp -o wgtest
//   ./wgtest legacy/tests/ref/<seed> <seed>
#include "core/worldgen.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

template <class T>
std::vector<T> load(const std::string &path) {
	std::ifstream f(path, std::ios::binary);
	std::vector<char> raw((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
	std::vector<T> v(raw.size() / sizeof(T));
	std::memcpy(v.data(), raw.data(), v.size() * sizeof(T));
	return v;
}

template <class T>
bool cmp(const char *name, const std::vector<T> &got, const std::vector<T> &want, int width) {
	if (got.size() != want.size()) {
		std::printf("  FAIL %-9s size %zu, want %zu\n", name, got.size(), want.size());
		return false;
	}
	size_t bad = 0, first = size_t(-1);
	for (size_t i = 0; i < got.size(); i++)
		if (std::memcmp(&got[i], &want[i], sizeof(T)) != 0) { if (first == size_t(-1)) first = i; bad++; }
	if (!bad) {
		std::printf("  ok   %-9s %zu values identical\n", name, got.size());
		return true;
	}
	std::printf("  FAIL %-9s %zu of %zu differ, first at %zu (x=%zu y=%zu): got %.9g want %.9g\n", name, bad, got.size(), first,
			first % width, first / width, double(got[first]), double(want[first]));
	return false;
}

int main(int argc, char **argv) {
	std::string dir = argc > 1 ? argv[1] : "legacy/tests/ref/777";
	uint32_t seed = argc > 2 ? uint32_t(std::stoul(argv[2])) : 777;
	tr::WorldParams p;
	auto t0 = std::chrono::steady_clock::now();
	tr::World w = tr::generate_world(seed, p);
	double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
	std::printf("seed %u: generated in %.0f ms, T=%.17g land=%d states=%zu\n", seed, ms, w.T, w.land_count, w.countries.size());
	bool ok = true;
	ok &= cmp("low", w.low, load<float>(dir + "/low.f32"), p.mw / 2);
	ok &= cmp("H", w.H, load<float>(dir + "/H.f32"), p.mw);
	ok &= cmp("Mf", w.Mf, load<float>(dir + "/Mf.f32"), p.mw);
	ok &= cmp("land", w.land, load<uint8_t>(dir + "/land.u8"), p.mw);
	ok &= cmp("ownGrow", w.own_grow, load<int8_t>(dir + "/ownGrow.i8"), p.mw);
	ok &= cmp("sqd", w.sqd, load<uint8_t>(dir + "/sqd.u8"), w.sqw);
	ok &= cmp("sql", w.sql, load<int16_t>(dir + "/sql.i16"), w.sqw * 2);
	ok &= cmp("own", w.own, load<int8_t>(dir + "/own.i8"), p.mw);
	// countries: label point, seed, neighbours (compared as text with the JSON from the reference)
	std::ifstream mf(dir + "/meta.json");
	std::string meta((std::istreambuf_iterator<char>(mf)), std::istreambuf_iterator<char>());
	size_t bad = 0;
	for (auto &c : w.countries) {
		std::string want = "{\"idx\":" + std::to_string(c.idx) + ",";
		std::string nb;
		for (size_t i = 0; i < c.neighbors.size(); i++) nb += (i ? "," : "") + std::to_string(c.neighbors[i]);
		char buf[256];
		if (c.no_label) std::snprintf(buf, sizeof buf, "\"lx\":null,\"ly\":null,\"cap\":{\"x\":%d,\"y\":%d},\"neighbors\":[%s]", c.cap_x, c.cap_y, nb.c_str());
		else std::snprintf(buf, sizeof buf, "\"lx\":%d,\"ly\":%d,\"cap\":{\"x\":%d,\"y\":%d},\"neighbors\":[%s]", c.lx, c.ly, c.cap_x, c.cap_y, nb.c_str());
		size_t at = meta.find(want);
		if (at == std::string::npos || meta.find(buf, at) != meta.find("\"lx\"", at)) {
			if (bad < 3) std::printf("  country %d differs: %s\n", c.idx, buf);
			bad++;
		}
	}
	std::printf("  %s countries %zu, %zu differ\n", bad ? "FAIL" : "ok  ", w.countries.size(), bad);
	ok &= bad == 0;
	std::printf(ok ? "ALL IDENTICAL\n" : "DIFFERENCES FOUND\n");
	return ok ? 0 : 1;
}
