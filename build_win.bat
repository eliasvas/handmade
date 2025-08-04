@echo off
mkdir build 2> NUL
pushd code
call odin.exe build .  -debug -out:../build/sdl3_handmade.exe
popd
xcopy /F /y "SDL3.dll" "build//SDL3.dll"
echo Successfuly built handmade