# Native module (GDExtension, C++)

Heavy parts of the game in C++: world generation now; roads, route search later.
`src/core/` is plain C++ (no Godot), `src/godot/` binds it to Godot. Built libraries go to `godot/bin/`
and are committed, so the game opens in Godot without compiling anything.

## Build (Linux host)

```bash
git submodule update --init native/godot-cpp     # godot-cpp 4.4-stable
pip install scons
sudo apt-get install mingw-w64                   # for the Windows build
cd native
scons platform=linux target=template_debug
scons platform=windows use_mingw=yes target=template_debug
```

## Test against the HTML version

```bash
bash legacy/build.sh
node legacy/tests/worldref.js 777                # reference arrays -> legacy/tests/ref/777
g++ -O2 -std=c++17 -I native/src native/tests/worldgen_test.cpp native/src/core/worldgen.cpp -o wgtest
./wgtest legacy/tests/ref/777 777                # every array must be identical
```

In Godot: `godot --headless --path godot -s res://tests/run_tests.gd` (test_worldgen checks MD5 fingerprints).
