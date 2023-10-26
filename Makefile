web_target: | $(EMSDK)/upstream/emscripten
	zig build run -Dtarget=wasm32-emscripten --sysroot "$|"

clean:
	rm -rf zig-cache zig-out
