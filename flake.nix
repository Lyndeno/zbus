{
  inputs = {
    utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    crane.url = "github:ipetkov/crane";

    pre-commit-hooks-nix = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    utils,
    crane,
    pre-commit-hooks-nix,
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  in
    utils.lib.eachSystem systems (system: let
      pkgs = nixpkgs.legacyPackages."${system}";
      craneLib = crane.mkLib pkgs;
      lib = pkgs.lib;

      jsonFilter = path: _type: builtins.match ".*json$" path != null;
      jsonOrCargo = path: type:
        (jsonFilter path type) || (craneLib.filterCargoSources path type);

      src = lib.cleanSourceWith {
        src = ./.;
        filter = jsonOrCargo;
        name = "source";
      };

      common-args = {
        inherit src;
        strictDeps = true;

        buildInputs = [pkgs.udev];
        nativeBuildInputs = [pkgs.installShellFiles pkgs.pkg-config];

        postInstall = ''
          installShellCompletion --cmd zbus \
            --bash ./target/release/build/zbus-*/out/zbus.bash \
            --fish ./target/release/build/zbus-*/out/zbus.fish \
            --zsh ./target/release/build/zbus-*/out/_zbus
          installManPage ./target/release/build/zbus-*/out/zbus.1
        '';
      };

      cargoArtifacts = craneLib.buildDepsOnly common-args;

      zbus = craneLib.buildPackage (common-args
        // {
          inherit cargoArtifacts;
        });

      pre-commit-check = hooks:
        pre-commit-hooks-nix.lib.${system}.run {
          src = ./.;

          inherit hooks;
        };
    in rec {
      #checks = {
      #  inherit zbus;

      #  zbus-clippy = craneLib.cargoClippy (common-args
      #    // {
      #      inherit cargoArtifacts;
      #      cargoClippyExtraArgs = "--all-targets -- --deny warnings";
      #    });

      #  zbus-fmt = craneLib.cargoFmt {
      #    inherit src;
      #  };

      #  zbus-deny = craneLib.cargoDeny {
      #    inherit src;
      #  };

      #  pre-commit-check = pre-commit-check {
      #    alejandra.enable = true;
      #  };
      #};
      #packages.zbus = zbus;
      #packages.default = packages.zbus;

      #apps.zbus = utils.lib.mkApp {
      #  drv = packages.zbus;
      #};
      #apps.default = apps.zbus;

      formatter = pkgs.alejandra;

      devShells.default = let
        checks = pre-commit-check {
          alejandra.enable = true;
          rustfmt.enable = true;
          clippy.enable = true;
        };
      in
        craneLib.devShell {
          packages = with pkgs; [
            rustfmt
            clippy
            cargo-deny
            cargo-about
            termshot
            pkg-config
            udev
            cargo-flamegraph
          ];
          shellHook = ''
            ${checks.shellHook}
          '';
        };
    })
    // {
      hydraJobs = {
        inherit (self) checks packages devShells;
      };
    };
}
