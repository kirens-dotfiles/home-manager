# Adapted from Nixpkgs.

{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.safeeyes;

in

{

  options.services.safeeyes = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Enable Safe Eyes to get reminded to take brakes for your eyes.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.safeeyes;
      defaultText = "pkgs.safeeyes";
      description = ''
        Safe Eyes derivation to use
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.user.services.safeeyes = {
      description = "safeeyes";

      Unit = {
        Description = "Safe Eyes break remineder";
#        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };

      Service = {
        ExecStart = ''
          ${cfg.package}/bin/safeeyes
        '';
        RestartSec = 3;
        Restart = "on-failure";
        StartLimitInterval = 350;
        StartLimitBurst = 10;
      };
    };
  };

}
