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
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      nix-monitored =
        { gccStdenv
        , lib
        , nix
        , nix-output-monitor
        , withNotify ? gccStdenv.isLinux
        , libnotify
        , nixos-icons
        , ...
        }: gccStdenv.mkDerivation {
          pname = "nix-monitored";

          src = inputs.nix-filter.lib {
            root = ./.;
            include = [ "monitored.cc" "Makefile" ];
          };

          inherit (nix) version outputs;

          CXXFLAGS = [
            "-O2"
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

          meta.mainProgram = "nix";
        };
      module = { config, pkgs, lib, ... }:
        let
          cfg = config.nix.monitored;
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
            ({
              nixpkgs.overlays = [
                (self: super: { nix-monitored = self.callPackage nix-monitored { }; })
              ];
            })
            (lib.mkIf cfg.enable rec {
              nix.package = cfg.package.override { withNotify = cfg.notify; };
              nixpkgs.overlays = [
                (self: super: {
                  nixos-rebuild = super.nixos-rebuild.override {
                    nix = nix.package;
                  };
                  nix-direnv = super.nix-direnv.override {
                    nix = nix.package;
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

      nixosModules.default = module;
      darwinModules.default = module;

      checks.nixosTest = pkgs.nixosTest {
        name = "nix-monitored";
        nodes = {
          withNotify = { pkgs, ... }: {
            imports = [ module ];
            environment.systemPackages = with pkgs; [ expect ];
            nix.monitored.enable = true;
            nix.monitored.notify = true;
          };
          withoutNotify = { pkgs, ... }: {
            imports = [ nixosModules.default ];
            environment.systemPackages = with pkgs; [ expect ];
            nix.monitored.enable = true;
            nix.monitored.notify = false;
          };
        };
        testScript = let nix-monitored = attrs: packages.nix-monitored.override attrs; in
          ''
            start_all()

            machines = [withNotify, withoutNotify]
            packages = ["${nix-monitored { withNotify = true; }}", "${nix-monitored { withNotify = false; }}"]

            for (machine, package) in zip(machines, packages):
              for binary in ["nix", "nix-build", "nix-shell"]:
                actual = machine.succeed(f"readlink $(which {binary})")
                expected = f"{package}/bin/{binary}"
                assert expected == actual.strip(), f"{binary} binary is {actual}, expected {expected}"

              actual = machine.succeed("unbuffer nix --version")
              expected = "nix-output-monitor ${pkgs.nix-output-monitor.version}\nnix (Nix) ${pkgs.nix.version}"
              assert expected == actual.strip(), f"version string is {actual}, expected {expected}"
          '';
      };

      devShells.default = (pkgs.mkShell.override { stdenv = pkgs.gccStdenv; }) {
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
