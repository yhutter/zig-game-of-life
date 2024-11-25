# zig-game-of-life
Game of Life implementation using Zig and Sokol for education purpose

## Building the Application

### Build native Application
Just execute the following command
```bash
zig build -Doptimize=ReleaseFast
```

### Build for specific OS and CPU Architecture
In order to build for Windows execute the following command
```bash
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-windows
```


