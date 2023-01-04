#!/bin/bash
/home/sappho/tfTEST/tf2/tf/addons/sourcemod/scripting/spcomp -i ./addons/sourcemod/scripting/include/ addons/sourcemod/scripting/soap_tournament.sp -o addons/sourcemod/plugins/soap_tournament.smx
sync; sleep 1
/home/sappho/tfTEST/tf2/tf/addons_1.10/sourcemod/scripting/spcomp -i ./addons/sourcemod/scripting/include/ addons/sourcemod/scripting/soap_tournament.sp -o addons/sourcemod/plugins/soap_tournament.smx

cp ./addons/sourcemod/plugins/* /home/sappho/tfTEST/tf2/tf/addons/sourcemod/plugins/ -rfv
