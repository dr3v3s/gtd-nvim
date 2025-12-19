-- GTD Global Menu Application
-- Compile with: osacompile -o ~/bin/GTDMenu.app /tmp/GTDMenu.applescript

use AppleScript version "2.4"
use scripting additions

property GTD_DIR : "/Users/plague/Documents/GTD"
property INBOX_FILE : "/Users/plague/Documents/GTD/Inbox.org"

on run
	tell me to activate
	showMainMenu()
end run

on showMainMenu()
	set menuItems to {"📝 Capture task", "⚡ Quick capture (instant)", "📋 Capture from clipboard", "─────────────", "📊 View metrics", "📂 Open Inbox", "─────────────", "🔄 Weekly Review", "🔍 Search GTD", "─────────────", "❌ Cancel"}
	
	set chosen to choose from list menuItems with prompt "GTD - What would you like to do?" with title "GTD" default items {"📝 Capture task"}
	
	if chosen is false then return
	set choice to item 1 of chosen
	
	if choice is "📝 Capture task" then
		doCapture()
		showMainMenu()
	else if choice is "⚡ Quick capture (instant)" then
		doQuickCapture()
		showMainMenu()
	else if choice is "📋 Capture from clipboard" then
		doClipboardCapture()
		showMainMenu()
	else if choice is "📊 View metrics" then
		showMetrics()
	else if choice is "📂 Open Inbox" then
		do shell script "open -a Ghostty && sleep 0.2 && osascript -e 'tell application \"System Events\" to keystroke \"nvim ~/Documents/GTD/Inbox.org\" & return'"
	else if choice is "🔄 Weekly Review" then
		do shell script "open -a Ghostty && sleep 0.2 && osascript -e 'tell application \"System Events\" to keystroke \"nvim -c \\\"lua require(\\\\\\\"gtd-nvim.gtd.review\\\\\\\").start()\\\"\" & return'"
	else if choice is "🔍 Search GTD" then
		do shell script "open -a Ghostty && sleep 0.2 && osascript -e 'tell application \"System Events\" to keystroke \"cd ~/Documents/GTD && nvim -c \\\"lua require(\\\\\\\"gtd-nvim.gtd.lists\\\\\\\").search_all()\\\"\" & return'"
	end if
end showMainMenu

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
	
	writeTask(taskTitle, taskState, "")
	display notification "✓ [" & taskState & "] " & taskTitle with title "GTD Capture" sound name "Pop"
	refreshDisplays()
end doCapture

on doQuickCapture()
	set taskTitle to text returned of (display dialog "Quick capture:" default answer "" with title "GTD Capture" buttons {"Cancel", "Capture"} default button "Capture")
	
	if taskTitle is "" then return
	
	writeTask(taskTitle, "TODO", "")
	display notification "✓ " & taskTitle with title "GTD Capture" sound name "Pop"
	refreshDisplays()
end doQuickCapture

on doClipboardCapture()
	set clipContent to the clipboard as text
	
	if clipContent is "" then
		display alert "Clipboard is empty" as warning
		return
	end if
	
	-- Truncate long clipboard
	if length of clipContent > 120 then
		set clipContent to text 1 thru 120 of clipContent & "..."
	end if
	
	set taskTitle to text returned of (display dialog "Capture from clipboard:" default answer clipContent with title "GTD Capture" buttons {"Cancel", "Capture"} default button "Capture")
	
	if taskTitle is "" then return
	
	-- Check if original clipboard was URL
	set noteText to ""
	set origClip to the clipboard as text
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

on showMetrics()
	set metricsRaw to do shell script "/Users/plague/bin/gtd_sketchybar.sh counts 2>/dev/null || echo ''"
	
	set inboxCount to extractMetric(metricsRaw, "inbox")
	set nextCount to extractMetric(metricsRaw, "next")
	set waitingCount to extractMetric(metricsRaw, "waiting")
	set projectsCount to extractMetric(metricsRaw, "projects")
	set somedayCount to extractMetric(metricsRaw, "someday")
	set overdueCount to extractMetric(metricsRaw, "overdue")
	
	set msg to "📥 Inbox: " & inboxCount & "
⚡ Next: " & nextCount & "
⏳ Waiting: " & waitingCount & "
📂 Projects: " & projectsCount & "
💭 Someday: " & somedayCount
	
	if overdueCount is not "0" then
		set msg to msg & "
🚨 Overdue: " & overdueCount
	end if
	
	set btnClicked to button returned of (display dialog msg with title "GTD Metrics" buttons {"Back", "OK"} default button "OK")
	
	if btnClicked is "Back" then
		showMainMenu()
	end if
end showMetrics

on extractMetric(rawText, metricName)
	try
		set oldDelims to AppleScript's text item delimiters
		set AppleScript's text item delimiters to metricName & "="
		set parts to text items of rawText
		if (count of parts) > 1 then
			set AppleScript's text item delimiters to return
			set valuePart to text item 1 of (item 2 of parts)
			set AppleScript's text item delimiters to oldDelims
			return valuePart
		end if
		set AppleScript's text item delimiters to oldDelims
		return "0"
	on error
		return "0"
	end try
end extractMetric

on refreshDisplays()
	do shell script "rm -f /tmp/gtd_starship_cache /tmp/gtd_sketchybar_cache; /Users/plague/bin/gtd_sketchybar.sh refresh >/dev/null 2>&1 &"
end refreshDisplays
