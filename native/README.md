# Native module (GDExtension, C++)

Heavy parts of the game in C++: world generation (relief, states, towns, roads, railways, ports, checkpoints); route search later.
Built with godot-cpp 4.4-stable, runs in Godot 4.4 and newer (the project targets 4.7).
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

## History: how the port was checked against the HTML version

No longer used: the Godot version is the reference now (`godot/tests/record_refs.gd` records it).

```bash
bash legacy/build.sh
node legacy/tests/worldref.js 777                # reference arrays -> legacy/tests/ref/777
g++ -O2 -std=c++17 -I native/src native/tests/worldgen_test.cpp native/src/core/worldgen.cpp -o wgtest
./wgtest legacy/tests/ref/777 777                # every array must be identical
node legacy/tests/boardref.js 777                # towns, roads, railways... -> legacy/tests/ref/777/board.json
g++ -O2 -std=c++17 -I native/src native/tests/board_dump.cpp native/src/core/*.cpp -o board_dump
python3 -c "import json;print('\n'.join('%.17g'%s['pop'] for s in json.load(open('legacy/tests/ref/777/board.json'))['states']))" > pops.txt
./board_dump 777 pops.txt board.json && python3 native/tests/board_compare.py legacy/tests/ref/777 board.json
```

In Godot: `godot --headless --path godot -s res://tests/run_tests.gd` (test_worldgen compares the generator with its recorded fingerprints; record them again after a deliberate change with `godot --headless --path godot -s res://tests/record_refs.gd`).
