# compile
cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug

# build
cmake --build build

# run
./build/cpu


# run tests
ctest --test-dir build --output-on-failure
