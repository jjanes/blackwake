{
  description = "Zig Raylib App";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
  let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
  in {
    devShells.x86_64-linux.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        zig
        raylib
        pkg-config
        vulkan-loader # Provides libvulkan.so
        glfw          # Provides libglfw.so
        libGL         # For OpenGL dependencies
        xorg.libXrandr
        xorg.libXinerama
        xorg.libXcursor
        xorg.libXi    # Additional X11 libraries Raylib may need
        ffmpeg 
        v4l-utils 
        libv4l
      ];
      shellHook = ''
        export LD_LIBRARY_PATH=${pkgs.raylib}/lib:$LD_LIBRARY_PATH
      '';
    };
  };
}
