{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = inputs:
    let
      lib = inputs.nixpkgs.lib;
      foreach = xs: f: with lib; foldr recursiveUpdate { } (
        if isList xs then map f xs
        else if isAttrs xs then mapAttrsToList f xs
        else throw "foreach: expected list or attrset but got ${typeOf xs}"
      );
      nix-monitored =
        { gccStdenv
        , lib
        , cmake
        , nix
        , nix-output-monitor
        , withNotify ? gccStdenv.isLinux
        , libnotify
        , pkg-config
        , glib
        , gdk-pixbuf
        , nixos-icons
        , ...
        }: gccStdenv.mkDerivation {
          pname = "nix-monitored";

          src = with lib.fileset; toSource {
            root = ./.;
            fileset = unions [
              ./monitored.cc
              ./CMakeLists.txt
            ];
          };

          inherit (nix) version outputs;

          nativeBuildInputs = [
            cmake
            pkg-config
          ];

          buildInputs = [
            libnotify
            glib
            gdk-pixbuf
          ];

          cmakeFlags = [
            "-DCMAKE_INSTALL_PREFIX=${placeholder "out"}"
            "-DPATH=${lib.makeBinPath [ nix nix-output-monitor ]}"
          ] ++ lib.optionals withNotify [
            "-DNOTIFY=1"
            "-DNOTIFY_ICON=${nixos-icons}/share/icons/hicolor/32x32/apps/nix-snowflake.png"
          ];

          VERBOSE = "1";

          postInstall = ''
            ln -s nix-monitored $out/bin/nix
            ln -s nix-monitored $out/bin/nix-build
            ln -s nix-monitored $out/bin/nix-shell
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
      overlay = final: prev: {
        nix-monitored = final.callPackage nix-monitored { };
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
    foreach inputs.nixpkgs.legacyPackages
      (system: pkgs: {
        packages.${system}.default = (pkgs.extend overlay).nix-monitored;

        checks.${system}.nixosTest = pkgs.nixosTest {
          name = "nix-monitored";
          nodes = {
            withNotify = { pkgs, ... }: {
              imports = [ module ];
              nix.monitored.enable = true;
              nix.monitored.notify = true;
              environment.systemPackages = with pkgs; [ expect ];
            };
            withoutNotify = { pkgs, ... }: {
              imports = [ inputs.self.nixosModules.default ];
              nix.monitored.enable = true;
              nix.monitored.notify = false;
              environment.systemPackages = with pkgs; [ expect ];
            };
          };
          testScript = let nix-monitored = attrs: inputs.self.packages.${system}.default.override attrs; in
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

        devShells.${system}.default = (pkgs.mkShell.override { stdenv = pkgs.gccStdenv; }) {
          name = "nix-monitored";
          inputsFrom = [ inputs.self.packages.${system}.default ];
          nativeBuildInputs = with pkgs; [
            clang-tools
            nixpkgs-fmt
          ];
        };

        formatter.${system} = pkgs.nixpkgs-fmt;
      })
    //
    {
      overlays.default = overlay;
      nixosModules.default = module;
      darwinModules.default = module;
    };
}
