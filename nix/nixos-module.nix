# NixOS module: CLAB Widget plus a containerlab/netlab setup that works for a
# normal user, the way containerlab's own installer does it — a setuid-root
# `containerlab` owned by group clab_admins (netlab refuses to run otherwise:
# it checks the group and calls `containerlab deploy` without sudo). Store
# paths can't be setuid, hence security.wrappers.
#
#   imports = [ clab-widget.nixosModules.default ];
#   programs.clab-widget = { enable = true; users = [ "me" ]; };
self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.clab-widget;
  own = self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.programs.clab-widget = {
    enable = lib.mkEnableOption "CLAB Widget (Plasma widget) with containerlab and netlab";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = "Users allowed to run containerlab (members of clab_admins). They also need Docker access.";
    };

    containerlab = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install containerlab as a setuid wrapper restricted to clab_admins.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = own.containerlab;
        defaultText = lib.literalExpression "clab-widget.packages.\${system}.containerlab";
        description = "containerlab package (netlab 26.x needs >= 0.75; nixpkgs may be older).";
      };
    };

    netlab.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install netlab (with Ansible) system-wide.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [ own.default ] ++ lib.optional cfg.netlab.enable own.netlab;
    }

    (lib.mkIf cfg.containerlab.enable {
      users.groups.clab_admins.members = cfg.users;

      # Same as the upstream installer: root:clab_admins, setuid, no access
      # for others (chmod 4750).
      security.wrappers.containerlab = {
        source = lib.getExe cfg.containerlab.package;
        owner = "root";
        group = "clab_admins";
        setuid = true;
        permissions = "u+rx,g+x";
      };
    })
  ]);
}
