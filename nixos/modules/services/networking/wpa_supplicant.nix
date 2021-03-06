{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.networking.wireless;
  configFile = if cfg.networks != {} then pkgs.writeText "wpa_supplicant.conf" ''
    ${optionalString cfg.userControlled.enable ''
      ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=${cfg.userControlled.group}
      update_config=1''}
    ${concatStringsSep "\n" (mapAttrsToList (ssid: networkConfig: let
      psk = if networkConfig.psk != null
        then ''"${networkConfig.psk}"''
        else networkConfig.pskRaw;
      priority = networkConfig.priority;
    in ''
      network={
        ssid="${ssid}"
        ${optionalString (psk != null) ''psk=${psk}''}
        ${optionalString (psk == null) ''key_mgmt=NONE''}
        ${optionalString (priority != null) ''priority=${toString priority}''}
      }
    '') cfg.networks)}
  '' else "/etc/wpa_supplicant.conf";
in {
  options = {
    networking.wireless = {
      enable = mkEnableOption "wpa_supplicant";

      interfaces = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "wlan0" "wlan1" ];
        description = ''
          The interfaces <command>wpa_supplicant</command> will use. If empty, it will
          automatically use all wireless interfaces.
        '';
      };

      driver = mkOption {
        type = types.str;
        default = "nl80211,wext";
        description = "Force a specific wpa_supplicant driver.";
      };

      networks = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            psk = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                The network's pre-shared key in plaintext defaulting
                to being a network without any authentication.

                Be aware that these will be written to the nix store
                in plaintext!

                Mutually exclusive with <varname>pskRaw</varname>.
              '';
            };

            pskRaw = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                The network's pre-shared key in hex defaulting
                to being a network without any authentication.

                Mutually exclusive with <varname>psk</varname>.
              '';
            };
            priority = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = ''
                By default, all networks will get same priority group (0). If some of the
                networks are more desirable, this field can be used to change the order in
                which wpa_supplicant goes through the networks when selecting a BSS. The
                priority groups will be iterated in decreasing priority (i.e., the larger the
                priority value, the sooner the network is matched against the scan results).
                Within each priority group, networks will be selected based on security
                policy, signal strength, etc.
              '';
            };
          };
        });
        description = ''
          The network definitions to automatically connect to when
           <command>wpa_supplicant</command> is running. If this
           parameter is left empty wpa_supplicant will use
          /etc/wpa_supplicant.conf as the configuration file.
        '';
        default = {};
        example = literalExample ''
          { echelon = {
              psk = "abcdefgh";
            };
            "free.wifi" = {};
          }
        '';
      };

      userControlled = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Allow normal users to control wpa_supplicant through wpa_gui or wpa_cli.
            This is useful for laptop users that switch networks a lot and don't want
            to depend on a large package such as NetworkManager just to pick nearby
            access points.

            When using a declarative network specification you cannot persist any
            settings via wpa_gui or wpa_cli.
          '';
        };

        group = mkOption {
          type = types.str;
          default = "wheel";
          example = "network";
          description = "Members of this group can control wpa_supplicant.";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = flip mapAttrsToList cfg.networks (name: cfg: {
      assertion = cfg.psk == null || cfg.pskRaw == null;
      message = ''networking.wireless."${name}".psk and networking.wireless."${name}".pskRaw are mutually exclusive'';
    });

    environment.systemPackages =  [ pkgs.wpa_supplicant ];

    services.dbus.packages = [ pkgs.wpa_supplicant ];

    # FIXME: start a separate wpa_supplicant instance per interface.
    systemd.services.wpa_supplicant = let
      ifaces = cfg.interfaces;
      deviceUnit = interface: [ "sys-subsystem-net-devices-${interface}.device" ];
    in {
      description = "WPA Supplicant";

      after = lib.concatMap deviceUnit ifaces;
      before = [ "network.target" ];
      wants = [ "network.target" ];
      requires = lib.concatMap deviceUnit ifaces;
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.wpa_supplicant ];

      script = ''
        ${if ifaces == [] then ''
          for i in $(cd /sys/class/net && echo *); do
            DEVTYPE=
            source /sys/class/net/$i/uevent
            if [ "$DEVTYPE" = "wlan" -o -e /sys/class/net/$i/wireless ]; then
              ifaces="$ifaces''${ifaces:+ -N} -i$i"
            fi
          done
        '' else ''
          ifaces="${concatStringsSep " -N " (map (i: "-i${i}") ifaces)}"
        ''}
        exec wpa_supplicant -s -u -D${cfg.driver} -c ${configFile} $ifaces
      '';
    };

    powerManagement.resumeCommands = ''
      ${config.systemd.package}/bin/systemctl try-restart wpa_supplicant
    '';

    # Restart wpa_supplicant when a wlan device appears or disappears.
    services.udev.extraRules = ''
      ACTION=="add|remove", SUBSYSTEM=="net", ENV{DEVTYPE}=="wlan", RUN+="${config.systemd.package}/bin/systemctl try-restart wpa_supplicant.service"
    '';
  };

  meta.maintainers = with lib.maintainers; [ globin ];
}
