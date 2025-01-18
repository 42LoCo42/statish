{
  outputs = { flake-utils, nixpkgs, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let mypkgs = import nixpkgs { inherit system; }; in rec {
        packages = rec {
          default = statish;

          statish = mypkgs.buildGoModule rec {
            pname = "statish";
            version = "1.0.0";

            src = mypkgs.lib.fileset.toSource {
              root = ./.;
              fileset = mypkgs.lib.fileset.unions [
                ./go.mod
                ./go.sum
                ./main.go
              ];
            };

            env.CGO_ENABLED = "0";
            ldflags = [ "-s" "-w" ];
            vendorHash = "sha256-Xh/tUcR3a4BA4gcArO6npWi39otqxoU8yaLr8EZONGU=";

            meta.mainProgram = pname;
          };

          example = lib.mkstatish {
            name = "example";
            text = builtins.readFile ./test/main;
            bins = [ "coreutils" ];
          };
        };

        lib.mkstatish =
          { name
          , text
          , bins ? [ ]
          , pkgs ? mypkgs
          , shell ? "bash"
          }:
          let script = pkgs.writeScriptBin "main" (text); in
          pkgs.lib.pipe bins [
            (x: x ++ (if shell == null then [ ] else [ shell ]))
            pkgs.lib.unique
            (map (x: "${pkgs.pkgsStatic.${x}}/bin"))
            (builtins.concatStringsSep " ")
            (paths: (pkgs.runCommand "${name}-statish" {
              nativeBuildInputs = with pkgs; [
                binutils # objcopy
                findutils
                gnutar
                zstd
              ];
            }) ''
              cp ${pkgs.lib.getExe packages.statish} $out
              chmod +w $out

              for i in ${paths} ${script}; do echo "$i"; done

              find ${paths} ${script} -not -type d     \
              | tar c -T- --transform 's|.*/||' --zstd \
              | objcopy --add-section statish=/dev/stdin $out

              ${if shell == null then "" else ''
                <<< "${shell}" \
                objcopy --add-section statish-shell=/dev/stdin $out
              ''}
            '')
          ];

        devShells.default = mypkgs.mkShell {
          inputsFrom = [ packages.default ];
          packages = [
            (mypkgs.writeShellApplication {
              name = "run";
              text = builtins.readFile ./run;
            })
          ];
        };
      });
}
