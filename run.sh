# compile
cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug

# build
cmake --build build

# run
./build/cpu
