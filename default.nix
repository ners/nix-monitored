{ lib
, stdenv
, nix
, nix-output-monitor
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "nix-monitored";
  version = nix.version + lib.optionalString (finalAttrs.src ? version) "-${finalAttrs.src.version}";
  inherit (nix) outputs;
  src = ./.;

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

  meta = with lib; {
    description = "A transparent wrapper around Nix that pipes its output through Nix Output Monitor";
    homepage = "https://github.com/ners/nix-monitored";
    license = licenses.mit;
    mainProgram = "nix";
    maintainers = with maintainers; [ ners ];
    platforms = platforms.unix;
    inherit (nix.meta) outputsToInstall;
  };
})
