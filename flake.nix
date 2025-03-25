{
  description = "uv2nix base";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    uv2nix,
    pyproject-nix,
    pyproject-build-systems,
    ...
  }:
  let
    inherit (nixpkgs) lib;

    # uv workspace from workspace root
    workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

    # package overlay from workspace
    overlay = workspace.mkPyprojectOverlay {
      sourcePreference = "wheel";  # prefer over "sdist"
      # Optionally customise PEP 508 environment
      # environ = {
      #   platform_release = "5.10.65";
      # };
    };

    # build fixups where needed
    # see https://github.com/TyberiusPrime/uv2nix_hammer_overrides
    pyprojectOverrides = _final: _prev: {
      # not using buildPythonPackage, uses https://pyproject-nix.github.io/pyproject.nix/build.html
        ibis-framework = _prev.ibis-framework.overrideAttrs(old: {
          buildInputs = (old.buildInputs or []) ++ _final.resolveBuildSystem ( {hatchling = [];});
        });
    };

    # only x86_64-linux
    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    python = pkgs.python312;

    pythonSet =
      # base package set from pyproject.nix builders
      (pkgs.callPackage pyproject-nix.build.packages {
        inherit python;
      }).overrideScope
        (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
            pyprojectOverrides
          ]
        );
  in
  {
    # package a virtual environment as our main application

    # no optional dependencies for production build
    packages.x86_64-linux.default = pythonSet.mkVirtualEnv "uv-env" workspace.deps.default;

    # make hello runnable with `nix run`
    # apps.x86_64-linux = {
    #   default = {
    #     type = "app";
    #     program = "${self.packages.x86_64-linux.default}/bin/hello";
    #   };
    # };

    devShells.x86_64-linux = {

      # impure virtualenv workflow with uv
      impure = pkgs.mkShell {
        packages = [
          python
          pkgs.uv
          pkgs.zsh
        ];
        env = {
          # prevent uv from managing python downloads
          UV_PYTHON_DOWNLOADS = "never";
          # force uv to use nixpkgs python interpreter
          UV_PYTHON = python.interpreter;
        };
      };

      # undo dependency leakage
      shellHook = ''
        unset PYTHONPATH;
        
        # zsh
        exec zsh
      '';

      # pure nix environment with uv2nix
      default = let
        # editable mode for local dependencies
        editableOverlay = workspace.mkEditablePyprojectOverlay {
          # use env variable
          root = "$REPO_ROOT";
          # Optional: only enable editable for these packages
          # members = [ "hello-world" ];
        };

        # override previous set with our overrideable overlay
        # editablePythonSet = pythonSet.overrideScope editableOverlay;

        # Override previous set with our overrideable overlay.
        editablePythonSet = pythonSet.overrideScope (
          lib.composeManyExtensions [
            editableOverlay

            # Apply fixups for building an editable package of your workspace packages
            (final: prev: {
              immich-api-caller = prev.immich-api-caller.overrideAttrs (old: {
                # It's a good idea to filter the sources going into an editable build
                # so the editable package doesn't have to be rebuilt on every change.
                src = lib.fileset.toSource {
                  root = old.src;
                  fileset = lib.fileset.unions [
                    (old.src + "/pyproject.toml")
                    (old.src + "/README.md")
                    # (old.src + "/src/hello_world/__init__.py")
                  ];
                };

                # Hatchling (our build system) has a dependency on the `editables` package when building editables.
                #
                # In normal Python flows this dependency is dynamically handled, and doesn't need to be explicitly declared.
                # This behaviour is documented in PEP-660.
                #
                # With Nix the dependency needs to be explicitly declared.
                nativeBuildInputs =
                  old.nativeBuildInputs
                  ++ final.resolveBuildSystem {
                    editables = [ ];
                  };
              });

            })
          ]
        );


        # build virtual environment, with local packages being editable
        # enable all optional dependencies for development
        virtualenv = editablePythonSet.mkVirtualEnv "uv-env" workspace.deps.all;
      in
      pkgs.mkShell {
        packages = [
          virtualenv
          pkgs.uv
          pkgs.zsh
        ];

        buildInputs = [
          virtualenv
        ];

        env = {
          # don't create venv with uv
          UV_NO_SYNC = "1";

          # force uv to use python interpreter from venv
          UV_PYTHON = "${virtualenv}/bin/python";

          # prevent uv from managing python downloads
          UV_PYTHON_DOWNLOADS = "never";
        };

        # undo dependency leakage
        shellHook = ''
          unset PYTHONPATH;
          # Get repository root using git. This is expanded at runtime by the editable `.pth` machinery.
          export REPO_ROOT=$(git rev-parse --show-toplevel)

          # zsh
          # exec zsh
        '';
      };
    };
  };
}
