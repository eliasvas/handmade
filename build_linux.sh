mkdir -p build
pushd code/game
odin build . -build-mode:dll -debug -out:../../build/game.dll
popd
pushd code/platform
odin build . -build-mode:exe -debug -out:../../build/sdl3_handmade
popd
echo Successfuly built handmade
