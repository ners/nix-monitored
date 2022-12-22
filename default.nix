{ lib
, stdenv
, nix
, nix-output-monitor
}:

stdenv.mkDerivation {
  inherit (nix)
    outputs
    version
    ;
  pname = "nix-monitored";
  meta = nix.meta // { mainProgram = "nix"; };
  src = ./.;
  buildPhase = ''
    mkdir -p $out/bin
    ''${CXX} \
      ''${CXXFLAGS} \
      -std=c++17 \
      -O2 \
      -DPATH='"${nix}/bin:${nix-output-monitor}/bin"' \
      -o $out/bin/nix \
      $src/monitored.cc
  '';
  installPhase = ''
    ln -s $out/bin/nix $out/bin/nix-build
    ln -s $out/bin/nix $out/bin/nix-shell
    ls ${nix} | while read d; do
      [ -e "$out/$d" ] || ln -s ${nix}/$d $out/$d
    done
    ls ${nix}/bin | while read b; do
      [ -e $out/bin/$b ] || ln -s ${nix}/bin/$b $out/bin/$b
    done
    ${ lib.pipe nix.outputs
        [
          (builtins.map (o: ''
            [ -e "''$${o}" ] || ln -s ${nix.${o}} ''$${o}
          ''))
          (builtins.concatStringsSep "\n")
        ]
    }
  '';
  dontFixup = true;
}

