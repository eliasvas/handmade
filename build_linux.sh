mkdir -p build
pushd code
odin build . -debug -out:../build/sdl3_handmade
popd
echo Successfuly built handmade
