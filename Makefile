PLIST = ~/Library/LaunchAgents/com.bobrippling.plugaway.plist

plugaway: plugaway.swift
	swiftc $<

install: plugaway ${PLIST}

${PLIST}: com.bobrippling.plugaway.plist
	cp $< $@

load: install
	launchctl load ${PLIST}

unload: install
	launchctl unload ${PLIST}

.PHONY: load unload install
