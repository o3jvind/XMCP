#tag Class
Protected Class RevertProject
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("revert_project", "Reverts the current Xojo project to the version saved on disk. Use this after modifying project files (e.g. .xojo_window, .xojo_code) directly on disk to reload them in the IDE. The project is closed and reopened, so unsaved IDE changes are discarded and open editor tabs are lost. On Windows a throwaway project is briefly opened alongside it, because closing the last project window would quit the IDE.")

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  #Pragma Unused args

		  // Reloading a project through IDE scripting has exactly one non-interactive route:
		  // CloseProject(False) followed by OpenFile. Everything else was tested and rejected
		  // (Xojo 2025r3.1, verified by adding a module to the project file on disk and
		  // checking whether the IDE picked it up):
		  //
		  //   DoCommand "Revert"      - always raises a modal confirmation dialog. A human has
		  //                             to click it, and while it is up the IDE's script engine
		  //                             is blocked, so every XMCP tool hangs. Not automatable,
		  //                             and triggering it saves the user nothing over using the
		  //                             menu item themselves.
		  //   OpenFile <same project> - returns normally and reloads nothing.
		  //
		  // On Windows, closing the last project window quits the IDE, so the close is done
		  // while a throwaway host project holds the IDE open - see the Windows branch below.

		  If App.IDE = Nil Then
		    Return MCPKit.ToolResult.Failure("Xojo IDE is not connected. Start the IDE and restart XMCP.")
		  End If

		  #If TargetWindows Then
		    // Windows quits the IDE when its last project window closes, so the target cannot
		    // simply be closed and reopened. A second open workspace window prevents that. (The
		    // script itself carries on after CloseProject either way - measured on 2026r2.1.)
		    //
		    // CloseProject acts on the frontmost workspace window, and OpenFile on an
		    // already-open project focuses it without reloading - that is what makes the
		    // ordering below controllable. Every step is measured, not assumed.

		    // 1. Where is the target?
		    Var reachable As Boolean
		    Var targetShell As String = ProjectPathFromIDE(reachable)
		    If Not reachable Then Return IDEFailure("reading the project path")
		    If targetShell = "" Then
		      Return MCPKit.ToolResult.Failure("No project is open in the Xojo IDE, or it has never " + _
		      "been saved to disk. Open a saved project and try again.")
		    End If

		    Var target As FolderItem = FileFromShellPath(targetShell)
		    If target = Nil Then
		      Return MCPKit.ToolResult.Failure("Could not resolve the open project's path: " + targetShell)
		    End If

		    // 2. A second window is only needed if the target is the only one open. When the
		    //    user already has another project open, it holds the IDE up for us.
		    Var windowsBefore As Integer = WindowCountFromIDE
		    Var hostCreated As Boolean = False

		    If windowsBefore = 1 Then
		      // NewConsoleProject opens an unsaved workspace window. Nothing is written to disk
		      // and CloseProject(False) discards it without prompting.
		      Call App.IDE.SendAndReceive("NewConsoleProject" + EndOfLine + "Print ""created""", 30000)

		      If WindowCountFromIDE <= windowsBefore Then
		        Var waiting As MCPKit.ToolResult = StillWaiting("opening a second workspace window", False, target.NativePath, TempProjectNote(True))
		        If waiting <> Nil Then Return waiting
		        // The request did reach the IDE, so an empty project may have opened even though the
		        // count does not show it - say so, as StillWaiting does when the request is still waiting.
		        Return MCPKit.ToolResult.Failure("Could not open a second workspace window, which is " + _
		        "needed because closing the last project would quit the IDE on Windows. Nothing was " + _
		        "changed to your project. Reload it manually instead. " + TempProjectNote(True))
		      End If
		      hostCreated = True
		    ElseIf windowsBefore < 1 Then
		      // Say why it could not be read when the IDE told us. The usual reason now is the
		      // refusal that arrives while an earlier request is still parked, and "the IDE is
		      // still busy with an earlier request" is a far more useful thing to read than a
		      // generic warning about quitting the IDE.
		      Var why As String = App.IDE.LastErrorMessage
		      If why <> "" Then
		        Return MCPKit.ToolResult.Failure("Could not read how many workspace windows are open, " + _
		        "so closing the project might quit the IDE. Nothing was changed." + EndOfLine + EndOfLine + why)
		      End If
		      Return MCPKit.ToolResult.Failure("Could not read how many workspace windows are open, " + _
		      "so closing the project might quit the IDE. Nothing was changed.")
		    End If

		    // 3. Focus the target, then close it. The extra window keeps the IDE running.
		    If Not OpenAndVerify(target) Then
		      Var waitingFocus As MCPKit.ToolResult = StillWaiting("bringing the project to the front", False, target.NativePath, If(hostCreated, TempProjectNote(False), ""))
		      If waitingFocus <> Nil Then Return waitingFocus
		      Var tempNote As String = If(hostCreated, CloseTempProject(windowsBefore), "")
		      Return MCPKit.ToolResult.Failure("Could not focus the project before closing it. " + _
		      "Nothing was changed. Reload the project manually instead." + tempNote)
		    End If

		    Call CloseFocusedProject

		    Var afterClose As String = ProjectPathFromIDE(reachable)
		    If Not reachable Then
		      Var waitingClose As MCPKit.ToolResult = StillWaiting("closing the project", True, target.NativePath, If(hostCreated, TempProjectNote(False), ""))
		      If waitingClose <> Nil Then Return waitingClose
		      Return MCPKit.ToolResult.Failure("The Xojo IDE stopped responding while closing the " + _
		      "project: " + App.IDE.LastErrorMessage + " Reopen the project manually: " + target.NativePath + _
		      If(hostCreated, " - and only then close the empty project XMCP opened for this, since on " + _
		      "Windows closing the last open project quits the IDE.", ""))
		    End If
		    If SamePath(afterClose, target) Then
		      Var tempNote As String = If(hostCreated, CloseTempProject(windowsBefore), "")
		      Return MCPKit.ToolResult.Failure("The project did not close, so it has not been " + _
		      "reloaded from disk. Nothing was changed." + tempNote)
		    End If

		    // 4. Reopen the target from disk.
		    If Not OpenAndVerify(target) Then
		      Var waitingOpen As MCPKit.ToolResult = StillWaiting("reopening the project", True, target.NativePath, If(hostCreated, TempProjectNote(False), ""))
		      If waitingOpen <> Nil Then Return waitingOpen
		      Return MCPKit.ToolResult.Failure("The project was closed but did not reopen. Another " + _
		      "workspace window is still open, so the IDE is still running. Reopen the project " + _
		      "manually: " + target.NativePath + If(hostCreated, " - and only then close the empty project " + _
		      "XMCP opened for this, since on Windows closing the last open project quits the IDE.", ""))
		    End If

		    // 5. Drop our extra window, leaving the IDE as we found it. It is the only unsaved
		    //    one, because step 2 only created it when the target was the sole window.
		    //    The reload itself has worked by now, so whatever happens here is a note on a
		    //    success, not a failure.
		    If hostCreated Then
		      Var tempNote As String = CloseTempProject(windowsBefore)
		      // Restoring focus is skipped while the close is still waiting: it would only be
		      // turned down. When it runs, it can itself be the step left waiting, and says so.
		      If App.IDE.DrainPending = 0 Then
		        Call OpenAndVerify(target)
		        tempNote = tempNote + WaitingNote("bringing your project back to the front", "")
		      End If
		      Return MCPKit.ToolResult.Success("Project reloaded from disk: " + target.NativePath + tempNote)
		    End If

		    Return MCPKit.ToolResult.Success("Project reloaded from disk: " + target.NativePath)
		  #Else
		    // 1. Learn where the project lives while it is still open.
		    Var reachable As Boolean
		    Var shellPath As String = ProjectPathFromIDE(reachable)
		    If Not reachable Then Return IDEFailure("reading the project path")
		    If shellPath = "" Then
		      Return MCPKit.ToolResult.Failure("No project is open in the Xojo IDE, or it has never " + _
		      "been saved to disk. Open a saved project and try again.")
		    End If

		    // 2. Resolve the path once: needed as a long path for the reopen and for messages,
		    //    and as a FolderItem to compare against what the IDE reports later.
		    Var target As FolderItem = FileFromShellPath(shellPath)
		    Var nativePath As String = shellPath
		    If target <> Nil And target.Exists Then nativePath = target.NativePath

		    // 3. Close, discarding unsaved IDE changes: reloading from disk is the whole point.
		    //    The False suppresses the save prompt. The reply is not what counts: whether the project
		    //    actually closed is, and only step 4's question shows that. (Measured on 2026r2.1: the
		    //    script carries on after CloseProject and its reply does arrive.)
		    Call App.IDE.SendAndReceive("CloseProject(False)" + EndOfLine + "Print ""closed""", 20000)

		    // Compare against the target, not against "" - if the IDE has another project open
		    // it becomes the current one after the close, so an empty path is not the signal.
		    Var afterClose As String = ProjectPathFromIDE(reachable)
		    If reachable And SamePath(afterClose, target) Then
		      Return MCPKit.ToolResult.Failure("CloseProject did not take effect - the project is " + _
		      "still open and has not been reloaded from disk. Nothing was changed.")
		    End If

		    If Not reachable Then
		      Var waitingClose As MCPKit.ToolResult = StillWaiting("closing the project", True, nativePath, "")
		      If waitingClose <> Nil Then Return waitingClose
		      Return MCPKit.ToolResult.Failure("The Xojo IDE stopped responding after the project " + _
		      "was closed: " + App.IDE.LastErrorMessage + " Reopen the project manually: " + nativePath)
		    End If

		    // 4. Reopen from disk, then confirm by asking the IDE rather than trusting the reply.
		    Var openResponse As JSONItem = App.IDE.SendAndReceive( _
		    "OpenFile """ + nativePath + """" + EndOfLine + "Print ""reopened""", 30000)
		    // Kept now: the check below sends a request of its own, which replaces the message.
		    Var openError As String = App.IDE.LastErrorMessage

		    If Not SamePath(ProjectPathFromIDE(reachable), target) Then
		      Var waitingOpen As MCPKit.ToolResult = StillWaiting("reopening the project", True, nativePath, "")
		      If waitingOpen <> Nil Then Return waitingOpen
		      Var detail As String = ""
		      If openResponse = Nil Then
		        detail = openError
		      Else
		        detail = App.IDE.ReplyDiagnostics(openResponse)
		      End If
		      If detail <> "" Then detail = " (" + detail + ")"

		      Return MCPKit.ToolResult.Failure("The project was closed but did not reopen" + detail + _
		      ". Reopen it manually: " + nativePath)
		    End If

		    Return MCPKit.ToolResult.Success("Project reloaded from disk: " + nativePath)
		  #EndIf

		End Function
	#tag EndMethod


	#tag Method, Flags = &h21
		Private Function CloseFocusedProject() As Boolean
		  /// Closes the frontmost project, discarding unsaved changes. Callers verify the effect with
		  /// ProjectPathFromIDE rather than trusting the reply: the reply says the script ran, not that
		  /// the project closed. (An older note here said closing takes the script host with it;
		  /// measured on 2026r2.1 on macOS and Windows, it does not - the script carries on and answers.)

		  Call App.IDE.SendAndReceive("CloseProject(False)" + EndOfLine + "Print ""closed""", 20000)
		  Return True

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FileFromShellPath(shellPath As String) As FolderItem
		  If shellPath.Trim = "" Then Return Nil

		  Try
		    Return New FolderItem(shellPath, FolderItem.PathModes.Shell)
		  Catch e As RuntimeException
		    Return Nil
		  End Try

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function CloseUnsavedWindow() As Boolean
		  /// Closes the one workspace window that has no path on disk - the empty project this
		  /// tool created. Only called when we created it, so there is no other unsaved window
		  /// to confuse it with.
		  ///
		  /// Selecting the window and closing it are separate requests, so that the close acts on the
		  /// window the first request found and left selected, and its result can be checked apart.

		  Var findScript As String = "Dim found As Integer = -1" + EndOfLine + _
		  "Dim i As Integer" + EndOfLine + _
		  "For i = 0 To WindowCount - 1" + EndOfLine + _
		  "  SelectWindow(i)" + EndOfLine + _
		  "  If ProjectShellPath = """" Then" + EndOfLine + _
		  "    found = i" + EndOfLine + _
		  "    Exit" + EndOfLine + _
		  "  End If" + EndOfLine + _
		  "Next" + EndOfLine + _
		  "Print Str(found)"

		  Var response As JSONItem = App.IDE.SendAndReceive(findScript, 20000)
		  If response = Nil Or Not response.HasKey("response") Then Return False

		  Var resp As Variant = response.Value("response")
		  If resp.Type <> Variant.TypeString Then Return False
		  If resp.StringValue.Trim = "-1" Then Return False

		  // The loop left that window selected, so this closes it.
		  Return CloseFocusedProject

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function WindowCountFromIDE() As Integer
		  /// How many workspace windows the IDE has open, or -1 if it could not be read.
		  ///
		  /// This is what makes closing a project safe on Windows: with more than one window
		  /// open, closing one cannot quit the IDE.

		  // -1 means "could not read it". App.IDE.LastErrorMessage still holds why, and the
		  // caller reports it: a parked-request refusal used to be flattened into a generic
		  // "might quit the IDE" message that named no cause.
		  Var response As JSONItem = App.IDE.SendAndReceive("Print Str(WindowCount)")
		  If response = Nil Or Not response.HasKey("response") Then Return -1

		  Var resp As Variant = response.Value("response")
		  If resp.Type <> Variant.TypeString Then Return -1

		  Var text As String = resp.StringValue.Trim
		  If text = "" Then Return -1

		  Return text.ToInteger

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function OpenAndVerify(project As FolderItem) As Boolean
		  /// Opens (or focuses, if already open) a project and confirms it became current.

		  If project = Nil Then Return False

		  Call App.IDE.SendAndReceive("OpenFile """ + project.NativePath + """" + EndOfLine + _
		  "Print ""opened""", 60000)

		  Var reachable As Boolean
		  Return SamePath(ProjectPathFromIDE(reachable), project)

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function SamePath(shellPathFromIDE As String, expected As FolderItem) As Boolean
		  /// Compares a path reported by the IDE with one we hold. Both are normalised through
		  /// FolderItem first: the IDE hands back shell paths, which are escaped on macOS and
		  /// the 8.3 short form on Windows, so string comparison would fail on both.

		  If expected = Nil Then Return False

		  Var reported As FolderItem = FileFromShellPath(shellPathFromIDE)
		  If reported = Nil Then Return False

		  Return reported.NativePath = expected.NativePath

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function StillWaiting(stepName As String, projectClosed As Boolean, projectPath As String, tempNote As String) As MCPKit.ToolResult
		  /// Nil, unless one of this tool's own requests is still waiting for the IDE - then the
		  /// message that says so, in place of a misleading one.
		  ///
		  /// Several steps here send a request and ignore its reply, then check the effect with a
		  /// second call. If the first request is still being carried out when its wait runs out -
		  /// a slow close, a dialog - it is left waiting, and the second call is turned down. The
		  /// check used to read that as the step having failed ("stopped responding", "did not
		  /// reopen") when the IDE was in fact still doing it. Asking whether a request is still
		  /// waiting tells the two apart.
		  ///
		  /// tempNote is TempProjectNote, about the empty project the Windows branch opens, or "":
		  /// the user has to close it by hand when the tool stops early.
		  
		  If App.IDE = Nil Or App.IDE.DrainPending = 0 Then Return Nil
		  
		  Var what As String
		  If projectClosed Then
		    what = "The project may already be closed. When the IDE has finished, check whether it is open, " + _
		    "and reopen it manually if it is not: " + projectPath
		  Else
		    what = "Nothing has been changed yet: the project has not been closed. When the IDE has finished, " + _
		    "run revert_project again."
		  End If
		  If tempNote <> "" Then what = what + " " + tempNote
		  
		  Return MCPKit.ToolResult.Failure("The Xojo IDE has not finished " + stepName + " yet. It is still " + _
		  "working on it, so further requests are turned down until it answers - nothing has failed so far. " + _
		  "Wait for it, or click any dialog it is showing. " + what + EndOfLine + EndOfLine + _
		  "Do not quit or restart Claude Code (or whichever MCP client you use) meanwhile: on macOS and " + _
		  "Linux the Xojo IDE crashes if it answers over a connection that has been closed.")
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function CloseTempProject(windowsBefore As Integer) As String
		  /// Closes the empty project the Windows branch opened, then checks that it is gone.
		  /// Returns "" when it is, or a note to add to whatever the tool reports: the user has to
		  /// close it by hand otherwise, and nothing else would tell them.
		  ///
		  /// Checked, not assumed. The close is the tool's last request, and a close that stalls,
		  /// fails, or cannot be verified used to go unmentioned: while it is still waiting the
		  /// window count is turned down and reads as -1, which passed for "closed".
		  
		  Call CloseUnsavedWindow
		  
		  Var waiting As String = WaitingNote("closing the temporary empty project XMCP opened for this", _
		  "close that empty project without saving if it is still open afterwards")
		  If waiting <> "" Then Return waiting
		  
		  // With it closed, the count is back to what it was before this tool opened it.
		  Var count As Integer = WindowCountFromIDE
		  If count = windowsBefore Then Return ""
		  If count < 0 Then
		    // The count itself can be the request left waiting - then say so, with the warning not to
		    // quit, exactly as for the close; a success would otherwise hide it.
		    Return " (note: could not check whether the temporary empty project XMCP opened was closed; " + _
		    "if it is still open in the IDE, close it without saving)" + _
		    WaitingNote("checking whether the temporary empty project XMCP opened was closed", "")
		  End If
		  Return " (note: the temporary empty project XMCP opened could not be closed and is still open " + _
		  "in the IDE; close it without saving)"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function TempProjectNote(mayAppear As Boolean) As String
		  /// What to tell the user about the empty project the Windows branch opens, when the tool
		  /// stops before closing it. The order matters: on Windows, closing the last open project
		  /// quits the IDE, so the empty one must stay open until the user's own project is open
		  /// again - after a close, it may be the only window left.
		  
		  If mayAppear Then
		    Return "XMCP also asked the IDE to open an empty project for this. If one appears, close it " + _
		    "without saving - but only while another project is open, since on Windows closing the last " + _
		    "open project quits the IDE."
		  End If
		  Return "The empty project XMCP opened for this is still open too. Close it without saving once " + _
		  "your project is open again - not before, since on Windows closing the last open project quits the IDE."
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function WaitingNote(stepName As String, afterwards As String) As String
		  /// "", unless one of this tool's requests is still waiting for the IDE - then a note
		  /// naming the step, to add to the tool's result. For the last steps of the Windows
		  /// branch, which run after the reload has already worked: nothing after them would
		  /// notice a stall, so the result would read as finished while further requests are
		  /// turned down, with no warning against quitting meanwhile.
		  
		  If App.IDE = Nil Or App.IDE.DrainPending = 0 Then Return ""
		  
		  Var todo As String = "Wait for it, or click any dialog it is showing"
		  If afterwards <> "" Then todo = todo + "; " + afterwards
		  
		  Return EndOfLine + EndOfLine + "The Xojo IDE has not finished " + stepName + ", so further " + _
		  "requests are turned down until it answers. " + todo + "." + EndOfLine + EndOfLine + _
		  "Do not quit or restart Claude Code (or whichever MCP client you use) meanwhile: on macOS and " + _
		  "Linux the Xojo IDE crashes if it answers over a connection that has been closed."
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function IDEFailure(whileDoing As String) As MCPKit.ToolResult
		  If App.IDE.LastErrorMessage <> "" Then
		    Return MCPKit.ToolResult.Failure("IDE communication failed while " + whileDoing + ": " + _
		    App.IDE.LastErrorMessage)
		  End If

		  Return MCPKit.ToolResult.Failure("Timeout waiting for the IDE while " + whileDoing + ".")

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ProjectPathFromIDE(ByRef ideReachable As Boolean) As String
		  /// The open project's shell path, or "" if no project is open.
		  ///
		  /// ideReachable distinguishes "no project open" from "no IDE answering" - both of
		  /// which return "". Conflating them turns a vanished IDE into an apparent successful
		  /// close, so callers must check it.

		  ideReachable = False

		  Var response As JSONItem = App.IDE.SendAndReceive("Print ProjectShellPath")
		  If response = Nil Then Return ""

		  ideReachable = True

		  // A real error means there is no path to read. A warnings-only reply or an empty
		  // object means the script ran and printed nothing - there is no path then either, but
		  // not because anything failed. Either way the answer is "", and only an actual string
		  // is read, so a non-string response can no longer be coerced into a path.
		  If App.IDE.ReplyDiagnostics(response) <> "" Then Return ""
		  If Not response.HasKey("response") Then Return ""
		  
		  Var resp As Variant = response.Value("response")
		  If resp.Type <> Variant.TypeString Then Return ""
		  Return resp.StringValue.Trim

		End Function
	#tag EndMethod


	#tag ViewBehavior
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Index"
			Visible=true
			Group="ID"
			InitialValue="-2147483648"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Super"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Left"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Top"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Description"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="String"
			EditorType="MultiLineEditor"
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
