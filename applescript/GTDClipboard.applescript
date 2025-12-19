-- GTD Clipboard Capture Application
-- Compile with: osacompile -o ~/bin/GTDClipboard.app /tmp/GTDClipboard.applescript

use AppleScript version "2.4"
use scripting additions

property INBOX_FILE : "/Users/plague/Documents/GTD/Inbox.org"

on run
	tell me to activate
	doClipboardCapture()
end run

on doClipboardCapture()
	set clipContent to the clipboard as text
	
	if clipContent is "" then
		display alert "Clipboard is empty" as warning
		return
	end if
	
	set origClip to clipContent
	
	-- Truncate long clipboard for display
	if length of clipContent > 120 then
		set clipContent to text 1 thru 120 of clipContent & "..."
	end if
	
	set taskTitle to text returned of (display dialog "Capture from clipboard:" default answer clipContent with title "GTD Capture" buttons {"Cancel", "Capture"} default button "Capture")
	
	if taskTitle is "" then return
	
	-- Check if original clipboard was URL
	set noteText to ""
	if origClip starts with "http://" or origClip starts with "https://" then
		set noteText to "Source: " & origClip
	end if
	
	writeTask(taskTitle, "TODO", noteText)
	display notification "✓ " & taskTitle with title "GTD Capture" sound name "Pop"
	refreshDisplays()
end doClipboardCapture

on writeTask(taskTitle, taskState, noteText)
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
	
	if noteText is not "" then
		set taskContent to taskContent & "

" & noteText
	end if
	
	do shell script "echo " & quoted form of taskContent & " >> " & quoted form of INBOX_FILE
end writeTask

on refreshDisplays()
	do shell script "rm -f /tmp/gtd_starship_cache /tmp/gtd_sketchybar_cache; /Users/plague/bin/gtd_sketchybar.sh refresh >/dev/null 2>&1 &"
end refreshDisplays
