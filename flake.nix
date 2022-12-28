{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-compat.follows = "flake-compat";
    };
  };

  outputs = { self, nixpkgs, flake-utils, pre-commit-hooks, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        nix-monitored =
          { stdenv
          , lib
          , nix
          , nix-output-monitor
          , withNotify ? stdenv.isLinux
          , libnotify
          , nixos-icons
          }: stdenv.mkDerivation {
            pname = "nix-monitored";
            src = ./.;

            inherit (nix) outputs version;

            CXXFLAGS = [
              "-O2"
              "-DNDEBUG"
            ] ++ lib.optionals withNotify [
              "-DNOTIFY"
            ];
            makeFlags = [
              "BIN=nix"
              "BINDIR=$(out)/bin"
              "NIXPATH=${lib.makeBinPath [ nix nix-output-monitor ]}"
            ] ++ lib.optionals withNotify [
              "NOTIFY_ICON=${nixos-icons}/share/icons/hicolor/32x32/apps/nix-snowflake.png"
            ];

            postInstall = ''
              ln -s $out/bin/nix $out/bin/nix-build
              ln -s $out/bin/nix $out/bin/nix-shell
              ls ${nix} | while read d; do
                [ -e "$out/$d" ] || ln -s ${nix}/$d $out/$d
              done
              ls ${nix}/bin | while read b; do
                [ -e $out/bin/$b ] || ln -s ${nix}/bin/$b $out/bin/$b
              done
            '' + lib.pipe nix.outputs [
              (builtins.map (o: ''
                [ -e "''$${o}" ] || ln -s ${nix.${o}} ''$${o}
              ''))
              (builtins.concatStringsSep "\n")
            ];

            # Nix will try to fixup the propagated outputs (e.g. nix-dev), to which it has
            # no write permission when building this derivation.
            # We don't actually need any fixup, as the derivation we are building is a native Nix build,
            # and all the propagated outputs have already been fixed up for the Nix derivation.
            dontFixup = true;
          };
        lib = pkgs.lib;
      in
      {
        packages = {
          default = self.packages.${system}.nix-monitored;
          nix-monitored = pkgs.callPackage nix-monitored { };
        };

        devShells.default = (pkgs.mkShell.override { stdenv = pkgs.llvmPackages.stdenv; }) {
          name = "nix-monitored";
          inputsFrom = [ self.packages.${system}.default ];
          nativeBuildInputs = with pkgs; [
            clang-tools
          ];
          inherit (self.checks.${system}.pre-commit) shellHook;
        };

        checks.pre-commit = pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nixpkgs-fmt.enable = true;
            clang-format.enable = true;
          };
        };
      });
}
