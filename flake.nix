{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";
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

  outputs = inputs: inputs.flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import inputs.nixpkgs { inherit system; };
      nix-monitored =
        { stdenv
        , lib
        , nix
        , nix-output-monitor
        , withNotify ? stdenv.isLinux
        , libnotify
        , nixos-icons
        , ...
        }: stdenv.mkDerivation {
          pname = "nix-monitored";

          src = inputs.nix-filter.lib {
            root = ./.;
            include = [ "monitored.cc" "Makefile" ];
          };

          inherit (nix) version outputs;

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
      module = { config, pkgs, lib, ... }:
        let
          cfg = config.nix.monitored;
          package = cfg.package.override { withNotify = cfg.notify; };
        in
        {
          meta.maintainers = [ lib.maintainers.ners ];

          options.nix.monitored = with lib; {
            enable = mkEnableOption (mdDoc "nix-monitored, an improved output formatter for Nix");
            notify = mkEnableOption (mdDoc "notifications using libnotify") // {
              default = pkgs.stdenv.isLinux;
              defaultText = "pkgs.stdenv.isLinux";
            };
            package = mkPackageOption pkgs "nix-monitored" { };
          };

          config = lib.mkMerge [
            {
              nixpkgs.overlays = [
                (self: super: { nix-monitored = self.callPackage nix-monitored; })
              ];
            }
            (lib.optionalAttrs (cfg.enable) {
              nix.package = package;
              nixpkgs.overlays = [
                (self: super: {
                  nixos-rebuild = super.nixos-rebuild.override {
                    nix = package;
                  };
                  nix-direnv = super.nix-direnv.override {
                    nix = package;
                  };
                })
              ];
            })
          ];
        };
    in
    rec {
      packages = {
        nix-monitored = pkgs.callPackage nix-monitored { };
        default = packages.nix-monitored;
      };

      nixosModule = module;
      darwinModule = module;

      devShells.default = (pkgs.mkShell.override { stdenv = pkgs.llvmPackages.stdenv; }) {
        name = "nix-monitored";
        inputsFrom = [ packages.nix-monitored ];
        nativeBuildInputs = with pkgs; [
          clang-tools
          nixpkgs-fmt
        ];
        inherit (checks.pre-commit) shellHook;
      };

      checks.pre-commit = inputs.pre-commit-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          nixpkgs-fmt.enable = true;
          clang-format.enable = true;
        };
      };

      formatter = pkgs.nixpkgs-fmt;
    }
  );
}
