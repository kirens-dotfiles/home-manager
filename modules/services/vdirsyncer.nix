{ config, lib, pkgs, ... }:
let
  cfg = config.services.vdirsyncer;

  printPair = pair: ''
    a
  '';

  inherit (lib)
    types
    ;
  inherit (types)
    attrsOf
    submodule
    path
    string
    package
    nullOr
    ;

  recursiveListOf = type: listOf (either (recursiveListOf type) type);
in

{
  meta.maintainers = [ ];

  options = {
    services.vdirsyncer = {
      enable = mkEnableOption "Synchronize calendars and contacts";

      # TODO: abstraction layer
      # calendars.google =

      package = mkOption {
        default = pkgs.vdirsyncer;
        type = package;
        defaultText = "pkgs.vdirsyncer";
      };

      statusPath = mkOption {
        default = "~/.vdirsyncer/status/";
        type = path;
        description = ''
          A directory where vdirsyncer will store some additional data for the
          next sync.

          The data is needed to determine whether a new item means it has been
          added on one side or deleted on the other. Relative paths will be
          interpreted as relative to the configuration file’s directory.
        '';
      };
      aditionalConfig = mkOption {
        default = "";
        type = string;
        description = ''
          Additional config to be inserted after generated contents.
        '';
      };

      pairs = mkOption {
        type = attrsOf (submodule {
          options = {
            a = mkOption {
              type = str;
              description = "Reference the storages to sync by their names.";
            };
            b = mkOption {
              type = str;
              description = "Reference the storages to sync by their names.";
            };
            collections = mkOption {
              type = nullOr (recursiveListOf str);
              description = ''
                A list of collections to synchronize when vdirsyncer sync is
                executed. Read more in vdirsyncer docs.
              '';
              example = [["bar" "bar_a" "bar_b"] "foo"];
            };

            conflictResolution = mkOption {
              type = nullOr (either string (listOf string));
              example = ["command" "vimdiff" "--noplugin"];
              default = null;
              description = ''
                Define how conflicts should be handled. A conflict occurs when
                one item (event, task) changed on both sides since the last
                sync.
              '';
            };
            partialSync = mkOption {
              type = enum [ "error" "ignore" "revert" ];
              default = "revert";
              description = ''
                Assume A is read-only, B not. If you change items on B,
                vdirsyncer can’t sync the changes to A. What should happen
                instead?
              '';
            };
          };
        });

        example = {
          gcals = {
            a = "google_calendar";
            b = "local_calendar";
            collections = ["from a" "from b"];
            metadata = ["color" "displayname"];
          };
        };
      };

      storages = mkOption {
        type = let
          const = name: { type = enum [ name ]; };
          text = description: { type = str; inherit description; };
          optional = defenition:
            { default = null; }
            //
            defenition
            //
            { type = nullOr defenition.type; }
            ;

          calShared = {
            startDate = withName "start_date"
              (date "Start date of timerange to show.");
            endDate = withName "end_date"
              (date "End date of timerange to show.");
            itemTypes = withName "item_types" {
              type = listOf string;
              example = [ "VEVENT" "VTODO" ];
            };
          };

          davShared = {
            url = mandatory (text "Base URL or an URL to a calendar.");
            username = text "Username for authentication.";
            password = text "Password for authentication.";
            verify = {
              type = either bool path;
              descriptiopn = ''
                Verify SSL certificate, default True. This can also be a local
                path to a self-signed SSL certificate. See SSL and certificate
                validation for more information.
              '';
            };
            verifyFingerprint = withName "verify_fingerprint" (text ''
              SHA1 or MD5 fingerprint of the expected server certificate. See
              SSL and certificate validation for more information.
            '');
            auth = {
              type = enum [ "basic" "digest" "guess" ];
              description = ''
                The default is preemptive Basic auth, sending credentials even
                if server didn’t request them. This saves from an additional
                roundtrip per request. Consider setting guess if this causes
                issues with your server.
              '';
            };
            authCert = withName "auth_cert" {
              type = either path (listOf path);
              description = ''
                Either a path to a certificate with a client certificate and
                the key or a list of paths to the files with them.
              '';
            };
            useragent = { type = str; };
          };

          cardDav = davShared // type "caldav";
          calDav = davShared // calShared // type "carddav";

          googleShared = {
            tokenFile = mandatory (aPath "Where access tokens are stored.");
            client_id = mandatory
              (text "OAuth credentials, from the Google API Manager.");
            client_secret = mandatory
              (text "OAuth credentials, from the Google API Manager.");
          };
          googleContacts = googleShared // type "google_contacts";
          googleCalendar = googleShared // calShared // type "google_calendar";

          eteSyncShared = {
            email = mandatory (text "The email address of your account.");
            secrets = mandatory (withName "secrets_dir" (aPath ''
              A directory where vdirsyncer can store the encryption key and
              authentication token.
            ''));
            url = withName "server_url"
              (text "URL to the root of your custom server.");
            db = withName "db_path"
              (text "Use a different path for the database.");
          };

        in attrsOf (anyOf [ caldav ]);

        example = {
          local_calendar = {
            type = "filesystem";
            fileExt = ".ics";
            path = "~/.cals";
          };
          google_calendar = {
            type = "google_calendar";
            tokenFile = "~/.vdirsyncer/google_token";
            clientId = "xxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com";
            clientSecret = "xxxxxxxxxxxxxxxxxxxxxxxx";
          };
        };
      };

    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      systemd.user.services = {
        vdirsyncer = {
          Unit = {
            Description = "vdirsyncer - Synchronize calendars and contacts";
            Documentation = "man:syncthing(1)";
            After = [ "network.target" ];
          };

          Service = {
            ExecStart = ''
              ${cfg.package}/bin/vdirsyncer discover && \
              ${cfg.package}/bin/vdirsyncer sync
            '';
            Restart = "on-failure";
            SuccessExitStatus = [ 3 4 ];
            RestartForceExitStatus = [ 3 4 ];
          };

          Install = {
            WantedBy = [ "default.target" ];
          };
        };
      };
      config.files.".config/vdirsyncer/config".text = ''
        [general]
        status_path = "${cfg.statusPath}"


      '';
    })

    (mkIf config.services.syncthing.tray {
      systemd.user.services = {
        qsyncthingtray = {
          Unit = {
            Description = "QSyncthingTray";
            After = [ "graphical-session-pre.target"
                      "polybar.service"
                      "taffybar.service"
                      "stalonetray.service" ];
            PartOf = [ "graphical-session.target" ];
          };

          Service = {
            Environment = "PATH=${config.home.profileDirectory}/bin";
            ExecStart = "${pkgs.qsyncthingtray}/bin/QSyncthingTray";
          };

          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      };
    })
  ];
}
