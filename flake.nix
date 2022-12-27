{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;
    flake-compat = {
      url = github:edolstra/flake-compat;
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
      nix-monitored = { stdenv, lib, nix, nix-output-monitor }: stdenv.mkDerivation {
        pname = "nix-monitored";
        version = nix.version;
        src = ./.;

        inherit (nix) outputs;

        CXXFLAGS = [ "-O2" "-DNDEBUG" ];
        makeFlags = [
          "BIN=nix"
          "BINDIR=$(out)/bin"
          "NIXPATH=${lib.makeBinPath [ nix nix-output-monitor ]}"
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
    in
    {
      packages = {
        default = self.packages.${system}.nix-monitored;
        nix-monitored = pkgs.callPackage nix-monitored { };
      };

      devShells.default = pkgs.mkShell {
        name = "nix-monitored";
        inputsFrom = [ self.packages.${system}.default ];
        nativeBuildInputs = with pkgs; [
          clang-tools
        ];
      };
    });
}
