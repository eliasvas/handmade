@echo off
mkdir build 2> NUL
pushd code\game
call odin.exe build . -build-mode:dll -debug -out:../../build/game.dll
popd
pushd code\platform
call odin.exe build . -build-mode:exe -debug -out:../../build/sdl3_handmade.exe
popd
xcopy /F /y "SDL3.dll" "build//SDL3.dll"
echo Successfuly built handmade
