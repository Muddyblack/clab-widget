{
  description = "CLAB Widget — Containerlab & netlab lab status for KDE Plasma 6 and Hyprland/Quickshell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: f system);
      metadata = builtins.fromJSON (builtins.readFile ./package/metadata.json);
      pluginId = metadata.KPlugin.Id;
    in {
      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "clab-widget";
            version = metadata.KPlugin.Version;
            src = ./package;
            dontConfigure = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall
              root=$out/share/plasma/plasmoids/${pluginId}
              mkdir -p "$root"
              cp -r . "$root/"
              # plasmashell's PATH on NixOS has no python3; pin it (see tools/run).
              substituteInPlace "$root/contents/tools/run" \
                --replace-fail 'PY_DEFAULT="python3"' \
                               'PY_DEFAULT="${pkgs.python3}/bin/python3"'
              # Register the icon (all sizes) so the widget explorer, panel
              # config and notifications show it.
              for f in contents/icons/app/${pluginId}-*.png; do
                n=''${f##*-}; n=''${n%.png}
                install -Dm644 "$f" "$out/share/icons/hicolor/''${n}x''${n}/apps/${pluginId}.png"
              done
              runHook postInstall
            '';

            meta = {
              description = "Containerlab & netlab lab status widget for KDE Plasma 6";
              license = pkgs.lib.licenses.gpl3Plus;
              platforms = pkgs.lib.platforms.linux;
            };
          };

          netlab = pkgs.callPackage ./nix/netlab.nix { };
          containerlab = pkgs.callPackage ./nix/containerlab.nix { };
        });

      # programs.clab-widget: the widget, using the installed containerlab / netlab;
      # containerlab.enable / netlab.enable install them (setuid for clab_admins).
      nixosModules.default = import ./nix/nixos-module.nix self;

      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # The backend needs python3 (not on NixOS's default PATH); the lab
          # tools go last so system-installed versions still win.
          runtimePath = ''
            export PATH=${pkgs.lib.makeBinPath [ pkgs.python3 ]}:"$PATH":${pkgs.lib.makeBinPath [ self.packages.${system}.containerlab self.packages.${system}.netlab ]}
          '';
        in {
          # Both preview the working copy, so edits show up without a rebuild.
          view = {
            type = "app";
            program = toString (pkgs.writeShellScript "clab-widget-view" ''
              if [ ! -f "$PWD/package/metadata.json" ]; then
                echo "error: run 'nix run .#view' from the repo root" >&2
                exit 1
              fi
              export PATH=${pkgs.lib.makeBinPath [ pkgs.kdePackages.plasma-sdk pkgs.kdePackages.plasma-desktop ]}:"$PATH"
              ${runtimePath}
              exec plasmoidviewer -a "$PWD/package" -f "''${1:-planar}"
            '');
          };
          # The tray app for Windows/macOS, runnable on any Linux desktop too.
          desktop = {
            type = "app";
            program = toString (pkgs.writeShellScript "clab-widget-desktop" ''
              if [ ! -f "$PWD/desktop/app.py" ]; then
                echo "error: run 'nix run .#desktop' from the repo root" >&2
                exit 1
              fi
              export PATH="$PATH":${pkgs.lib.makeBinPath [ self.packages.${system}.containerlab self.packages.${system}.netlab ]}
              exec ${pkgs.python3.withPackages (ps: [ ps.pyside6 ])}/bin/python3 "$PWD/desktop/app.py" "$@"
            '');
          };
          # make pack: the .plasmoid that release.yml publishes.
          pack = {
            type = "app";
            program = toString (pkgs.writeShellScript "clab-widget-pack" ''
              set -euo pipefail
              here="$PWD"
              [ -f "$here/package/metadata.json" ] || { echo "error: run 'nix run .#pack' from the repo root" >&2; exit 1; }
              ver="$(${pkgs.jq}/bin/jq -r .KPlugin.Version "$here/package/metadata.json")"
              out="$here/$(basename "$here")-$ver.plasmoid"
              rm -f "$out"
              (cd "$here/package" && ${pkgs.zip}/bin/zip -qr "$out" . -x '*.swp' '*~' '*/__pycache__/*')
              echo "wrote $out"
            '');
          };
          view-hyprland = {
            type = "app";
            program = toString (pkgs.writeShellScript "clab-widget-quickshell" ''
              if [ ! -f "$PWD/shell.qml" ]; then
                echo "error: run 'nix run .#view-hyprland' from the repo root" >&2
                exit 1
              fi
              ${runtimePath}
              exec ${pkgs.quickshell}/bin/qs -p "$PWD/shell.qml"
            '');
          };
        });

      checks = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          # jsonschema: the Schema tests validate snapshots against docs/.
          backend = pkgs.runCommand "clab-widget-backend-tests" { nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.jsonschema ])) ]; } ''
            cp -r ${./package} package
            cp -r ${./tests} tests
            cp -r ${./docs} docs
            python3 -m unittest discover -s tests -v
            touch $out
          '';
          frontend-logic = pkgs.runCommand "clab-widget-labs-js-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
            cp -r ${./package} package
            cp -r ${./tests} tests
            node tests/labs.test.js
            touch $out
          '';
        });

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            name = "clab-widget-dev";
            packages = with pkgs; [
              # netlab (containerlab is appended to PATH in shellHook below)
              self.packages.${system}.netlab

              # widget development
              qt6.qtdeclarative
              kdePackages.kirigami
              kdePackages.libplasma
              kdePackages.plasma-sdk
              quickshell
              (python3.withPackages (ps: [ ps.jsonschema ps.pillow ]))
              nodejs
              ruff
              jq
              yq-go
            ];
            shellHook = ''
              # Appended, not prepended: a system-wide setuid containerlab
              # (nixosModules.default) must win, or netlab refuses to deploy.
              export PATH="$PATH:${self.packages.${system}.containerlab}/bin"
              export QML_IMPORT_PATH="${pkgs.kdePackages.kirigami.unwrapped}/lib/qt-6/qml:${pkgs.kdePackages.libplasma}/lib/qt-6/qml:${pkgs.qt6.qtdeclarative}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
              echo "clab-widget dev shell: containerlab $(command -v containerlab), netlab ${self.packages.${system}.netlab.version}"
              echo "  nix run .#view | .#view-hyprland — preview   ·   python3 -m unittest discover -s tests"
            '';
          };

          # Desktop tray app (desktop/): `nix develop .#desktop`, then
          # `python desktop/app.py`. Separate so the main shell stays PySide-free.
          desktop = pkgs.mkShell {
            name = "clab-widget-desktop";
            packages = [
              (pkgs.python3.withPackages (ps: [ ps.pyside6 ]))
              pkgs.ruff
            ];
          };
        });
    };
}
