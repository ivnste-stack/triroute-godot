// JavaScript-compatible math helpers.
// The world generator must give the same result as the HTML version for the same seed, so every
// operation that JS defines in its own way is reproduced here exactly.
#pragma once
#include <cmath>
#include <cstdint>
#include <algorithm>

namespace tr {

// Math.PI (M_PI is not standard C++ and MinGW does not define it)
constexpr double PI = 3.141592653589793;

// Math.round: nearest integer, ties toward +infinity (Math.round(-2.5) == -2).
inline double js_round(double x) {
	double r = std::floor(x);
	return (x - r >= 0.5) ? r + 1.0 : r;
}

// Math.hypot(a, b) as V8 computes it (builtins/math.tq): scale by the largest value, Kahan-summed squares.
inline double js_hypot(double a, double b) {
	a = std::fabs(a);
	b = std::fabs(b);
	if (std::isinf(a) || std::isinf(b)) return INFINITY;
	if (std::isnan(a) || std::isnan(b)) return NAN;
	double mx = std::max(a, b);
	if (mx == 0) return 0;
	double sum = 0, comp = 0;
	for (double v : {a, b}) {
		double n = v / mx;
		double summand = n * n - comp;
		double prelim = sum + summand;
		comp = (prelim - sum) - summand;
		sum = prelim;
	}
	return std::sqrt(sum) * mx;
}

inline double js_hypot3(double a, double b, double c) {
	a = std::fabs(a);
	b = std::fabs(b);
	c = std::fabs(c);
	double mx = std::max(a, std::max(b, c));
	if (mx == 0) return 0;
	double sum = 0, comp = 0;
	for (double v : {a, b, c}) {
		double n = v / mx;
		double summand = n * n - comp;
		double prelim = sum + summand;
		comp = (prelim - sum) - summand;
		sum = prelim;
	}
	return std::sqrt(sum) * mx;
}

// clamp from 03-core.js: v<a?a:v>b?b:v (NaN passes through, like the original)
inline double clampd(double v, double a, double b) { return v < a ? a : (v > b ? b : v); }
inline int clampi(int v, int a, int b) { return std::max(a, std::min(b, v)); }

// sstep(a,b,x) from 03-core.js: smoothstep
inline double sstep(double a, double b, double x) {
	double t = clampd((x - a) / (b - a), 0.0, 1.0);
	return t * t * (3 - 2 * t);
}

} // namespace tr
