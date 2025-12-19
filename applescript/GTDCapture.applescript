-- GTD Quick Capture Application
-- Compile with: osacompile -o ~/bin/GTDCapture.app /tmp/GTDCapture.applescript

use AppleScript version "2.4"
use scripting additions

property INBOX_FILE : "/Users/plague/Documents/GTD/Inbox.org"

on run
	tell me to activate
	doCapture()
end run

on doCapture()
	set taskTitle to text returned of (display dialog "What's on your mind?" default answer "" with title "GTD Capture" buttons {"Cancel", "Capture"} default button "Capture")
	
	if taskTitle is "" then return
	
	set stateList to {"TODO", "NEXT", "WAITING", "SOMEDAY"}
	set chosenState to choose from list stateList with prompt "Select GTD state:" with title "GTD Capture" default items {"TODO"}
	
	if chosenState is false then
		set taskState to "TODO"
	else
		set taskState to item 1 of chosenState
	end if
	
	writeTask(taskTitle, taskState)
	display notification "✓ [" & taskState & "] " & taskTitle with title "GTD Capture" sound name "Pop"
	refreshDisplays()
end doCapture

on writeTask(taskTitle, taskState)
	set taskID to do shell script "date +%Y%m%d%H%M%S"
	set createdDate to do shell script "date '+[%Y-%m-%d %a %H:%M]'"
	
	set taskContent to "
* " & taskState & " " & taskTitle & "
:PROPERTIES:
:ID:        " & taskID & "
:TASK_ID:   " & taskID & "
:ZK_LINK:   [[zk:" & taskID & "]]
:CREATED:   " & createdDate & "
:END:"
	
	do shell script "echo " & quoted form of taskContent & " >> " & quoted form of INBOX_FILE
end writeTask

on refreshDisplays()
	do shell script "rm -f /tmp/gtd_starship_cache /tmp/gtd_sketchybar_cache; /Users/plague/bin/gtd_sketchybar.sh refresh >/dev/null 2>&1 &"
end refreshDisplays
