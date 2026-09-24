# containerlab from the upstream release binary. nixpkgs trails (0.71 at the
# time of writing) and netlab 26.9 requires >= 0.75. The binary is static Go.
{ lib, stdenvNoCC, fetchurl }:

let
  version = "0.79.0";
  assets = {
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-+Q021Yu2xK/Ts6TcoAa4FZTG0W96BL4BhLA/RCkQhaI=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-6J4FH3H6160cdMAYn7JgU5wfVjflwQ/lP3T6a02+Upg=";
    };
  };
  asset = assets.${stdenvNoCC.hostPlatform.system}
    or (throw "containerlab: no release binary for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "containerlab";
  inherit version;

  src = fetchurl {
    url = "https://github.com/srl-labs/containerlab/releases/download/v${version}/containerlab_${version}_linux_${asset.arch}.tar.gz";
    inherit (asset) hash;
  };
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 containerlab $out/bin/containerlab
    ln -s containerlab $out/bin/clab
    runHook postInstall
  '';

  meta = {
    description = "Container-based networking labs";
    homepage = "https://containerlab.dev";
    license = lib.licenses.bsd3;
    mainProgram = "containerlab";
    platforms = builtins.attrNames assets;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
