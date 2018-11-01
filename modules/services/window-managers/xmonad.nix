{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.xsession.windowManager.xmonad;

  xmonad = pkgs.xmonad-with-packages.override {
    ghcWithPackages = cfg.haskellPackages.ghcWithPackages;
    packages = self:
      cfg.extraPackages self
      ++ optionals cfg.enableContribAndExtras [
        self.xmonad-contrib self.xmonad-extras
      ];
  };

  # A file that exposes nix-generated paths to the compilation.
  nixVarsHs = pkgs.writeTextFile {
    name = "Nix.Vars.hs";
    text = import (cfg.configDir + "/lib/Nix/Vars.hs.nix") (cfg.configData xmonad);
  };

  anotherXmonad = pkgs.xmonad-with-packages.override {
    packages = self: [
      self.xmonad-contrib self.xmonad-extras
    ];
  };

  xmonadConfigBuild = pkgs.stdenv.mkDerivation rec {
    name = "custom-xmonad-config";
    src = cfg.configDir;
    #env = pkgs.buildEnv { name = name; path = bul; };
    buildInputs = [ anotherXmonad ];
    buildPhase = ''
      # Copy Nix.Vars
      ln -s ${nixVarsHs} lib/Nix/Vars.hs
      echo "XMonad is compiling source..."
      ln -s ./ .xmonad
      HOME=$(pwd) xmonad --recompile
      echo "Compilation successfull!"
    '';
    installPhase = ''
      echo $(ls)
      echo "Copying generated files to the package"
      mkdir -p $out/bin $out/src
      cp xmonad-x86_64-linux $out/bin/
      cp --parents $(find ./ -type f -name "*.hs") $out/src/
      mkdir -p $out/src/lib/Nix
      ln -s ${nixVarsHs} $out/src/lib/Nix/Vars.hs
    '';
  };

in

{
  options = {
    xsession.windowManager.xmonad = {
      enable = mkEnableOption "xmonad window manager";

      configDir = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Directory sourced in automatic build
        '';
      };
      configData = mkOption {
        default = null;
        description = ''
          Data handed over to lib/Nix/Vars.hs.nix
        '';
      };

      haskellPackages = mkOption {
        default = pkgs.haskellPackages;
        defaultText = "pkgs.haskellPackages";
        example = literalExample "pkgs.haskell.packages.ghc784";
        description = ''
          The <varname>haskellPackages</varname> used to build xmonad
          and other packages. This can be used to change the GHC
          version used to build xmonad and the packages listed in
          <varname>extraPackages</varname>.
        '';
      };

      extraPackages = mkOption {
        default = self: [];
        defaultText = "self: []";
        example = literalExample ''
          haskellPackages: [
            haskellPackages.xmonad-contrib
            haskellPackages.monad-logger
          ]
        '';
        description = ''
          Extra packages available to GHC when rebuilding xmonad. The
          value must be a function which receives the attribute set
          defined in <varname>haskellPackages</varname> as the sole
          argument.
        '';
      };

      enableContribAndExtras = mkOption {
        default = false;
        type = types.bool;
        description = "Enable xmonad-{contrib,extras} in xmonad.";
      };

      config = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = literalExample ''
          pkgs.writeText "xmonad.hs" '''
            import XMonad
            main = xmonad defaultConfig
                { terminal    = "urxvt"
                , modMask     = mod4Mask
                , borderWidth = 3
                }
          '''
        '';
        description = ''
          The configuration file to be used for xmonad. This must be
          an absolute path or <literal>null</literal> in which case
          <filename>~/.xmonad/xmonad.hs</filename> will not be managed
          by Home Manager.
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      xsession.windowManager.command = "${xmonad}/bin/xmonad";

      home.file.".xmonad" = {
        source = "${xmonadConfigBuild}/bin";
        recursive = true;
      };
    }

    (mkIf (cfg.config != null) {
      home.file.".xmonad/xmonad.hs".source = cfg.config;
      home.file.".xmonad/xmonad.hs".onChange = ''
        echo "Recompiling xmonad"
        $DRY_RUN_CMD ${config.xsession.windowManager.command} --recompile

        # Attempt to restart xmonad if X is running.
        if [[ -v DISPLAY ]] ; then
          echo "Restarting xmonad"
          $DRY_RUN_CMD ${config.xsession.windowManager.command} --restart
        fi
      '';
    })
  ]);
}
