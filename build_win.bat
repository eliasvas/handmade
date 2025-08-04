@echo off
mkdir build 2> NUL
pushd code
call odin.exe build .  -debug -out:../build/handmade.exe
popd
xcopy /f /y "SDL3.dll" "build//SDL3.dll"
echo Successfuly built handmade