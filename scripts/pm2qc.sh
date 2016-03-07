#!/bin/sh
source /usr/local/bin/pm2func.sh

# files

# .****************************************************************************,
# | Section: Utilities                                                         |
# `****************************************************************************'
qc_log()
{
  echo "$@"
  echo "$@" >> $QC_LOG
}

set_network_to_dhcp_client() 
{
  if [ "$(pm2func_json_get_value $VARDIR/.settings/network.json mode)" != "clientdhcp" ];then
    qc_log "[set_network_to_dhcp_client]: WARNING: not DHCP, attempting to change to DHCP"
    pm2func_cgi_cmd "set=network&interface=eth0&mode=clientdhcp"
    pm2func_cgi_cmd "set=network&interface=eth0&action=connect"
  fi
  return 0
}

# .---------------------------------------------------------,
# | Description: Write QC report file                       | 
# | Parameters: [key] [value]                               |
# '---------------------------------------------------------'
json_write_status_file()
{
  if [ -f $QC_JSON ];then
    [ $(pm2func_file_size_bytes $QC_JSON) -le 0 ] && rm $QC_JSON
  fi
  if [ ! -f $QC_JSON ];then
    echo -n "{\"version\": \"000\"," > $QC_JSON 
    echo -n "\"timestamp\": \"0\"," >> $QC_JSON 
    echo -n "\"state\": \"none\"," >> $QC_JSON 
    echo -n "\"autostarthour\": 3," >> $QC_JSON 
    echo -n "\"RW-firmware-program\": \"TEST\"," >> $QC_JSON 
    echo -n "\"RW-app-update\": \"TEST\"," >> $QC_JSON 
    echo -n "\"RW-qc-tests\": \"TEST\"," >> $QC_JSON 
    echo -n "\"RO-firmware-program\": \"TEST\"," >> $QC_JSON 
    echo -n "\"RO-app-update\": \"TEST\"," >> $QC_JSON 
    echo -n "\"RO-qc-tests\": \"TEST\"" >> $QC_JSON 
    echo "}" >> $QC_JSON 
  fi
  pm2func_json_update_string $QC_JSON timestamp $(date +%Y-%m-%d_%T)
  # ip address
  # strings
  [ "$1" == "state" ] && pm2func_json_update_string $QC_JSON $1 $2
  # numbers
  sed -i 's/\("timestamp":\s\)\".\"/\1\"'$TIMESTAMP'\"/' $QC_JSON
  [ "$1" == "percent_completed" ] && pm2func_json_update_integer $QC_JSON $1 $2
}

# .****************************************************************************,
# | Section: API                                                               |
# `****************************************************************************'
pm2func_get_application_version
VARDIR=$(pm2func_vardir)
QC_JSON=$VARDIR/.settings/qc.json
QC_LOG=$VARDIR/qc.log

[ -f $QC_JSON ] || json_write_status_file
case "$1" in
  initialize)
    p2mfunc_json_update_string $QC_JSON state wait-to-start
    "$0" auto &
  ;;
  reset)
    qc_log "[QC]: $1"
    set_network_to_dhcp_client
    [ -f $QC_JSON ] && rm $QC_JSON
    [ -f $QC_LOG ] && rm $QC_LOG
    [ -f $VARDIR/update.log ] && rm $VARDIR/update.log
    if (pm2func_is_usbdrive_mounted);then
      rm -r $USBDRIVE/*
    fi
    json_write_status_file
  ;;
  start)
    "$0" reset
    qc_log "[QC]: $1"
    pm2func_json_update_string $QC_JSON state RW-firmware-program
    "$0" auto &
  ;;
  auto)
    STATE=$(pm2func_json_get_value $QC_JSON state)
    case "$STATE" in
      none)
        cat $QC_JSON
      ;;
      wait-to-start)
        CURRENT_HOUR=$(date +%k) 
        TARGET_HOUR=$(pm2func_json_get_value $QC_JSON autostarthour) 
        if [ "$CURRENT_HOUR" == "$TARGET_HOUR" ];then
          "$0" start &
        else
          sleep 3600
          "$0" auto &
        fi
      ;;
      RW-firmware-program)
        qc_log -n "[QC]: RW program firmware . . . . "
        if [ $KERNEL == 3.1 ];then
          if (pm2func_is_usbdrive_mounted);then
            if (pm2func_is_qrs_server_available); then
              pm2func_json_update_string $QC_JSON RW-firmware-program PASS
              /usr/local/bin/pm2update.sh program-firmware 5.00
              if [ $? -eq 0 ];then
                qc_log "PASS"
              else
                pm2func_json_update_string $QC_JSON RW-firmware-program FAIL
                qc_log "FAIL"
              fi
              pm2func_json_update_string $QC_JSON state RW-app-update
            else
              qc_log "Not Tested - QRS server unavailable"
              set_network_to_dhcp_client
              sleep 30
              "$0" auto &
            fi
          else
            qc_log "Not Tested - USB drive not mounted"
            pm2func_json_update_string $QC_JSON state RW-app-update
            "$0" auto &
          fi
        else
          qc_log "Not Tested - not 3.1 kernel"
          pm2func_json_update_string $QC_JSON state RW-app-update
          "$0" auto &
        fi
      ;;
      RW-app-update)
        qc_log -n "[QC]: RW update application . . . "
        if [ $KERNEL == 2.6 ];then
          if (pm2func_is_qrs_server_available); then
            /usr/local/bin/pm2update.sh update app servertest
            if [ $? -eq 0 ];then
              pm2func_json_update_string $QC_JSON RW-app-update PASS
              qc_log "PASS"
            else
              pm2func_json_update_string $QC_JSON RW-app-update FAIL
              qc_log "FAIL"
            fi
            pm2func_json_update_string $QC_JSON state RW-qc-tests
          else
            qc_log "Not Tested - QRS server unavailable"
            set_network_to_dhcp_client
          fi
        else
          qc_log "Not Tested - not 2.6 kernel"
          pm2func_json_update_string $QC_JSON state RW-qc-tests
        fi
        "$0" auto &
      ;;
      RW-qc-tests)
        qc_log -n "[QC]: RW QC tests . . . . . . . . "
        if [ $KERNEL == 2.6 ];then
          /root/unittests/test > /dev/null
          if [ $? -eq 0 ];then
            pm2func_json_update_string $QC_JSON RW-qc-tests PASS
            qc_log "PASS"
          else
            pm2func_json_update_string $QC_JSON RW-qc-tests FAIL
            qc_log "FAIL"
          fi
        else
          qc_log "Not Tested - not 2.6 kernel"
        fi
        pm2func_json_update_string $QC_JSON state RO-firmware-program
        "$0" auto &
      ;;
      RO-firmware-program)
        qc_log -n "[QC]: RO program firmware . . . . "
        if [ $KERNEL == 2.6 ];then
          if (pm2func_is_usbdrive_mounted);then
            if (pm2func_is_qrs_server_available); then
              pm2func_json_update_string $QC_JSON RO-firmware-program PASS
              /usr/local/bin/pm2update.sh update firmware servertest
              if [ $? -eq 0 ];then
                qc_log "PASS"
              else
                pm2func_json_update_string $QC_JSON RO-firmware-program FAIL
                qc_log "FAIL"
              fi
              pm2func_json_update_string $QC_JSON state RO-app-update
            else
              qc_log "Not Tested - QRS server unavailable"
              set_network_to_dhcp_client
              sleep 30
              "$0" auto &
            fi
          else
            qc_log "Not Tested - USB drive not mounted"
            pm2func_json_update_string $QC_JSON state RO-app-update
            "$0" auto &
          fi
        else
          qc_log "Not Tested - not 2.6 kernel"
          pm2func_json_update_string $QC_JSON state RO-app-update
          "$0" auto &
        fi
      ;;
      RO-app-update)
        qc_log -n "[QC]: RO update application . . . "
        if [ $KERNEL == 3.1 ];then
          if (pm2func_is_qrs_server_available); then
            /usr/local/bin/pm2update.sh update app servertest
            if [ $? -eq 0 ];then
              pm2func_json_update_string $QC_JSON RO-app-update PASS
              qc_log "PASS"
            else
              pm2func_json_update_string $QC_JSON RO-app-update FAIL
              qc_log "FAIL"
            fi
            pm2func_json_update_string $QC_JSON state RO-qc-tests
          else
            qc_log "Not Tested - QRS server unavailable"
            set_network_to_dhcp_client
            sleep 30
            "$0" auto &
          fi
        else
          qc_log "Not Tested - not 3.1 kernel"
          pm2func_json_update_string $QC_JSON state RO-qc-tests
          "$0" auto &
        fi
      ;;
      RO-qc-tests)
        qc_log -n "[QC]: RO QC tests . . . . . . . . "
        if [ $KERNEL == 3.1 ];then
          /root/specifications/playlist.sh qc > /dev/null
          if [ $? -eq 0 ];then
            pm2func_json_update_string $QC_JSON RO-qc-tests PASS
            qc_log "PASS"
          else
            pm2func_json_update_string $QC_JSON RO-qc-tests FAIL
            qc_log "FAIL"
          fi
        else
          qc_log "Not Tested - not 3.1 kernel"
        fi
        pm2func_json_update_string $QC_JSON state none
        "$0" auto &
      ;;
      *)
        qc_log "unknown state $STATE"
      ;;
    esac
  ;;
  *)
    echo "[$0]: Unknown parameter $1"
    echo "Usage: $0 [initialize|reset|start|auto]"
    exit 1
  ;;
esac

exit $?
