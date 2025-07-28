{
  description = "ZigKit lib";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls";

    # Used for shell.nix
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }@inputs:
    let
      overlays = [
        # Other overlays
        (final: prev: {
          zigpkgs = inputs.zig.packages.${prev.system};
          zlspkgs = inputs.zls.packages.${prev.system};
        })
      ];

      # Our supported systems are the same supported systems as the Zig binaries
      systems = builtins.attrNames inputs.zig.packages;
    in
    flake-utils.lib.eachSystem systems (
      system:
      let
        pkgs = import nixpkgs { inherit overlays system; };
      in
      rec {
        commonInputs = with pkgs; [ zigpkgs.master ] ++ darwinInputs;

        darwinInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin (
          with pkgs;
          [
            darwin.apple_sdk.frameworks.Security
            darwin.apple_sdk.frameworks.Foundation
          ]
        );

        sysroot = pkgs.lib.optionalString pkgs.stdenv.isDarwin "--sysroot $SDKROOT";

        packages.default = packages.zigkit;
        packages.zigkit = pkgs.stdenv.mkDerivation {
          name = "ZigKit";
          version = "master";
          src = ./.;
          nativeBuildInputs = commonInputs;
          dontConfigure = true;
          dontInstall = true;
          doCheck = false;
          buildPhase = ''
            mkdir -p .cache
            zig build install ${sysroot} -Doptimize=ReleaseSafe --prefix $out --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache 
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = commonInputs ++ (with pkgs; [ zlspkgs.default ]);
        };

        # For compatibility with older versions of the `nix` binary
        devShell = self.devShells.${system}.default;
      }
    );
}
