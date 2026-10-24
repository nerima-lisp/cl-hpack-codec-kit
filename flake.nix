{
  description = "RFC 7541 Huffman and prefixed-integer codecs shared by HPACK and QPACK.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-weave,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forEachSystem =
        function:
        nixpkgs.lib.genAttrs systems (system: function system (import nixpkgs { inherit system; }));
    in
    {
      formatter = forEachSystem (system: pkgs: pkgs.nixfmt-tree);

      # The source tree, installed where an ASDF source registry expects to
      # find it. A consumer adds "${cl-hpack-codec-kit}/share/common-lisp/source//"
      # to CL_SOURCE_REGISTRY; there is nothing to compile ahead of time.
      packages = forEachSystem (
        system: pkgs: {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "cl-hpack-codec-kit";
            version = "1.1.2";
            src = self;
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              target="$out/share/common-lisp/source/cl-hpack-codec-kit"
              mkdir -p "$target"
              cp -r cl-hpack-codec-kit.asd src t "$target"/
              runHook postInstall
            '';
            meta = {
              description = "RFC 7541 Huffman and prefixed-integer codecs shared by HPACK and QPACK";
              license = pkgs.lib.licenses.mit;
            };
          };
        }
      );

      checks = forEachSystem (
        system: pkgs:
        let
          clWeave = cl-weave.packages.${system}.default;
        in
        {
          test = pkgs.stdenvNoCC.mkDerivation {
            pname = "cl-hpack-codec-kit-tests";
            version = "1.1.2";
            src = self;
            nativeBuildInputs = [
              pkgs.sbcl
              clWeave
            ];
            dontConfigure = true;
            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              export CL_SOURCE_REGISTRY="$PWD//:${clWeave}/share/common-lisp/source//"
              sbcl --noinform --non-interactive \
                --eval '(require :asdf)' \
                --eval '(asdf:test-system "cl-hpack-codec-kit")'
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              runHook postInstall
            '';
          };
        }
      );

      devShells = forEachSystem (
        system: pkgs: {
          default = pkgs.mkShell {
            packages = [
              cl-weave.packages.${system}.default
              pkgs.sbcl
              pkgs.coreutils
              pkgs.perl
            ];
          };
        }
      );

      apps = forEachSystem (
        system: pkgs:
        let
          clWeave = cl-weave.packages.${system}.default;
          sourceRegistry = "${clWeave}/share/common-lisp/source//";
          test = pkgs.writeShellApplication {
            name = "cl-hpack-codec-kit-test";
            runtimeInputs = [
              pkgs.sbcl
              clWeave
            ];
            text = ''
              export CL_SOURCE_REGISTRY="$PWD//:${sourceRegistry}"
              sbcl --noinform --non-interactive \
                --eval '(require :asdf)' \
                --eval '(asdf:test-system "cl-hpack-codec-kit")'
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${test}/bin/cl-hpack-codec-kit-test";
          };
          test = {
            type = "app";
            program = "${test}/bin/cl-hpack-codec-kit-test";
          };
        }
      );
    };
}
