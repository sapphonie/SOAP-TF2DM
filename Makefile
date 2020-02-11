all: addons/sourcemod/plugins/soap_tf2dm.smx addons/sourcemod/plugins/soap_tournament.smx

addons/sourcemod/plugins/%.smx: addons/sourcemod/scripting/%.sp
	docker run --rm -v "$(CURDIR)/addons/sourcemod/scripting:/data" -v "$(CURDIR)/addons/sourcemod/plugins:/output" \
	-v "$(CURDIR)/addons/sourcemod/scripting/include:/include" spiretf/spcomp $(notdir $<)
