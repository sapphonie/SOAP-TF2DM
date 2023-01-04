#!/bin/bash
/home/sappho/tfTEST/tf2/tf/addons/sourcemod/scripting/spcomp -i ./addons/sourcemod/scripting/include/ ~/SOAP-TF2DM/addons/sourcemod/scripting/soap_tf2dm.sp -o addons/sourcemod/plugins/soap_tf2dm.smx
/home/sappho/tfTEST/tf2/tf/addons/sourcemod/scripting/spcomp -i ./addons/sourcemod/scripting/include/ ~/SOAP-TF2DM/addons/sourcemod/scripting/soap_tournament.sp -o addons/sourcemod/plugins/soap_tournament.smx

cp ./addons/sourcemod/plugins/* /home/sappho/tfTEST/tf2/tf/addons/sourcemod/plugins/ -rfv
