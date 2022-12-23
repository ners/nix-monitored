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
  src = ./.;
  makeFlags = [ "BIN=nix" "BINDIR=$(out)/bin" "NIXPATH=${lib.makeBinPath [ nix nix-output-monitor ]}" ];
  postInstall = ''
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

  meta = with lib; {
    description = "A drop-in replacement for Nix that pipes its output through Nix Output Monitor";
    homepage = "https://github.com/ners/nix-monitored";
    license = licenses.mit;
    mainProgram = "nix";
    maintainers = with maintainers; [ ners ];
    platforms = platforms.unix;
    inherit (nix.meta) outputsToInstall;
  };
}

