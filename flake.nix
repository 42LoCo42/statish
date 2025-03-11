{
  outputs = { flake-utils, nixpkgs, self, ... }: {
    lib.mkstatish =
      { name
      , text
      , bins ? [ ]
      , pkgs
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
          cp ${pkgs.lib.getExe self.packages.${pkgs.system}.statish} bin
          chmod +w bin

          for i in ${paths} ${script}; do echo "$i"; done

          find ${paths} ${script} -not -type d     \
          | tar c -T- --transform 's|.*/||' --zstd \
          | objcopy --add-section statish=/dev/stdin bin

          ${if shell == null then "" else ''
            <<< "${shell}" \
            objcopy --add-section statish-shell=/dev/stdin bin
          ''}

          install -Dm755 bin $out/bin/${name}
        '')
      ];
  } // flake-utils.lib.eachDefaultSystem (system:
    let pkgs = import nixpkgs { inherit system; }; in rec {
      packages = rec {
        default = statish;

        statish = pkgs.buildGoModule rec {
          pname = "statish";
          version = "1.0.0";

          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
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

        example = self.lib.mkstatish {
          name = "example";
          text = builtins.readFile ./test/main;
          bins = [ "curl" ];
          inherit pkgs;
        };
      };

      devShells.default = pkgs.mkShell {
        inputsFrom = [ packages.default ];
        packages = [
          (pkgs.writeShellApplication {
            name = "run";
            text = builtins.readFile ./run;
          })
        ];
      };
    });
}
