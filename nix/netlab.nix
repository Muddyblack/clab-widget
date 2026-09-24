# netlab (ipSpace) is not in nixpkgs; it ships on PyPI as `networklab`.
# Built from the wheel: it is pure Python, and the sdist adds nothing we need.
{ lib, python3Packages, fetchPypi }:

python3Packages.buildPythonApplication rec {
  pname = "networklab";
  version = "26.9";
  format = "wheel";

  src = fetchPypi {
    inherit pname version;
    format = "wheel";
    dist = "py3";
    python = "py3";
    hash = "sha256-jA2JOwebLWDmKoSkA98gPB0IfuClj+tUqH419y6sIx4=";
  };

  dependencies = with python3Packages; [
    jinja2
    pyyaml
    netaddr
    python-box
    importlib-resources
    typing-extensions
    filelock
    packaging
    requests
    rich

    # `netlab up` pushes initial device config through Ansible. netlab detects
    # it as an importable Python package (not via PATH), so it has to live in
    # the same interpreter env; this is what `netlab install ansible` would add.
    ansible
    ansible-core
    ansible-pylibssh
    paramiko
  ];

  pythonImportsCheck = [ "netsim" ];

  meta = {
    description = "Network lab orchestration (\"network as code\") by ipSpace";
    homepage = "https://github.com/ipspace/netlab";
    license = lib.licenses.mit;
    mainProgram = "netlab";
  };
}
