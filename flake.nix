{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;
  };

  outputs = inputs: inputs.flake-utils.lib.eachDefaultSystem (system:
    let pkgs = inputs.nixpkgs.legacyPackages.${system}; in
    {
      packages.default = pkgs.callPackage ./. { };
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [ clang-tools ];
      };
    }
  );
}
