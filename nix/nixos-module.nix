# NixOS module: CLAB Widget, using the containerlab / netlab you already have.
#
#   imports = [ clab-widget.nixosModules.default ];
#   programs.clab-widget = { enable = true; users = [ "me" ]; };
#
# That installs only the widget. The backend finds containerlab and netlab
# wherever they are (PATH, /run/wrappers/bin, your Nix profiles, ~/.local/bin).
# No containerlab / netlab yet? Let the module install them:
#
#   programs.clab-widget.containerlab.enable = true;  # setuid, for clab_admins
#   programs.clab-widget.netlab.enable = true;
#
# containerlab is set up the way its own installer does it: a setuid-root
# binary owned by group clab_admins (netlab refuses to run otherwise: it checks
# the group and calls `containerlab deploy` without sudo). Store paths can't be
# setuid, hence security.wrappers. If you already define
# security.wrappers.containerlab yourself, leave containerlab.enable off.
self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.clab-widget;
  own = self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.programs.clab-widget = {
    enable = lib.mkEnableOption "CLAB Widget (Plasma widget); uses the containerlab / netlab already installed";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = ''
        Users added to clab_admins, the group a setuid containerlab (this
        module's or your own) lets run labs without sudo. They also need Docker
        access.
      '';
    };

    containerlab = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Also install containerlab, as a setuid wrapper restricted to
          clab_admins. Leave off when containerlab is installed already.
        '';
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
      default = false;
      description = "Also install netlab (with Ansible) system-wide. Leave off when netlab is installed already.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [ own.default ] ++ lib.optional cfg.netlab.enable own.netlab;
    }

    (lib.mkIf (cfg.users != [ ]) {
      users.groups.clab_admins.members = cfg.users;
    })

    (lib.mkIf cfg.containerlab.enable {
      users.groups.clab_admins = { };

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
