#!/bin/bash
/home/steph/tfTEST/tf2/tf/addons/sourcemod/scripting/spcomp -i ./addons/sourcemod/scripting/include/ addons/sourcemod/scripting/soap_tf2dm.sp -o addons/sourcemod/plugins/soap_tf2dm.smx
sync; sleep 1
/home/steph/tfTEST/tf2/tf/addons_1.10/sourcemod/scripting/spcomp -i ./addons/sourcemod/scripting/include/ addons/sourcemod/scripting/soap_tf2dm.sp -o addons/sourcemod/plugins/soap_tf2dm.smx

/home/steph/tfTEST/tf2/tf/addons/sourcemod/scripting/spcomp -i ./addons/sourcemod/scripting/include/ addons/sourcemod/scripting/soap_tournament.sp -o addons/sourcemod/plugins/soap_tournament.smx
sync; sleep 1
/home/steph/tfTEST/tf2/tf/addons_1.10/sourcemod/scripting/spcomp -i ./addons/sourcemod/scripting/include/ addons/sourcemod/scripting/soap_tournament.sp -o addons/sourcemod/plugins/soap_tournament.smx
