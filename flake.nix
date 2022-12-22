{
  inputs = {
    nixpkgs.url = github:nixos/nixpkgs/nixpkgs-unstable;
    flake-utils.url = github:numtide/flake-utils;
  };

  outputs = inputs: inputs.flake-utils.lib.eachDefaultSystem (system:
    let pkgs = inputs.nixpkgs.legacyPackages.${system}; in
    {
      packages.default = pkgs.callPackage ./. { };
    }
  );
}
