#include "tr_math.h"
#include "core/crmath.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void TRMath::_bind_methods() {
	ClassDB::bind_static_method("TRMath", D_METHOD("exp", "x"), &TRMath::exp);
	ClassDB::bind_static_method("TRMath", D_METHOD("log", "x"), &TRMath::log);
	ClassDB::bind_static_method("TRMath", D_METHOD("log10", "x"), &TRMath::log10);
	ClassDB::bind_static_method("TRMath", D_METHOD("log2", "x"), &TRMath::log2);
	ClassDB::bind_static_method("TRMath", D_METHOD("pow", "x", "y"), &TRMath::pow);
}

double TRMath::exp(double x) { return tr::cr::exp(x); }
double TRMath::log(double x) { return tr::cr::log(x); }
double TRMath::log10(double x) { return tr::cr::log10(x); }
double TRMath::log2(double x) { return tr::cr::log2(x); }
double TRMath::pow(double x, double y) { return tr::cr::pow(x, y); }

} // namespace godot
