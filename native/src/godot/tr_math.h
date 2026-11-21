// TRMath: correctly rounded exp/log/log10/log2/pow for the ported game logic (see core/crmath.h).
// GDScript's own exp/log/pow come from the C runtime and differ between platforms and from the HTML version.
#pragma once
#include <godot_cpp/classes/object.hpp>

namespace godot {

class TRMath : public Object {
	GDCLASS(TRMath, Object)

protected:
	static void _bind_methods();

public:
	static double exp(double x);
	static double log(double x);
	static double log10(double x);
	static double log2(double x);
	static double pow(double x, double y);
};

} // namespace godot
