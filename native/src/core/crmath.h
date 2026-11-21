// Correctly rounded exp, log, log10, log2 and pow.
// The HTML version runs in Chromium, whose Math.exp/log/pow return the correctly rounded result
// (the nearest double to the exact value) — except Math.pow, which is within ~0.5 ulp; the reference runs
// replace it with legacy/tests/crmath.js, the same algorithm in JS. The C runtime is not correctly rounded (glibc differs
// from it in ~0.1% of cases, other platforms more), and the game feeds these values into ratings and
// money that accumulate, so the ported logic uses these instead.
// Method: evaluate in double-double arithmetic (~105 bits) and round once to double. A misrounding
// would need the exact value within ~1e-30 (relative) of a halfway point between two doubles.
// Requires IEEE double arithmetic without contraction into FMA (SConstruct sets -ffp-contract=off).
#pragma once
#include <cmath>
#include <limits>

namespace tr {
namespace cr {

struct dd {
	double hi, lo;
};

inline dd quick_two_sum(double a, double b) {
	double s = a + b;
	return {s, b - (s - a)};
}
inline dd two_sum(double a, double b) {
	double s = a + b, bb = s - a;
	return {s, (a - (s - bb)) + (b - bb)};
}
// exact product by Dekker's splitting (no FMA: some C runtimes have a broken software fma)
inline dd two_prod(double a, double b) {
	const double SPLIT = 134217729.0; // 2^27 + 1
	double p = a * b;
	double t = SPLIT * a, ah = t - (t - a), al = a - ah;
	t = SPLIT * b;
	double bh = t - (t - b), bl = b - bh;
	return {p, ((ah * bh - p) + ah * bl + al * bh) + al * bl};
}
inline dd add(dd a, dd b) {
	dd s = two_sum(a.hi, b.hi), t = two_sum(a.lo, b.lo);
	s.lo += t.hi;
	s = quick_two_sum(s.hi, s.lo);
	s.lo += t.lo;
	return quick_two_sum(s.hi, s.lo);
}
inline dd neg(dd a) { return {-a.hi, -a.lo}; }
inline dd sub(dd a, dd b) { return add(a, neg(b)); }
inline dd mul(dd a, dd b) {
	dd p = two_prod(a.hi, b.hi);
	p.lo += a.hi * b.lo + a.lo * b.hi;
	return quick_two_sum(p.hi, p.lo);
}
inline dd mul_d(dd a, double b) {
	dd p = two_prod(a.hi, b);
	p.lo += a.lo * b;
	return quick_two_sum(p.hi, p.lo);
}
inline dd div(dd a, dd b) {
	double q1 = a.hi / b.hi;
	dd r = sub(a, mul_d(b, q1));
	double q2 = r.hi / b.hi;
	r = sub(r, mul_d(b, q2));
	double q3 = r.hi / b.hi;
	return add(quick_two_sum(q1, q2), dd{q3, 0});
}

const dd LN2 = {0.6931471805599453, 2.3190468138462996e-17};
const dd LN10 = {2.302585092994046, -2.1707562233822494e-16};

// e^a for |a| < ~709
inline dd exp_dd(dd a) {
	double k = std::nearbyint(a.hi / LN2.hi);
	dd r = sub(a, mul_d(LN2, k));
	r = {std::ldexp(r.hi, -10), std::ldexp(r.lo, -10)};
	// expm1(r) by Taylor series, |r| < 3.4e-4
	dd s = r, term = r;
	for (int i = 2; i <= 12; i++) {
		term = div(mul(term, r), dd{double(i), 0});
		s = add(s, term);
		if (std::fabs(term.hi) < 1e-36) break;
	}
	// (1+s)^(2^10): s <- 2s + s^2
	for (int i = 0; i < 10; i++) s = add(mul_d(s, 2.0), mul(s, s));
	dd e = add(dd{1.0, 0}, s);
	int ki = int(k);
	return {std::ldexp(e.hi, ki), std::ldexp(e.lo, ki)};
}

// ln x for finite x > 0: one Newton step on exp from the libm estimate
inline dd log_dd(double x) {
	double y0 = std::log(x);
	dd t = mul_d(exp_dd(dd{-y0, 0}), x); // x * e^-y0 = 1 + d
	return add(dd{y0, 0}, sub(t, dd{1.0, 0}));
}

inline bool plain(double x) { return std::isfinite(x) && x > 0 && x >= std::numeric_limits<double>::min(); }

inline double exp(double x) {
	if (!std::isfinite(x) || x > 709.0 || x < -708.0 || x == 0) return std::exp(x);
	return exp_dd(dd{x, 0}).hi;
}
inline double log(double x) {
	if (!plain(x) || x == 1.0) return std::log(x);
	dd r = log_dd(x);
	return r.hi + r.lo;
}
inline double log10(double x) {
	if (!plain(x) || x == 1.0) return std::log10(x);
	// exact powers of ten
	double e = std::nearbyint(std::log10(x));
	if (e >= 0 && e <= 22 && std::pow(10.0, e) == x) return e;
	dd r = div(log_dd(x), LN10);
	return r.hi + r.lo;
}
inline double log2(double x) {
	if (!plain(x) || x == 1.0) return std::log2(x);
	int ex;
	double m = std::frexp(x, &ex);
	if (m == 0.5) return double(ex - 1);
	dd r = div(log_dd(x), LN2);
	return r.hi + r.lo;
}
inline double pow(double x, double y) {
	if (y == 0) return 1.0;
	if (std::isnan(x) || std::isnan(y)) return std::numeric_limits<double>::quiet_NaN();
	if (y == 1) return x;
	if (y == 2) return x * x;
	if (y == 0.5 && x >= 0 && std::isfinite(x)) return std::sqrt(x);
	if (y == -1) return 1.0 / x;
	if (!plain(x) || !std::isfinite(y) || x == 1.0) return std::pow(x, y);
	dd t = log_dd(x);
	t = mul_d(t, y);
	if (t.hi > 709.0 || t.hi < -708.0) return std::pow(x, y);
	return exp_dd(t).hi;
}

} // namespace cr
} // namespace tr
