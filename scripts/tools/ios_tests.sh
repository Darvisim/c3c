#!/usr/bin/env bash

SHOW_SUCCESS_LOGS="${SHOW_SUCCESS_LOGS:-true}"

if [ $# -lt 1 ]; then
    echo "Usage: ./ios_tests.sh <path_to_c3c_binary> [target_override]"
    exit 1
fi

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REAL_ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
C3C_BIN="$(realpath "$1")"
ROOT_DIR="$REAL_ROOT_DIR"
TARGET_FLAG="$2"

echo ">>> Running iOS Target CI Tests using C3C at: $C3C_BIN"
echo ">>> Initializing iOS Simulator Target Lifecycle..."

if [ -n "$TARGET_DEVICE" ]; then
    TARGET_DEVICE_ID="$TARGET_DEVICE"
else
    TARGET_DEVICE_ID=$(xcrun simctl list devices | grep -E "Booted" | head -n 1 | sed -E 's/.* \(([-0-9A-Fa-f]+)\).*/\1/')
fi

if [ -z "$TARGET_DEVICE_ID" ]; then
    echo ">>> No active booted device found. Discovering available templates..."
    TARGET_DEVICE_ID=$(xcrun simctl list devices available | grep -E "iPhone" | head -n 1 | sed -E 's/.* \(([-0-9A-Fa-f]+)\).*/\1/')
    
    if [ -z "$TARGET_DEVICE_ID" ]; then
        echo "::error::No operational iOS Simulator configuration available on this host."
        exit 1
    fi
    
    echo ">>> Powering up Simulator Runtime Instance [ID: ${TARGET_DEVICE_ID}]..."
    xcrun simctl boot "${TARGET_DEVICE_ID}" || true
    xcrun simctl bootstatus "${TARGET_DEVICE_ID}" > /dev/null 2>&1 || sleep 5
fi

echo ">>> Active iOS Simulator Environment Confirmed: [${TARGET_DEVICE_ID}]"

WORK_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3_ios_ci_tests')
echo ">>> Setting up workspace in: $WORK_DIR"

cleanup() {
    echo ">>> Cleaning up..."
    cd "$REAL_ROOT_DIR" || cd ..
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

run_c3c() {
    "$C3C_BIN" --target "$TARGET_FLAG" --output-dir "$MY_WORK_DIR" --build-dir "$MY_WORK_DIR" --obj-out "$MY_WORK_DIR" "$@"
}

run_c3c_sim_exec() {
    local source_file="$1"
    shift
    local source_name=$(basename "$source_file")
    local target_name="${source_name%.*}"
    local target_path="$MY_WORK_DIR/$target_name"
    
    run_c3c compile "$source_file" "$@" -o "$source_name"
    xcrun simctl spawn "$TARGET_DEVICE_ID" "$target_path"
    rm -f "$target_path"
}

run_examples() {
    local MY_WORK_DIR="$WORK_DIR/examples"
    mkdir -p "$MY_WORK_DIR"

    echo "--- Running iOS Standard Examples Matrix ---"
    cd "$ROOT_DIR/resources"
    
    run_c3c compile examples/base64.c3
    run_c3c compile examples/binarydigits.c3
    run_c3c compile examples/brainfk.c3
    run_c3c compile examples/factorial_macro.c3
    run_c3c compile examples/fasta.c3
    run_c3c compile examples/gameoflife.c3
    run_c3c compile examples/hash.c3
    run_c3c compile-only examples/levenshtein.c3
    run_c3c compile examples/load_world.c3
    run_c3c compile-only examples/map.c3
    run_c3c compile examples/mandelbrot.c3
    run_c3c compile examples/plus_minus.c3
    run_c3c compile examples/nbodies.c3
    run_c3c compile examples/spectralnorm.c3
    run_c3c compile examples/swap.c3
    run_c3c compile examples/contextfree/boolerr.c3
    run_c3c compile examples/contextfree/dynscope.c3
    run_c3c compile examples/contextfree/guess_number.c3
    run_c3c compile examples/contextfree/multi.c3
    run_c3c compile examples/contextfree/cleanup.c3
    
    run_c3c_sim_exec examples/hello_world_many.c3
    run_c3c_sim_exec examples/time.c3
    run_c3c_sim_exec examples/fannkuch-redux.c3
    run_c3c_sim_exec examples/contextfree/boolerr.c3

    run_c3c compile --no-entry --test -g --threads 1 --target macos-x64 examples/constants.c3
}

run_dynlib_tests() {
    local MY_WORK_DIR="$WORK_DIR/dynlib"
    mkdir -p "$MY_WORK_DIR"

    echo "--- Running iOS Dynamic Lib Tests ---"
    cd "$MY_WORK_DIR"
    
    run_c3c -vv dynamic-lib "$ROOT_DIR/resources/examples/dynlib-test/add.c3" -o add
    run_c3c_sim_exec "$ROOT_DIR/resources/examples/dynlib-test/test.c3" -l "add.dylib"
}

run_staticlib_tests() {
    local MY_WORK_DIR="$WORK_DIR/staticlib"
    mkdir -p "$MY_WORK_DIR"

    echo "--- Running iOS Static Lib Tests ---"
    cd "$MY_WORK_DIR"
    
    run_c3c -vv static-lib "$ROOT_DIR/resources/examples/staticlib-test/add.c3" -o libadd
    run_c3c_sim_exec "$ROOT_DIR/resources/examples/staticlib-test/test.c3" -L . -l add
}

run_testproject() {
    local MY_WORK_DIR="$WORK_DIR/testproject"
    mkdir -p "$MY_WORK_DIR"

    echo "--- Running Test Project for iOS Targets ---"
    cd "$ROOT_DIR/resources/testproject"
    
    run_c3c build -vv --trust=full --linker=builtin
    run_c3c clean
}

run_wasm_compile() {
    local MY_WORK_DIR="$WORK_DIR/wasm"
    mkdir -p "$MY_WORK_DIR"

    echo "--- Running WASM Compile Check ---"
    cd "$ROOT_DIR/resources/testfragments"
    run_c3c compile --target wasm32 -g0 --no-entry -Os wasm4.c3
}

run_cli_tests() {
    local MY_WORK_DIR="$WORK_DIR/cli"
    mkdir -p "$MY_WORK_DIR"

    echo "--- Running CLI tests (init) ---"
    (
        cd "$MY_WORK_DIR"
        run_c3c init-lib mylib
        run_c3c init myproject
        (cd myproject && run_c3c benchmark myproject --suppress-run)
        rm -rf mylib.c3l myproject
    )
}

run_http_server_tests() {
    local MY_WORK_DIR="$WORK_DIR/http"
    mkdir -p "$MY_WORK_DIR"

    echo "--- Running HTTP Server Integration Tests inside iOS Simulator ---"

    cd "$ROOT_DIR/resources/examples"
    run_c3c compile -O1 http_server.c3 -o http_server

    OUTPUT_BIN="$MY_WORK_DIR/http_server"

    PORT=$(( 8085 + $RANDOM % 10000 ))
    echo "Starting server inside simulator on port $PORT..."
    
    xcrun simctl spawn "$TARGET_DEVICE_ID" "$OUTPUT_BIN" -p $PORT -r "$ROOT_DIR/resources/examples" &
    SERVER_PID=$!

    sleep 2

    echo "Testing GET / from Host to Simulator"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/")
    if [ "$HTTP_STATUS" != "200" ]; then
        echo "::error::HTTP GET / failed with status $HTTP_STATUS."
        kill $SERVER_PID 2>/dev/null || true
        exit 1
    fi

    echo "Testing GET /http_server.c3"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/http_server.c3")
    if [ "$HTTP_STATUS" != "200" ]; then
        echo "::error::HTTP GET /http_server.c3 failed with status $HTTP_STATUS."
        kill $SERVER_PID 2>/dev/null || true
        exit 1
    fi

    echo "Testing 404 for invalid path"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/does_not_exist_404_test")
    if [ "$HTTP_STATUS" != "404" ]; then
        echo "::error::HTTP GET /does_not_exist_404_test expected 404, but got $HTTP_STATUS."
        kill $SERVER_PID 2>/dev/null || true
        exit 1
    fi

    echo "HTTP Server Integration Tests passed."
    kill $SERVER_PID 2>/dev/null || true
}

run_unit_tests() {
    local MY_WORK_DIR="$WORK_DIR/unit"
    mkdir -p "$MY_WORK_DIR"

    echo "--- Running iOS Unit Test Suites ---"
    cd "$ROOT_DIR/test"

    run_c3c compile-test unit -O1 --suppress-run -o "unit_test"
    xcrun simctl spawn "$TARGET_DEVICE_ID" "$MY_WORK_DIR/unit_test"

    echo "--- Running Test Suite Runner inside iOS Simulator Container ---"
    cd "$MY_WORK_DIR"
    
    run_c3c compile "$ROOT_DIR/test/src/test_suite_runner.c3" -o suite_runner
    xcrun simctl spawn "$TARGET_DEVICE_ID" "$MY_WORK_DIR/suite_runner" "$C3C_BIN" "$ROOT_DIR/test/test_suite/" --no-terminal
}

PIDS=()
run_parallel() {
    local name=$1
    local func=$2
    local MY_WORK_DIR="$WORK_DIR/$name"
    local log="$WORK_DIR/$name.log"
    (
        set +e
        ( set -e; $func ) > "$log" 2>&1
        local status=$?

        if [ $status -eq 0 ]; then
            echo "SUCCESS: $name"
            if [ "$SHOW_SUCCESS_LOGS" = "true" ]; then
                echo "--------------------------------------------------------------------------------"
                cat "$log"
                echo "--------------------------------------------------------------------------------"
            fi
        else
            echo "FAILED: $name (see log below)"
            echo "--------------------------------------------------------------------------------"
            cat "$log"
            echo "--------------------------------------------------------------------------------"
            echo "Directory listing for $MY_WORK_DIR:"
            ls -R "$MY_WORK_DIR" || true
            echo "--------------------------------------------------------------------------------"
            exit 1
        fi
    ) &
    PIDS+=($!)
}

run_parallel examples run_examples
run_parallel cli run_cli_tests
run_parallel dynlib run_dynlib_tests
run_parallel staticlib run_staticlib_tests
run_parallel testproject run_testproject
run_parallel wasm run_wasm_compile
run_parallel http run_http_server_tests

exit_code=0
for p in "${PIDS[@]}"; do
    wait "$p" || exit_code=1
done

if [ $exit_code -ne 0 ]; then
    echo "::error::One or more parallel iOS simulator test suites failed."
    exit 1
fi

run_unit_tests

echo ">>> All iOS Simulator CI Tests Passed Successfully!"
