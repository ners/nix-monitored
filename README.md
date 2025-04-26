# nix-monitored

Pipe Nix through Nix Output Monitor without hassle.

![](https://github.com/maralorn/nix-output-monitor/raw/main/example-screenshot.png)

## Motivation

Everyone I know wants to have nom's pretty output, but no one I know remembers to put `|& nom` after every command.
Further, nix-monitored can integrate with direnv and nixos-rebuild, which is difficult to do without overriding the Nix package.

### Shouldn't this be a shell script / `wrapProgram` / etc.?

The reasons it is C++ rather than a shell wrapper are:
 - It runs on every Nix invocation, so overhead should be minimal.
 - Building C++ is trivial with `stdenv`.
 - Nix itself is written in C++, so it should be easier to maintain.
 - Bash is notoriously terrible with string / parameter manipulation. The first version of this wrapper was Bash, and I kept running into weird string splitting errors, despite using `"$@"`.

### Shouldn't this be upstreamed into Nix?

I don't think so.

The Nix project has a stated mission of having low a runtime and dependencies. That's why it was authored in C++ and not something more respectable like Haskell. This design goal makes Nix attractive in a wide range of applications, e.g. on embedded devices with limited resources.

Nix Output Monitor does not share this design goal, and is therefore more resource heavy. In fact introducing any kind of fanciness in the Nix CLI, even with C++ or Rust, would likely increase Nix' runtime and dependency footprint.

With a wrapper like this, we can have our cake and eat it too: Nix stays appreciably small, but we can still use Nix Output Monitor on developer workstations if we wish. It's a win-win.

## Usage

On NixOS and nix-darwin, simply replace your `nix.package`, like so:
```nix
nix.package = pkgs.nix-monitored;
```
And then import and enable it like this:
```nix
{
  imports = [
    inputs.nix-monitored.nixosModules.default
  ];

  nix.monitored.enable = true;
}
```

You can also import it in the overlay below by putting this line inside alongside the rest:
```
nix-monitored = inputs.nix-monitored.packages.${self.system}.default.override self;
```

To make it work with `nix-direnv` and `nixos-rebuild`, we can override those packages:
```nix
nixpkgs.overlays = [
  (self: super: {
    nixos-rebuild = super.nixos-rebuild.override {
      nix = super.nix-monitored;
    };
    nix-direnv = super.nix-direnv.override {
      nix = super.nix-monitored;
    };
    # Line above here if you want it.
  })
];
```

If you're feeling adventurous, you can also simply try to override the Nix package entirely:
```nix
nixpkgs.overlays = [
  (self: super: {
    nix = super.nix-monitored.override {
	  inherit (super) nix;
    };
  })
];
```

A PR is in the works to bring this to NixOS as a module: [NixOS/nixpkgs#207108](https://github.com/NixOS/nixpkgs/pull/207108).

## Does it work?

The wrapper should work at least with the following tools:
 - nix commands on the CLI, with and without flakes
 - nix-direnv
 - nixos-rebuild

It's been tested on both NixOS and macOS.
