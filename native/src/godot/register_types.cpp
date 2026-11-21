// Registers the TriRoute native classes with Godot.
#include "tr_math.h"
#include "tr_worldgen.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static void initialize_triroute(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
	GDREGISTER_CLASS(TRWorldGen);
	GDREGISTER_CLASS(TRMath);
}

static void uninitialize_triroute(ModuleInitializationLevel level) {}

extern "C" {
GDExtensionBool GDE_EXPORT triroute_library_init(GDExtensionInterfaceGetProcAddress get_proc_address, const GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization) {
	GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
	init.register_initializer(initialize_triroute);
	init.register_terminator(uninitialize_triroute);
	init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init.init();
}
}
