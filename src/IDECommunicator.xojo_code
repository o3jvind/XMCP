#tag Class
Protected Class IDECommunicator
	#tag Method, Flags = &h0
		Sub Constructor()
		  mTagCounter = 0
		  // Random per process, so no two XMCP processes share a tag. See NextTag.
		  mTagPrefix = "xmcp_" + EncodeHex(Crypto.GenerateRandomBytes(4)).Lowercase + "_"
		  mSocketPath = FindIPCPath
		  LastErrorMessage = ""
		  mConnected = False
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function CandidateSocketPaths() As String()
		  /// The path that last worked first, then the platform's candidates in the
		  /// order the IDE itself considers them. See Platform.IPCSocketPaths.
		  
		  Var paths() As String
		  paths.Add(mSocketPath)
		  
		  For Each p As String In Platform.IPCSocketPaths
		    paths.Add(p)
		  Next p
		  
		  Var unique() As String
		  For Each p As String In paths
		    If p.Trim = "" Then Continue
		    If Not ContainsString(unique, p) Then unique.Add(p)
		  Next p
		  
		  Return unique
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ContainsString(values() As String, target As String) As Boolean
		  For Each value As String In values
		    If value = target Then Return True
		  Next value
		  
		  Return False
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FindIPCPath() As String
		  /// The path the IDE is most likely listening on. Platform.IPCSocketPaths
		  /// probes candidate FOLDERS for writability rather than testing the socket
		  /// path itself, which is the only form that works on Windows.
		  
		  Var paths() As String = Platform.IPCSocketPaths
		  If paths.Count > 0 Then Return paths(0)
		  
		  Return ""
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function NextTag() As String
		  /// Returns a unique tag string for each request to correlate requests with responses.
		  ///
		  /// Unique across processes, not only within one. An answer the IDE owes on a connection
		  /// that has gone away - its XMCP was killed or restarted while a request was waiting - is
		  /// handed to the next client that connects, ahead of that client's own answer and with its
		  /// original tag (measured against the raw socket on Windows, where the IDE survives that).
		  /// With a plain counter every XMCP process numbers from xmcp_1, so a new process's first
		  /// request could carry the same tag and take the late answer - end marker included - for
		  /// its own. Reproduced on Windows with the old tags: a second XMCP's Print "B-own-answer"
		  /// came back as the first one's "A-late-answer", reported as success. The random part,
		  /// chosen once per process, rules that out; the counter keeps tags unique within the process.

		  mTagCounter = mTagCounter + 1
		  Return mTagPrefix + mTagCounter.ToString

		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Reconnect()
		  /// Reconnect to the Xojo IDE.

		  mSocketPath = FindIPCPath
		  LastErrorMessage = ""
		  mConnected = False

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function SendAndReceive(script As String, timeoutMS As Integer = 10000) As JSONItem
		  /// Sends an IDE script and waits synchronously for the tagged response.
		  /// Uses IPCSocket transport only.
		  /// Returns the response JSON or Nil on timeout.
		  ///
		  /// Retries up to kMaxRetries times with a short pause if the socket is
		  /// temporarily unavailable (e.g. after the Xojo IDE navigates to a new
		  /// item) and the failure happened before the script was written to the
		  /// socket. Once the script has actually been sent, a subsequent failure
		  /// (e.g. timeout waiting for the response) is NOT retried, since the IDE
		  /// may have already executed it — resending could run it twice.

		  LastErrorMessage = ""
		  mParkedThisRequest = False
		  
		  // A request the IDE has accepted but not answered is still being executed: the
		  // IDE runs scripts one at a time on its main thread, and a build (or a modal
		  // dialog) holds it for minutes. Sending another request now would only queue it
		  // behind that one and give up on it too. Say so instead; DrainPending notices
		  // when the IDE has caught up and the next call goes through normally.
		  If DrainPending > 0 Then
		    // "Has not finished answering", not "has not answered": a waiting request can have part of
		    // its answer in already - the IDE sends each Print as it runs - and it is held until the
		    // answer is complete and 250 ms have passed without more (see PendingRequest.ReplyComplete).
		    // Saying the IDE "has not answered" would then be untrue.
		    LastErrorMessage = "The Xojo IDE is still busy with an earlier request and has not finished answering it:" + _
		    EndOfLine + PendingSummary + EndOfLine + _
		    "No new request was sent. Something is keeping the IDE busy - usually a build, or a dialog in " + _
		    "the IDE waiting for a click. Let the build finish or click the dialog, then try again. " + _
		    "Do not quit or restart Claude Code (or whichever MCP client you use) meanwhile: on macOS " + _
		    "and Linux the Xojo IDE crashes if it answers over a connection that has been closed."
		    LogVerbose("IDE request refused: " + LastErrorMessage)
		    Return Nil
		  End If
		  
		  Var tag As String = NextTag

		  // Build protocol upgrade + script request.
		  Var proto As New JSONItem
		  proto.Value("protocol") = 2

		  // Every request must be answerable. The IDE answers once per Print and not at all
		  // without one, so a script that prints nothing is never replied to: the request
		  // times out, its socket is parked, and because the IDE serves one IPC connection at
		  // a time that blocks every other client until the give-up timer expires. Appending
		  // the sentinel here rather than in each tool means a tool cannot forget, and a
		  // caller-supplied script - run_ide_script, or anything through RunScript - cannot
		  // reintroduce it. MergeReply ranks real output above an empty reply, so a script
		  // that does print still reports its own output.
		  //
		  // Skipped only when the script really ends in a line continuation, where the sentinel
		  // would be absorbed into that line and change its meaning. Such a script does not
		  // compile, and a compile error is itself a reply, so it cannot park either way. What
		  // counts as a continuation is decided by EndsWithLineContinuation, not by the last
		  // character: a comment or a name can end in an underscore too.
		  //
		  // An empty or whitespace-only script gets the sentinel as well. Without it such a
		  // script reaches the IDE with no Print, is never answered, and parks. Tools guard
		  // against sending one, but the guarantee belongs here, where no caller can skip it.
		  //
		  // The sentinel prints a marker unique to this request rather than an empty string, so
		  // that its arrival can be recognised: it is the script's last line, the IDE sends one
		  // reply per Print in order, so once the marker is in, the answer is complete - apart from
		  // a compiler warning, which the IDE sends after the last Print (measured on 2026r2.1:
		  // 0.3-0.6 ms later on macOS, 0.03-0.35 ms on Windows). The collection loop therefore
		  // waits kAfterEndMarkerMS after the marker instead of the full kSplitReplyWindowMS, and
		  // never hands the marker itself to a caller. See IsEndMarker.
		  Var sent As String = script
		  If Not EndsWithLineContinuation(script) Then
		    sent = script + EndOfLine + "Print """ + EndMarker(tag) + """"
		  End If
		  
		  Var req As New JSONItem
		  req.Value("tag") = tag
		  req.Value("script") = sent

		  Var payload As String = proto.ToString + Chr(0) + req.ToString + Chr(0)
		  LogVerbose("IDE request " + tag + ": trying IPCSocket transport.")

		  Const kMaxRetries = 5
		  Const kRetryPauseMS = 1000

		  Var attempt As Integer = 0
		  While attempt < kMaxRetries
		    attempt = attempt + 1

		    Var socketErrors() As String
		    For Each candidatePath As String In CandidateSocketPaths
		      LogVerbose("IDE request " + tag + ": IPCSocket path " + candidatePath + " (attempt " + attempt.ToString + ")")
		      Var responseViaSocket As JSONItem = SendAndReceiveViaIPCSocket(candidatePath, payload, tag, timeoutMS, script)
		      If responseViaSocket <> Nil Then
		        mConnected = True
		        mSocketPath = candidatePath
		        LastErrorMessage = ""
		        LogVerbose("IDE request " + tag + ": success via IPCSocket (" + candidatePath + ").")
		        Return responseViaSocket
		      End If

		      If LastErrorMessage <> "" Then
		        LogVerbose("IDE request " + tag + ": IPCSocket failed (" + candidatePath + "): " + LastErrorMessage)
		        socketErrors.Add(LastErrorMessage)
		      End If
		      
		      // The request was delivered and is now parked: the IDE has it and will execute
		      // it. Trying the remaining candidate paths - on macOS the same socket under
		      // other names - would only knock on a busy IDE again and clutter the message
		      // with "no listener" noise that is not the problem.
		      If mParkedThisRequest Then Exit
		    Next candidatePath
		    
		    If mParkedThisRequest Then
		      mParkedThisRequest = False
		      // LastErrorMessage is left as the parking message from the path that took the request.
		      // Once a request has been delivered, what the other paths said - usually "socket not
		      // found" - is beside the point, and joining it in front put that noise ahead of the
		      // warning not to quit the client.
		      Exit While
		    End If
		    
		    // All paths failed. If the socket was simply not found (IDE temporarily
		    // closed it after a navigation), wait briefly and retry.
		    Var allNotFound As Boolean = True
		    For Each err As String In socketErrors
		      If Not err.BeginsWith(kNoListenerPrefix) Then
		        allNotFound = False
		        Exit
		      End If
		    Next err

		    If attempt < kMaxRetries And (socketErrors.Count = 0 Or allNotFound) Then
		      LogVerbose("IDE request " + tag + ": socket temporarily unavailable, retrying in " + kRetryPauseMS.ToString + "ms...")
		      Var pauseDeadline As Double = System.Microseconds + (kRetryPauseMS * 1000.0)
		      While System.Microseconds < pauseDeadline
		        App.SleepCurrentThread(10)
		      Wend
		    Else
		      If socketErrors.Count > 0 Then
		        LastErrorMessage = String.FromArray(socketErrors, " | ")
		      Else
		        LastErrorMessage = "No IPCSocket response from Xojo IDE within " + timeoutMS.ToString + _
		        "ms. Searched: " + Platform.SocketPathSummary
		      End If
		      Exit While
		    End If
		  Wend

		  LogVerbose("IDE request " + tag + ": failed. " + LastErrorMessage)

		  mConnected = False
		  Return Nil

		End Function
	#tag EndMethod
	
	#tag Method, Flags = &h0
		Function RunScript(script As String, timeoutMS As Integer = 10000) As MCPKit.ToolResult
		  /// Sends an IDE script and converts the reply into a ToolResult. Fourteen tools go
		  /// through here - set_code, constant_value, get_code, select_project_item, get_project_info
		  /// and the rest -
		  /// so this is the path most of XMCP reports through.
		  ///
		  /// It now reports through the same classifier as run_ide_script, build_project,
		  /// run_project and analyze_project. It used to have its own rules, and they were wrong
		  /// in both directions: any reply carrying a scriptError key became a Failure with the
		  /// envelope dumped as raw JSON, so a script that merely raised a compiler warning was
		  /// reported as an outright failure; and a warning arriving alongside real output was
		  /// dropped entirely, because the merged parts under xmcp_parts were never read.
		  ///
		  /// That was not hypothetical. get_selected_text builds a script using Str() on an
		  /// Integer, which the IDE answers with a precision warning on every call - visible
		  /// through run_ide_script, silently discarded here.
		  ///
		  /// Three behaviours callers depend on are kept. A response that is a string is never
		  /// re-parsed as JSON: a constant or description whose text happens to contain
		  /// {"buildError":...} is content, not a failure, and re-parsing it used to say
		  /// otherwise. A script that deliberately prints "ERROR: ..." is still a Failure - that
		  /// is how several tools report their own guard clauses. And an empty object, which is
		  /// how the IDE answers a script that printed an empty string, still normalises to ""
		  /// rather than the literal text "{}".
		  
		  Var response As JSONItem = SendAndReceive(script, timeoutMS)
		  If response = Nil Then
		    If LastErrorMessage <> "" Then
		      Return MCPKit.ToolResult.Failure(LastErrorMessage)
		    End If
		    Var timeoutS As Integer = timeoutMS / 1000
		    Return MCPKit.ToolResult.Failure("No answer from the IDE within " + timeoutS.ToString + "s.")
		  End If
		  
		  If Not response.HasKey("response") Then
		    Return MCPKit.ToolResult.Failure("Unexpected response from IDE: " + response.ToString)
		  End If
		  
		  // Blocking errors first, in every shape the IDE sends, formatted, with the line numbers
		  // corrected for the boilerplate line it wraps each script in. ReplyDiagnostics returns
		  // "" for output, an empty reply, or warnings only, so a warning never lands here.
		  Var diagnostics As String = ReplyDiagnostics(response)
		  If diagnostics <> "" Then Return MCPKit.ToolResult.Failure(diagnostics)
		  
		  // Warnings are handled differently here than in run_ide_script, on purpose.
		  //
		  // The scripts reaching RunScript are generated by XMCP, not written by the caller, so a
		  // compiler warning about one is our own flaw rather than anything the caller can act on:
		  // get_selected_text uses Str() on an Integer and the IDE warns about the precision on
		  // every call. Appending that to the result would corrupt it, because for most of these
		  // tools the result IS data - the selected text, a constant's value, a list of items -
		  // and there would be no way to tell where the data ended and the diagnostic began.
		  //
		  // So a warning is attached only when the script printed nothing, where there is nothing
		  // to corrupt and it explains the silence. Otherwise it is logged and kept out of the
		  // payload. run_ide_script still reports warnings inline, because there the script is the
		  // caller's own and the warning is about their code.
		  Var warnings As String = ReplyWarnings(response)
		  
		  Var resp As String
		  Var kind As String = ReplyKind(response)
		  
		  If kind = "warning" Or kind = "empty" Then
		    // Nothing was printed. The warnings, if any, are the whole of what there is to say.
		    resp = ""
		  Else
		    Var respVar As Variant = response.Value("response")
		    If respVar.Type <> Variant.TypeObject Then
		      resp = respVar.StringValue
		    Else
		      Var respJSON As JSONItem
		      Try
		        respJSON = response.Value("response")
		      Catch e As RuntimeException
		        respJSON = Nil
		      End Try
		      If respJSON = Nil Then
		        resp = respVar.StringValue
		      ElseIf respJSON.Count = 0 Then
		        resp = ""
		      Else
		        resp = respJSON.ToString
		      End If
		    End If
		  End If
		  
		  If warnings <> "" Then
		    // Exact, for the same reason as MergeReply: resp is data. (A whitespace-only result
		    // cannot actually reach here - the IDE collapses one to an empty reply - but the test
		    // should not depend on that.)
		    If resp = "" Then
		      resp = "The script ran but printed nothing. The IDE reported warnings about it:" + _
		      EndOfLine + warnings
		    Else
		      LogVerbose("Script warnings (not surfaced, the reply carries data): " + warnings)
		    End If
		  End If
		  
		  // Case-sensitive, and deliberately not trimmed. BeginsWith is case-insensitive by
		  // default in this Xojo version, so "Error: ..." or "error: ..." in a result - a
		  // constant's value, a line of selected code - was misreported as a failure. Every tool
		  // that reports its own guard clause prints exactly "ERROR:" at the very start, so the
		  // exact, case-sensitive prefix is the whole contract; trimming would let data that
		  // merely contains "ERROR:" after some whitespace be mistaken for one.
		  If resp.BeginsWith("ERROR:", ComparisonOptions.CaseSensitive) Then
		    Return MCPKit.ToolResult.Failure(resp)
		  End If
		  
		  Return MCPKit.ToolResult.Success(resp)
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EndsWithLineContinuation(script As String) As Boolean
		  /// True when the script's last line of code ends in a line continuation, so that an
		  /// appended line would be absorbed into it.
		  ///
		  /// This used to be "the trimmed script's last character is an underscore", and that is
		  /// wrong in two ways that were each measured on 2026r2.1:
		  ///   - a comment can end in one. "Var x As Integer = 1 // rename to foo_" followed by
		  ///     more code runs the next line, so the underscore is not a continuation;
		  ///   - a name can end in one. "Var foo_ As Integer = 7" is legal.
		  /// Either as the last line of a script with no Print of its own meant no sentinel, no
		  /// reply, and the socket parked for the full give-up time.
		  ///
		  /// So the trailing comment is removed first - a ' or // outside a string literal - and an
		  /// underscore then counts only when it is not the end of a name. It cannot be told apart
		  /// by the space before it: "+_" continues exactly as "+ _" does.
		  ///
		  /// When unsure this returns False, which appends the sentinel. That is the safe way to be
		  /// wrong: a sentinel appended to a real continuation only changes the compile error of a
		  /// script that could not compile anyway, whereas a skipped one leaves a valid script
		  /// unanswered.
		  
		  Var lines() As String = script.ReplaceLineEndings(Chr(10)).Split(Chr(10))
		  Var last As String = ""
		  For i As Integer = lines.LastIndex DownTo 0
		    If lines(i).Trim <> "" Then
		      last = lines(i)
		      Exit
		    End If
		  Next i
		  If last = "" Then Return False
		  
		  // Keep the code part of the line. A comment marker inside a string literal is text, so
		  // track whether we are inside one; a doubled quote toggles twice and stays balanced.
		  Var code As String = ""
		  Var inString As Boolean = False
		  Var n As Integer = last.Length
		  For i As Integer = 0 To n - 1
		    Var c As String = last.Middle(i, 1)
		    If c = Chr(34) Then
		      inString = Not inString
		    ElseIf Not inString Then
		      If c = "'" Then Exit
		      If c = "/" And i + 1 < n And last.Middle(i + 1, 1) = "/" Then Exit
		    End If
		    code = code + c
		  Next i
		  code = code.Trim
		  
		  // A line that is only a Rem comment has no code at all. (= is case-insensitive here,
		  // which matches Rem, REM and rem alike.)
		  If code.Length >= 3 And code.Left(3) = "Rem" Then
		    If code.Length = 3 Or code.Middle(3, 1) = " " Or code.Middle(3, 1) = Chr(9) Then Return False
		  End If
		  
		  If code.Length = 0 Or code.Right(1) <> "_" Then Return False
		  If code.Length = 1 Then Return True
		  
		  // An underscore that ends a name - foo_ - belongs to the name.
		  Return Not IsNameCharacter(code.Middle(code.Length - 2, 1))
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function IsNameCharacter(c As String) As Boolean
		  /// Letters, digits and the underscore. Anything outside ASCII is counted as a letter too:
		  /// that makes EndsWithLineContinuation return False and append the sentinel, which is
		  /// the safe way to be wrong.
		  
		  If c = "" Then Return False
		  If c = "_" Then Return True
		  Var codePoint As Integer = c.Asc
		  If codePoint >= 48 And codePoint <= 57 Then Return True
		  If codePoint >= 65 And codePoint <= 90 Then Return True
		  If codePoint >= 97 And codePoint <= 122 Then Return True
		  Return codePoint > 127
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EmptyReply(tag As String) As JSONItem
		  /// The reply the IDE sends for a script that printed an empty string - an empty object -
		  /// built here for a script whose only reply was the end marker, which callers never see.
		  
		  Var envelope As New JSONItem
		  envelope.Value("tag") = tag
		  envelope.Value("response") = New JSONItem
		  Return envelope
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub CloseAnswered(sock As IPCSocket)
		  /// Closes the socket of a request whose answer is complete. The IDE has nothing more to write,
		  /// so a failing close cannot hurt it - and it must not throw the answer away: guarded like
		  /// DrainPending's close.
		  
		  Try
		    sock.Close
		  Catch e As RuntimeException
		    LogVerbose("Closing an answered connection failed (" + e.Message + "); the answer stands.")
		  End Try
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EmptyMessageExplanation(kind As String) As String
		  /// What to show when the IDE reports an error or warning without any message.
		  
		  If kind.Lowercase.EndsWith("runtimeerror") Then
		    Return "the script stopped with a runtime error, and the Xojo IDE gave no message and no line " + _
		    "number for it. Typical causes are an array index out of range or a Nil object."
		  End If
		  Return "the Xojo IDE gave no message for this."
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EndMarker(tag As String) As String
		  /// The text the sentinel Print outputs for this request. Unique per request because the tag
		  /// is, so a stale reply for another request can never be taken for this one's end.
		  
		  Return kEndMarkerPrefix + tag
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function IsEndMarker(envelope As JSONItem, tag As String) As Boolean
		  /// True when this reply part is the sentinel's own output rather than anything the script
		  /// printed. Compared exactly and case-sensitively: = on strings ignores case in Xojo, and a
		  /// loose match here would swallow a line of the caller's own output.
		  ///
		  /// Public because PendingRequest decides the same question for a parked request, and it
		  /// must decide it the same way.

		  If envelope = Nil Or Not envelope.HasKey("response") Then Return False
		  Var resp As Variant = envelope.Value("response")
		  If resp.Type <> Variant.TypeString Then Return False
		  Return resp.StringValue.Compare(EndMarker(tag), ComparisonOptions.CaseSensitive) = 0
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function BuildErrorIsKnownShape(value As Variant) As Boolean
		  /// True when a buildError holds only what the IDE has been measured to send: an "errors"
		  /// list, a "warnings" list, or both (2026r2.1, macOS and Windows, for CheckProjectErrors and
		  /// BuildApp alike). Anything else - another key, a list that is not a list, not an object at
		  /// all - is a shape nobody has seen, which must not be taken for a clean build.
		  ///
		  /// Public so analyze_project, which formats a build result its own way, decides the same.
		  
		  Try
		    If value.Type <> Variant.TypeObject Then Return False
		    Var be As JSONItem = value
		    // Not even empty: a clean build or analysis answers {} with no buildError at all
		    // (measured), so a buildError holding nothing is a shape nobody has seen either.
		    If be = Nil Or be.IsArray Or be.Count = 0 Then Return False
		    For Each key As String In be.Keys
		      If key.Compare("errors", ComparisonOptions.CaseSensitive) <> 0 And _
		        key.Compare("warnings", ComparisonOptions.CaseSensitive) <> 0 Then Return False
		      Var list As Variant = be.Value(key)
		      If list.Type <> Variant.TypeObject Then Return False
		      Var items As JSONItem = list
		      If items = Nil Or Not items.IsArray Then Return False
		    Next key
		    Return True
		  Catch e As RuntimeException
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ScriptErrorHasError(value As Variant) As Boolean
		  /// True when a scriptError value reports a compile or runtime error: any entry whose type
		  /// does not end in "warning" (a missing type counts as an error), or a value that is not a
		  /// list at all. The one test, shared by ReplyKind and StopsScript, so the two cannot differ.
		  
		  Try
		    If value.Type <> Variant.TypeObject Then Return True
		    Var items As JSONItem = value
		    If items = Nil Or Not items.IsArray Then Return True
		    For i As Integer = 0 To items.Count - 1
		      Var entry As JSONItem = items.ChildAt(i)
		      Var kind As String = If(entry <> Nil And entry.HasKey("type"), entry.Value("type").StringValue, "")
		      If Not kind.Lowercase.EndsWith("warning") Then Return True
		    Next i
		    Return False
		  Catch e As RuntimeException
		    Return True
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function StopsScript(envelope As JSONItem) As Boolean
		  /// True when this reply part is a compile or runtime error. The IDE stops the script
		  /// there, so nothing more follows - no further output and no end marker - and the
		  /// answer is complete. Measured on 2026r2.1: a runtime error and any warning arrive
		  /// together in this one part.
		  ///
		  /// A buildError is not one: DoCommand "BuildApp" returns it as a value and the script
		  /// carries on to its next line, so the end marker still comes.
		  ///
		  /// Public for the same reason as IsEndMarker.

		  // Judged on the scriptError entries themselves, not on the reply as a whole: a reply can be
		  // an error because of another key while its scriptError holds only warnings, and then the
		  // script did not stop - ending the answer there would close on a script still running.
		  If envelope = Nil Or Not envelope.HasKey("response") Then Return False
		  Try
		    Var resp As Variant = envelope.Value("response")
		    If resp.Type <> Variant.TypeObject Then Return False
		    Var obj As JSONItem = resp
		    If obj = Nil Or Not obj.HasKey("scriptError") Then Return False
		    Return ScriptErrorHasError(obj.Value("scriptError"))
		  Catch e As RuntimeException
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub LogVerbose(message As String)
		  If App <> Nil And App.Verbose Then
		    System.DebugLog(message)
		  End If
		End Sub
	#tag EndMethod
	
	#tag Method, Flags = &h21
		Private Function SendAndReceiveViaIPCSocket(candidatePath As String, payload As String, tag As String, timeoutMS As Integer, script As String) As JSONItem
		  LastErrorMessage = ""

		  #If Not TargetWindows Then
		    // A Unix domain socket is a real filesystem entry, so a missing file means the
		    // IDE is definitely not listening here and the connect can be skipped entirely.
		    // Never do this on Windows: an IPCSocket endpoint there is not a file but a TCP
		    // socket on localhost whose port is derived from the path string, so Exists is
		    // always False even while the IDE is listening.
		    Var socketFile As New FolderItem(candidatePath, FolderItem.PathModes.Native)
		    If socketFile = Nil Or Not socketFile.Exists Then
		      LastErrorMessage = kNoListenerPrefix + " at " + candidatePath + " (no socket file)."
		      Return Nil
		    End If
		  #EndIf

		  Var deadlineUS As Double = System.Microseconds + (timeoutMS * 1000.0)
		  Var sock As New IPCSocket
		  sock.Path = candidatePath

		  Try
		    sock.Connect
		  Catch e As RuntimeException
		    // Whether this counts as 'nobody is listening' - and so as retryable - differs
		    // by platform. Off Windows the Exists check above already ruled out a missing
		    // socket, so a failed connect means something more specific (a stale socket from
		    // a crashed IDE, a permission problem) and is reported as fatal, unchanged from
		    // before. On Windows there is no such check to lean on, so a failed connect is
		    // the only evidence that nothing is listening on this candidate.
		    #If TargetWindows Then
		      LastErrorMessage = kNoListenerPrefix + " at " + candidatePath + ": " + e.Message
		    #Else
		      LastErrorMessage = "IPCSocket connect failed for " + candidatePath + ": " + e.Message
		    #EndIf
		    Return Nil
		  End Try
		  
		  // Bound the connect wait separately from the response wait. Without a socket file
		  // to pre-check, a wrong candidate can only be ruled out by a failed connect, and a
		  // build request would otherwise sit here for its full 120s timeout on every
		  // candidate before reaching the one the IDE is listening on.
		  Var connectTimeoutMS As Integer = timeoutMS
		  If connectTimeoutMS > kConnectTimeoutMS Then connectTimeoutMS = kConnectTimeoutMS
		  Var connectDeadlineUS As Double = System.Microseconds + (connectTimeoutMS * 1000.0)
		  
		  // Poll is guarded like Connect above, and handled the same way: a failure here is a
		  // failed connect. Nothing has been written yet, so closing the socket is safe and the
		  // request can never have reached the IDE.
		  While Not sock.IsConnected And System.Microseconds < connectDeadlineUS
		    Try
		      sock.Poll
		    Catch e As RuntimeException
		      sock.Close
		      #If TargetWindows Then
		        LastErrorMessage = kNoListenerPrefix + " at " + candidatePath + ": " + e.Message
		      #Else
		        LastErrorMessage = "IPCSocket connect failed for " + candidatePath + ": " + e.Message
		      #EndIf
		      Return Nil
		    End Try
		    App.SleepCurrentThread(5)
		  Wend
		  
		  If Not sock.IsConnected Then
		    sock.Close
		    #If TargetWindows Then
		      LastErrorMessage = kNoListenerPrefix + " at " + candidatePath + _
		      " (connect timed out after " + connectTimeoutMS.ToString + "ms)."
		    #Else
		      LastErrorMessage = "IPCSocket connect timed out for " + candidatePath + _
		      " after " + connectTimeoutMS.ToString + "ms."
		    #EndIf
		    Return Nil
		  End If

		  // Once Write succeeds, the IDE may have already received (and be
		  // executing) the script even if we never see a response — e.g. a
		  // timeout below. From this point on, a failure must NOT be treated
		  // as safe to blindly retry with the same script.
		  Try
		    sock.Write(payload)
		    sock.Flush
		  Catch e As RuntimeException
		    // The comment above is the rule, and this branch used to break it: it closed the
		    // socket and returned without setting mParkedThisRequest, so the candidate loop went
		    // on to the next path and resent the script. On macOS the next path is usually the
		    // same socket under another name - /tmp is /private/tmp - so a write that had in fact
		    // reached the IDE before Flush failed would run twice. And closing a connection the
		    // IDE may answer on is the SIGPIPE this class exists to prevent.
		    //
		    // So it parks, like every other case where the request may have been delivered.
		    // If the connection is really broken, DrainPending finds that on its next poll - the
		    // poll throws or the socket reports itself closed - and releases it within one idle
		    // pass, so a dead socket does not hold the IDE's connection slot.
		    AddPending(sock, tag, script, "")
		    mParkedThisRequest = True
		    LastErrorMessage = "Writing the request to the Xojo IDE failed partway (" + e.Message + "). " + _
		    "It may or may not have arrived, so it is not being resent, and the connection is kept " + _
		    "open in case the IDE answers. Further requests are refused until it does or the " + _
		    "connection is found closed. Do not quit or restart Claude Code (or whichever MCP client " + _
		    "you use) meanwhile: on macOS and Linux the Xojo IDE crashes if it answers over a " + _
		    "connection that has been closed."
		    Return Nil
		  End Try

		  Var buffer As String = ""
		  Var hadData As Boolean = False
		  
		  // One answer arrives as several parts under the same tag - one per Print, then a
		  // compiler warning about the script, if any - and the IDE sends each part the moment
		  // it is produced. Measured on 2026r2.1: a Print, 232 ms of work, then a second Print
		  // arrived 232 ms apart; with a build or a dialog in between, parts are minutes apart.
		  // So a gap between parts says nothing about whether the answer is finished, and
		  // closing the socket on a gap is the SIGPIPE this class exists to prevent: the IDE
		  // writes the rest into a closed peer.
		  //
		  // What does say it is finished:
		  // - the end marker, the script's own last line (see SendAndReceive). After it only a
		  //   compiler warning can follow, within a millisecond, so kAfterEndMarkerMS is waited
		  //   for that, then the answer is complete;
		  // - a compile or runtime error (StopsScript): the IDE stops the script there, so no
		  //   marker will come;
		  // - nothing else, when no marker was appended - a script that ends in a line
		  //   continuation. Such a script cannot compile, so its answer is a compile error in
		  //   practice; the old rule, a window after the first part, is kept for it anyway.
		  // Without one of those by the deadline the script is still running, and the request
		  // parks. The same rule decides when a parked request is finished (PendingRequest).
		  Var markerExpected As Boolean = Not EndsWithLineContinuation(script)
		  Var frames() As JSONItem
		  Var collectUntilUS As Double = deadlineUS
		  Var sawEndMarker As Boolean = False
		  Var sawScriptStop As Boolean = False
		  Var windowStarted As Boolean = False
		  Var ideClosed As Boolean = False
		  
		  // Once the answer has ended - its marker is in, or the window after an error that stopped
		  // the script (or, with no marker, after its first part that is not warnings alone) has
		  // started - the short wait after it may run past the deadline: the answer has arrived, and
		  // cutting that wait short would close the socket just before a trailing part is written
		  // into it. And if that wait runs out while a part is still half read - on Windows a part
		  // can arrive in pieces - reading goes on until it is whole, for at most kPartialPartMS
		  // more: closing mid-part would cut the IDE off in the middle of writing it. Both are
		  // bounded; a normal answer leaves nothing half read and ends exactly as before.
		  While (System.Microseconds < deadlineUS Or sawEndMarker Or windowStarted) And _
		    (System.Microseconds < collectUntilUS Or _
		    ((sawEndMarker Or windowStarted) And buffer.Trim <> "" And _
		    System.Microseconds < collectUntilUS + (kPartialPartMS * 1000.0)))
		    // Guarded like Connect and Write above, and like DrainPending's own Poll. The write
		    // has already succeeded here, so the IDE may be executing the script; an exception
		    // escaping would skip both the answer and the parking below, leaking an open socket
		    // and losing the guarantee that a delivered script is never resent. Stop reading;
		    // what has arrived decides below whether the answer is complete or the request parks.
		    Var chunk As String
		    Try
		      sock.Poll
		      chunk = sock.ReadAll
		    Catch e As RuntimeException
		      LogVerbose("IDE request " + tag + ": polling failed (" + e.Message + ").")
		      Exit
		    End Try

		    If chunk = "" Then
		      // The IDE closed the connection: nothing more can arrive, so waiting out the rest of
		      // the deadline - up to 30 minutes for a build - would only delay the same outcome.
		      If Not sock.IsConnected Then
		        ideClosed = True
		        Exit
		      End If
		      App.SleepCurrentThread(5)
		      Continue
		    End If
		    
		    hadData = True
		    buffer = buffer + chunk
		    
		    Var nulPos As Integer = buffer.IndexOf(Chr(0))
		    While nulPos >= 0
		      Var frame As String = buffer.Left(nulPos).Trim
		      buffer = buffer.Middle(nulPos + 1)
		      nulPos = buffer.IndexOf(Chr(0))
		      
		      If frame = "" Then Continue
		      
		      Try
		        Var response As New JSONItem(frame)
		        If response.HasKey("tag") And response.Value("tag").StringValue = tag Then
		          If IsEndMarker(response, tag) Then
		            sawEndMarker = True
		            collectUntilUS = System.Microseconds + (kAfterEndMarkerMS * 1000.0)
		          Else
		            frames.Add(response)
		            If StopsScript(response) Then sawScriptStop = True
		            // Only where no marker is coming does a window after a part end the wait - and then
		            // not after a part of warnings alone, whose output is still to come: the same rule
		            // as the decision below and as PendingRequest.ReplyComplete.
		            If Not sawEndMarker And Not windowStarted And _
		              (sawScriptStop Or (Not markerExpected And ReplyKind(response) <> "warning")) Then
		              windowStarted = True
		              collectUntilUS = System.Microseconds + (kSplitReplyWindowMS * 1000.0)
		            End If
		          End If
		        Else
		          // Name the other tag: a late answer meant for another request - often another XMCP
		          // process's - is told apart from a malformed frame only by what it carries.
		          Var otherTag As String = If(response.HasKey("tag"), response.Value("tag").StringValue, "(none)")
		          LogVerbose("IDE request " + tag + ": ignoring a frame for another tag, " + otherTag + " (stale or unsolicited).")
		        End If
		      Catch e As RuntimeException
		        // Any exception, not only JSONException. The write has already succeeded here, so
		        // one escaping - a tag that is not a string, say - would skip both the answer and
		        // the parking below, leaving an open socket that is neither answered nor parked.
		        // A frame that cannot be read is skipped, like a malformed one always was.
		        LogVerbose("IDE request " + tag + ": skipped an unreadable frame (" + e.Message + ").")
		      End Try
		    Wend
		  Wend
		  
		  // The end marker arrived, so the script ran to its last line and its answer is complete.
		  // That holds even when the parts are only warnings, or when there are none at all -
		  // neither is "still running" any more, so neither waits. A script that printed nothing
		  // gets the empty reply the IDE would have sent for Print "", which is what every caller
		  // already understands as "no value".
		  If sawEndMarker Then
		    CloseAnswered(sock)
		    LastErrorMessage = ""
		    If frames.Count = 0 Then Return EmptyReply(tag)
		    Return MergeReply(frames)
		  End If
		  
		  // An error stopped the script, so nothing more is coming: the answer is complete.
		  If sawScriptStop Then
		    CloseAnswered(sock)
		    LastErrorMessage = ""
		    Return MergeReply(frames)
		  End If
		  
		  // No marker was appended, so the old rule stands: a window after the first part. A reply
		  // of warnings alone still parks, since the output they are about is still to come.
		  If Not markerExpected And Not ideClosed And frames.Count > 0 Then
		    Var onlyWarnings As Boolean = True
		    For Each f As JSONItem In frames
		      If ReplyKind(f) <> "warning" Then
		        onlyWarnings = False
		        Exit
		      End If
		    Next f
		    If Not onlyWarnings Then
		      CloseAnswered(sock)
		      LastErrorMessage = ""
		      Return MergeReply(frames)
		    End If
		  End If
		  
		  // The IDE closed the connection before the answer was complete - it quit or crashed, or
		  // dropped the connection. Nothing can be written into it any more, so there is nothing to
		  // protect; but the IDE may already have run the script, so it must not be sent again. It
		  // is parked all the same, so that the candidate loop stops and nothing is resent;
		  // DrainPending finds the connection closed and releases it on its next pass, so it
		  // blocks nothing.
		  If ideClosed Then
		    AddPending(sock, tag, script, buffer)
		    mParkedThisRequest = True
		    LastErrorMessage = "The Xojo IDE closed the connection before it finished answering. It may have " + _
		    "quit or crashed, or it may have run the script before closing it, so the request is not being " + _
		    "sent again. Check the IDE, then try again."
		    Return Nil
		  End If
		  
		  // Data arrived for some other tag and nothing for ours. This used to close the socket
		  // and return without setting mParkedThisRequest, which was wrong twice over: the
		  // caller's candidate loop then resent a script the IDE had already accepted, and
		  // closing a connection the IDE still owes a reply on is the SIGPIPE this class exists
		  // to avoid. A foreign frame says nothing about our request except that the IDE is
		  // busy - which is what parking is for - so it is logged and falls through.
		  If hadData And frames.Count = 0 Then
		    LogVerbose("IDE request " + tag + ": data from " + candidatePath + " carried another tag; ours is still outstanding.")
		  End If
		  
		  // The IDE accepted the request - connect and write both succeeded - and its answer is not
		  // complete within the timeout: the script is still running, even if part of its output
		  // has arrived. Do NOT close the socket. The IDE will write the rest when it is done, and
		  // a write into a closed peer raises SIGPIPE, which the Xojo IDE does not ignore: it dies
		  // mid-build, with no crash report. Park the socket open instead; DrainPending releases
		  // it once the IDE has finished or has gone away.
		  //
		  // Whatever was read but not yet framed goes with it: the time limit can fall in the middle of
		  // a part - on Windows a large one routinely arrives in pieces - and if that part is the end
		  // marker or the error that ends the answer, dropping its first half would leave the parked
		  // request unable to see its own end, refusing every request until the two-hour give-up.
		  AddPending(sock, tag, script, buffer)
		  mParkedThisRequest = True
		  LastErrorMessage = "The Xojo IDE accepted the request but has not finished answering it within " + timeoutMS.ToString + _
		  "ms. It is most likely busy - a build, or a modal dialog waiting for a click - and it will finish " + _
		  "the request regardless. The connection is kept open so the IDE can reply safely; that reply will " + _
		  "be discarded. Further requests are refused until the IDE has answered." + _
		  " Do not quit or restart Claude Code (or whichever MCP client you use) until then: " + _
		  "quitting closes this connection, and on macOS and Linux the Xojo IDE crashes if it " + _
		  "answers over a connection that has been closed."
		  
		  Return Nil
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ReplyKind(envelope As JSONItem) As String
		  /// Classifies one reply envelope by what its "response" carries:
		  ///   "output"  - a string (what the script printed), or an object that is none of the below
		  ///   "empty"   - an empty object: the IDE's answer to a script that printed nothing
		  ///   "warning" - diagnostics that are warnings only; the script or build still ran - including
		  ///               an openErrors result whose every entry says severity "warning"
		  ///   "error"   - scriptError with errors, buildError with errors, missingFiles, loadError, any
		  ///               other openErrors
		  ///   "unknown" - no "response" key at all
		  ///
		  /// scriptError is a heterogeneous array: each entry has a "type" that is
		  /// scriptCompilerError, scriptRuntimeError or scriptCompilerWarning, and a reply that
		  /// carries only warnings means the script compiled and ran. Treating the whole array as
		  /// fatal reported failures for scripts that had worked.
		  
		  If envelope = Nil Or Not envelope.HasKey("response") Then Return "unknown"
		  
		  // Anything that is not an object is what the script produced. A string is the usual
		  // case, but a reply part can also be a number or a boolean, and those used to be
		  // classified by attempting a JSONItem cast and catching the failure - control flow
		  // hidden in an exception handler, which is both slower and easy to misread as an
		  // error path. Ask what the value is instead.
		  Var resp As Variant = envelope.Value("response")
		  If resp.Type <> Variant.TypeObject Then Return "output"
		  
		  // It is an object, but not every object is a JSONItem; one that is not is still
		  // something the script produced, so the cast keeps its guard.
		  Var obj As JSONItem
		  Try
		    obj = envelope.Value("response")
		  Catch e As RuntimeException
		    Return "output"
		  End Try
		  If obj = Nil Then Return "output"
		  If obj.Count = 0 Then Return "empty"
		  
		  // Every key that can carry an error is looked at, not only the first one found: a reply
		  // counts as clean only if none of them reports anything. An error anywhere decides it;
		  // otherwise a warning anywhere; otherwise it is empty. The shapes the IDE is known to send
		  // each hold one of these keys (measured on 2026r2.1); a combination is judged the same way.
		  // Casts that meet a shape the IDE has never sent throw, and this runs after a request was
		  // written, where an exception escaping would skip both answering and parking it - so
		  // anything unreadable counts as an error: reported, rather than lost.
		  Var sawKnownKey As Boolean = False
		  Var sawWarning As Boolean = False
		  Try
		    If obj.HasKey("missingFiles") Or obj.HasKey("loadError") Then Return "error"
		    
		    If obj.HasKey("scriptError") Then
		      sawKnownKey = True
		      If ScriptErrorHasError(obj.Value("scriptError")) Then Return "error"
		      // No error among its entries: warnings only, as before - also for an empty list, which the
		      // old code called "warning" too, so no reply is classified differently for it.
		      sawWarning = True
		    End If
		    
		    // A build result counts as clean or as warnings only in the shape the IDE sends:
		    // {"buildError":{"errors":[...]}} and/or "warnings":[...] - see BuildErrorIsKnownShape.
		    // Any other shape is an error, rather than being passed off as a successful build.
		    If obj.HasKey("buildError") Then
		      sawKnownKey = True
		      If Not BuildErrorIsKnownShape(obj.Value("buildError")) Then Return "error"
		      Var be As JSONItem = obj.Value("buildError")
		      If be.HasKey("errors") And JSONItem(be.Value("errors")).Count > 0 Then Return "error"
		      If be.HasKey("warnings") And JSONItem(be.Value("warnings")).Count > 0 Then sawWarning = True
		    End If
		    
		    // openErrors is not always an error: opening a project saved by an older Xojo answers
		    // {"openErrors":[{"loadError":{"type":"IDE Version Conflict", ..., "severity":"warning"}}]}
		    // (measured on 2026r2.1), and the project does open. Only that exact shape counts as a
		    // warning (OpenErrorsAreWarnings); anything else, or anything unreadable, is an error.
		    If obj.HasKey("openErrors") Then
		      sawKnownKey = True
		      If Not OpenErrorsAreWarnings(obj.Value("openErrors")) Then Return "error"
		      sawWarning = True
		    End If
		  Catch e As RuntimeException
		    Return "error"
		  End Try
		  
		  If Not sawKnownKey Then Return "output"
		  If sawWarning Then Return "warning"
		  Return "empty"
		End Function
	#tag EndMethod
	#tag Method, Flags = &h21
		Private Function OpenErrorsAreWarnings(value As Variant) As Boolean
		  /// True only for the shape the IDE has been measured to send for a warning when opening a
		  /// project: a non-empty list of entries, each holding only objects, each object saying
		  /// severity "warning" and holding only plain values - {"loadError":{"type":"IDE Version
		  /// Conflict","projectVersion":"2026.011","ideVersion":"2026.021","severity":"warning"}}.
		  /// Anything else - a severity on the entry itself, a plain value beside the objects, an
		  /// object one level deeper, another severity - is an error, reported as it arrived.
		  ///
		  /// Deliberately narrow. Only one such result has been seen, and a rule written around
		  /// guesses at other shapes let parts of a reply be accepted as a warning and then not be
		  /// shown. This way everything accepted is exactly what FormatOpenWarnings can show in
		  /// full, and a real error is never passed off as a warning.
		  ///
		  /// The severity is compared as a whole word, trimmed and ignoring case - it is a value,
		  /// unlike the scriptError types, which are matched by their "warning" ending.
		  
		  Try
		    Var items As JSONItem = value
		    If items = Nil Or Not items.IsArray Or items.Count = 0 Then Return False
		    For i As Integer = 0 To items.Count - 1
		      Var entry As JSONItem = items.ChildAt(i)
		      If entry = Nil Or entry.IsArray Or entry.Count = 0 Then Return False
		      For Each key As String In entry.Keys
		        Var v As Variant = entry.Value(key)
		        If v.Type <> Variant.TypeObject Then Return False
		        Var inner As JSONItem = v
		        If inner = Nil Or inner.IsArray Or Not inner.HasKey("severity") Then Return False
		        If inner.Value("severity").StringValue.Trim.Compare("warning", ComparisonOptions.CaseInsensitive) <> 0 Then Return False
		        For Each field As String In inner.Keys
		          Var fv As Variant = inner.Value(field)
		          If fv.Type = Variant.TypeObject Then Return False
		        Next field
		      Next key
		    Next i
		    Return True
		  Catch e As RuntimeException
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ReplyDiagnostics(envelope As JSONItem) As String
		  /// The reply's blocking diagnostics as readable text, or "" when there are none -
		  /// that is, when the reply is output, empty, or warnings only. Covers every error
		  /// shape the IDE is known to send: scriptError (errors only; warnings are for
		  /// ReplyWarnings), buildError.errors, missingFiles, openErrors and loadError.
		  ///
		  /// missingFiles is undocumented but real: an Android build with no key store answers
		  /// {"missingFiles": "Unable to build. Please specify a Key Store properties file..."},
		  /// a precise message that used to be dropped as an unrecognised object.
		  
		  // Guarded independently of ReplyKind. Reading the response out of the envelope is
		  // only safe because ReplyKind returned "error", which implies a non-Nil envelope
		  // carrying a JSONItem response - a contract held in another method's head. If that
		  // classification ever widens, this would raise a NilObjectException rather than
		  // report the error it was asked about, so it checks for itself.
		  If envelope = Nil Or Not envelope.HasKey("response") Then Return ""
		  If ReplyKind(envelope) <> "error" Then Return ""
		  
		  Var obj As JSONItem
		  Try
		    obj = envelope.Value("response")
		  Catch e As RuntimeException
		    Return ""
		  End Try
		  If obj = Nil Then Return ""
		  
		  Var lines() As String
		  
		  // ReplyKind already calls a reply an error when its shape is not the one the IDE is known
		  // to send (a scriptError that is not a list of objects, a loadError that is a plain string).
		  // Reading the details out of such a reply can throw, and an exception here would escape the
		  // tool as an unexplained runtime error instead of the error it is. Say what arrived instead.
		  Try
		    If obj.HasKey("scriptError") Then
		      Var text As String = FormatScriptErrors(obj.Value("scriptError"), False)
		      If text <> "" Then lines.Add("Script errors:" + EndOfLine + text)
		    End If
		    If obj.HasKey("buildError") And Not BuildErrorIsKnownShape(obj.Value("buildError")) Then
		      // Not the shape the IDE sends, which is why ReplyKind called it an error: show it whole.
		      lines.Add("The IDE returned a build result XMCP does not recognise: " + JSONItem(obj.Value("buildError")).ToString)
		    ElseIf obj.HasKey("buildError") Then
		      Var be As JSONItem = obj.Value("buildError")
		      If be <> Nil And be.HasKey("errors") Then
		        Var errs As JSONItem = be.Value("errors")
		        If errs <> Nil And errs.Count > 0 Then
		          lines.Add("Build errors (" + errs.Count.ToString + "):" + EndOfLine + FormatDiagnosticList(errs, "Error"))
		        End If
		      End If
		    End If
		    If obj.HasKey("missingFiles") Then
		      lines.Add("The IDE needs something configured before it can build: " + obj.Value("missingFiles").StringValue)
		    End If
		    If obj.HasKey("openErrors") And Not OpenErrorsAreWarnings(obj.Value("openErrors")) Then
		      lines.Add("The project reported errors while opening: " + JSONItem(obj.Value("openErrors")).ToString)
		    End If
		    If obj.HasKey("loadError") Then
		      lines.Add("The project could not be loaded: " + JSONItem(obj.Value("loadError")).ToString)
		    End If
		  Catch e As RuntimeException
		    Var raw As String = "(unreadable)"
		    Try
		      raw = obj.ToString
		    Catch e2 As RuntimeException
		    End Try
		    // Keep what was already read: those lines are correct, the raw text only adds the rest.
		    lines.Add("The IDE reported an error in a form XMCP does not recognise: " + raw)
		    Return String.FromArray(lines, EndOfLine)
		  End Try
		  
		  If lines.Count = 0 Then Return "The IDE returned an error: " + obj.ToString
		  Return String.FromArray(lines, EndOfLine)
		End Function
	#tag EndMethod
	#tag Method, Flags = &h0
		Function ReplyWarnings(envelope As JSONItem) As String
		  /// Warnings carried by the reply - in its primary part or in any part MergeReply
		  /// attached - as readable text, or "" when there are none. For a successful script
		  /// this is typically a scriptCompilerWarning about the script XMCP itself sent.
		  
		  If envelope = Nil Then Return ""
		  Var lines() As String
		  
		  Var candidates() As JSONItem
		  If envelope.HasKey("response") And envelope.Value("response").Type = Variant.TypeObject Then
		    Try
		      candidates.Add(JSONItem(envelope.Value("response")))
		    Catch e As RuntimeException
		    End Try
		  End If
		  If envelope.HasKey("xmcp_parts") Then
		    Var parts As JSONItem = envelope.Value("xmcp_parts")
		    For i As Integer = 0 To parts.Count - 1
		      Try
		        // Only objects. MergeReply attaches the other parts' response VALUES, and
		        // for a multi-Print script those are plain strings - asking one of those
		        // HasKey raises, and the exception escaped as a JSON-RPC parse error.
		        Var child As JSONItem = parts.ChildAt(i)
		        If child <> Nil And Not child.IsArray Then candidates.Add(child)
		      Catch e As RuntimeException
		      End Try
		    Next i
		  End If
		  
		  For Each obj As JSONItem In candidates
		    If obj = Nil Or obj.IsArray Then Continue
		    
		    // A reply part can be any JSON the IDE chose to send. Reading warnings out of
		    // one must never fail the whole request: there is nothing to report from a part
		    // that is not an object, and that is not an error.
		    Try
		      If obj.HasKey("scriptError") Then
		        Var text As String = FormatScriptErrors(obj.Value("scriptError"), True)
		        If text <> "" Then lines.Add(text)
		      End If
		      If obj.HasKey("buildError") Then
		        Var be As JSONItem = obj.Value("buildError")
		        If be <> Nil And be.HasKey("warnings") Then
		          Var warns As JSONItem = be.Value("warnings")
		          If warns <> Nil And warns.Count > 0 Then lines.Add(FormatDiagnosticList(warns, "Warning"))
		        End If
		      End If
		      If obj.HasKey("openErrors") And OpenErrorsAreWarnings(obj.Value("openErrors")) Then
		        Var text As String = FormatOpenWarnings(obj.Value("openErrors"))
		        If text <> "" Then lines.Add(text)
		      End If
		    Catch e As RuntimeException
		    End Try
		  Next obj
		  
		  Return String.FromArray(lines, EndOfLine)
		End Function
	#tag EndMethod
	#tag Method, Flags = &h21
		Private Function FormatOpenWarnings(value As Variant) As String
		  /// One readable line per object of an openErrors result that OpenErrorsAreWarnings accepted,
		  /// e.g. "Warning while opening the project: IDE Version Conflict (projectVersion 2026.011,
		  /// ideVersion 2026.021)". That shape holds only objects of plain values, so every part of it
		  /// is shown. Each object is read on its own: one that cannot be read gets a line saying so,
		  /// rather than hiding the ones after it.
		  
		  Var lines() As String
		  Try
		    Var items As JSONItem = value
		    For i As Integer = 0 To items.Count - 1
		      Var entry As JSONItem = items.ChildAt(i)
		      For Each key As String In entry.Keys
		        Try
		          lines.Add(OpenWarningLine(entry.Value(key), key))
		        Catch e As RuntimeException
		          lines.Add("Warning while opening the project (one part of it could not be read).")
		        End Try
		      Next key
		    Next i
		  Catch e As RuntimeException
		    // Already classified as a warning, so it must not vanish: say so without the details.
		    If lines.Count = 0 Then lines.Add("Warning while opening the project (its details could not be read).")
		  End Try
		  Return String.FromArray(lines, EndOfLine)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function OpenWarningLine(item As JSONItem, fallbackKind As String) As String
		  /// "Warning while opening the project: <type> (<field value>, ...)" for one object of an
		  /// openErrors warning - the type if it has one, fallbackKind (its key) otherwise, then every
		  /// field but type and severity. OpenErrorsAreWarnings admits only plain values here.
		  
		  Var kind As String = If(item.HasKey("type"), item.Value("type").StringValue, fallbackKind)
		  Var details() As String
		  For Each field As String In item.Keys
		    If field.Compare("type", ComparisonOptions.CaseSensitive) = 0 Then Continue
		    If field.Compare("severity", ComparisonOptions.CaseSensitive) = 0 Then Continue
		    Var v As Variant = item.Value(field)
		    If v.Type = Variant.TypeObject Then Continue
		    details.Add(field + " " + v.StringValue)
		  Next field
		  Var line As String = "Warning while opening the project: " + kind
		  If details.Count > 0 Then line = line + " (" + String.FromArray(details, ", ") + ")"
		  Return line
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FormatScriptErrors(items As JSONItem, warningsOnly As Boolean) As String
		  /// One line per scriptError entry of the requested severity. The IDE wraps the
		  /// script in a line of boilerplate before compiling it, so every line number it
		  /// reports is one greater than the line that was sent; that offset is removed here.
		  /// A line too small to carry the offset passes through unchanged. Column -1 means
		  /// unknown and is omitted.
		  
		  If items = Nil Then Return ""
		  Var lines() As String
		  If Not items.IsArray Then Return items.ToString
		  
		  For i As Integer = 0 To items.Count - 1
		    Var entry As JSONItem = items.ChildAt(i)
		    If entry = Nil Then Continue
		    Var kind As String = If(entry.HasKey("type"), entry.Value("type").StringValue, "")
		    Var isWarning As Boolean = kind.Lowercase.EndsWith("warning")
		    If isWarning <> warningsOnly Then Continue
		    
		    Var text As String = If(kind = "", If(warningsOnly, "Warning", "Error"), kind)
		    // The IDE sends a runtime error with an empty message and line 0 - measured on 2026r2.1
		    // on macOS and Windows - which used to come out as "scriptRuntimeError:" and nothing
		    // else. Say what an empty message means instead of printing a bare colon.
		    Var message As String = If(entry.HasKey("message"), entry.Value("message").StringValue, "")
		    If message.Trim = "" Then message = EmptyMessageExplanation(kind)
		    text = text + ": " + message
		    If entry.HasKey("line") Then
		      Var line As Integer = entry.Value("line").IntegerValue
		      If line >= 2 Then line = line - 1
		      If line > 0 Then text = text + " (line " + line.ToString + ")"
		    End If
		    If entry.HasKey("column") Then
		      Var column As Integer = entry.Value("column").IntegerValue
		      If column >= 0 Then text = text + " (column " + column.ToString + ")"
		    End If
		    lines.Add(text)
		  Next i
		  
		  Return String.FromArray(lines, EndOfLine)
		End Function
	#tag EndMethod
	#tag Method, Flags = &h0
		Function FormatDiagnosticList(list As JSONItem, defaultType As String, preferDefaultType As Boolean = False) As String
		  /// One line per buildError entry: type, message, location and position.
		  ///
		  /// Public because a tool can need these lines under its own heading: analyze_project
		  /// reports "Analysis results", not "Build errors", so it formats the lists itself
		  /// rather than taking ReplyDiagnostics' wording wholesale. Sharing the line format is
		  /// the point - it was hand-rolled a second time there, twice over.
		  
		  If list = Nil Then Return ""
		  Var lines() As String
		  For i As Integer = 0 To list.Count - 1
		    Var err As JSONItem = list.ChildAt(i)
		    If err = Nil Then Continue
		    // Xojo's "type" is the issue category - "Code" - not its severity, so it reads the
		    // same on an error and on a warning. A caller whose heading does not already say
		    // which it is asks for defaultType instead, so a warning line still says Warning.
		    Var errType As String = defaultType
		    If Not preferDefaultType And err.HasKey("type") Then errType = err.Value("type").StringValue
		    Var msg As String = If(err.HasKey("message"), err.Value("message").StringValue, "")
		    Var location As String = If(err.HasKey("location"), err.Value("location").StringValue, "")
		    Var position As String = If(err.HasKey("position"), err.Value("position").StringValue, "")
		    Var line As String = errType + ": " + msg
		    If location <> "" Then line = line + " [" + location + "]"
		    If position <> "" And position <> location Then line = line + " (" + position + ")"
		    lines.Add(line)
		  Next i
		  Return String.FromArray(lines, EndOfLine)
		End Function
	#tag EndMethod
	#tag Method, Flags = &h21
		Private Function MergeReply(frames() As JSONItem) As JSONItem
		  /// Folds the parts of one reply into a single envelope so callers keep reading
		  /// response.Value("response") as before. The primary part is chosen by weight: an
		  /// error beats output, output beats a warning, and a warning beats an empty answer -
		  /// an empty reply carries nothing, so it must never displace a warning. Every other part is attached under "xmcp_parts" (their
		  /// "response" values) so a tool can still report, say, the compiler warning that
		  /// accompanied a successful script - see ReplyWarnings.
		  
		  If frames.Count = 0 Then Return Nil
		  If frames.Count = 1 Then Return frames(0)
		  
		  Var primary As Integer = -1
		  Var rank() As String = Array("error", "output", "warning", "empty", "unknown")
		  For r As Integer = 0 To rank.LastIndex
		    For i As Integer = 0 To frames.LastIndex
		      Var kind As String = ReplyKind(frames(i))
		      If kind = rank(r) Then
		        // Among outputs, prefer one that actually says something.
		        // Exact, not trimmed. This ranking picks the answer for every tool, and for most the
		        // answer is data, so the test is for an empty string and nothing looser. In practice
		        // the difference is moot for whitespace: measured on 2026r2.1, the IDE collapses a
		        // Print of only whitespace into an empty reply itself, while "[   ]" keeps its spaces.
		        If kind = "output" And frames(i).Value("response").Type = Variant.TypeString And _
		          frames(i).Value("response").StringValue = "" Then Continue
		        primary = i
		        Exit For i
		      End If
		    Next i
		    If primary >= 0 Then Exit For r
		  Next r
		  
		  // Nothing matched any rank. That happens in exactly one case: every frame was an
		  // output whose string was empty, so the preference above skipped all of them and no
		  // later rank could match either, since they are all "output". An empty output is
		  // still the script's answer - a script that printed empty strings - so take the
		  // first one deliberately. Arriving here by falling out of the rank table read like
		  // an oversight; it is a real case with a real answer.
		  If primary < 0 Then primary = 0
		  
		  Var merged As JSONItem = frames(primary)
		  Var parts As New JSONItem("[]")
		  For i As Integer = 0 To frames.LastIndex
		    If i = primary Then Continue
		    If frames(i).HasKey("response") Then parts.Add(frames(i).Value("response"))
		  Next i
		  If parts.Count > 0 Then merged.Value("xmcp_parts") = parts
		  
		  LogVerbose("Merged " + frames.Count.ToString + " reply parts; primary kind " + ReplyKind(merged) + ".")
		  Return merged
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub AddPending(sock As IPCSocket, tag As String, script As String, unframed As String)
		  /// Parks a socket whose request the IDE accepted but has not answered yet.
		  ///
		  /// The IDE runs scripts on its main thread, so during a build - or behind a modal
		  /// dialog - it answers nothing until it is done, and then answers everything that
		  /// queued up, on the connections the requests arrived on. Closing such a
		  /// connection is what killed the IDE: its later write hits a closed peer, the
		  /// kernel raises SIGPIPE, and the Xojo IDE does not ignore that signal. The system
		  /// log showed "exited due to SIGPIPE | sent by Xojo" five seconds after the build
		  /// finished, with no crash report. So a timed-out socket stays open here until the
		  /// IDE has replied or has gone away; DrainPending does the housekeeping.
		  ///
		  /// The crash is a macOS/Linux one: there the IPCSocket is a Unix domain socket. On
		  /// Windows it is a TCP socket on localhost, where a write into a closed peer merely
		  /// fails. Parking is still right there - a busy IDE accepts the connect into its
		  /// backlog on both platforms, so the request is delivered either way, and refusing
		  /// to stack more behind it is what keeps the message honest.
		  
		  // The same test SendAndReceive used to decide whether to append the end marker, on the
		  // same script, so the two cannot disagree about whether a marker is coming.
		  mPending.Add(New PendingRequest(sock, tag, script, Not EndsWithLineContinuation(script), unframed))
		End Sub
	#tag EndMethod
	#tag Method, Flags = &h0
		Function DrainPending() As Integer
		  /// Polls every parked socket and releases the ones the IDE is finished with: it
		  /// wrote a reply (discarded - the caller gave up long ago), or it closed the
		  /// connection (the IDE quit or crashed), or the socket has been parked longer
		  /// than kPendingGiveUpMS. Returns how many are still waiting for the IDE.
		  
		  Var i As Integer = mPending.LastIndex
		  While i >= 0
		    Var req As PendingRequest = mPending(i)
		    Var done As Boolean = False
		    Var reason As String = ""
		    
		    Try
		      req.Sock.Poll
		      // Released only once the answer is complete - its end marker, or an error that
		      // stopped the script - never on a part followed by quiet: see ReplyComplete.
		      If req.ReplyComplete(Self) Then
		        done = True
		        reason = "the IDE answered it (reply discarded)"
		      ElseIf Not req.Sock.IsConnected Then
		        // Nothing more is coming, whether or not what arrived was whole.
		        done = True
		        reason = "the IDE closed the connection"
		      ElseIf System.Microseconds - req.SinceUS > kPendingGiveUpMS * 1000.0 Then
		        // The one release that closes a socket the IDE may still answer. If it does answer
		        // after this - a build longer than the limit, a dialog left open for hours - that
		        // write hits a closed peer, which on macOS and Linux is the SIGPIPE parking exists
		        // to prevent. It is a deliberate bound: without one, a request the IDE never
		        // answers would hold its only IPC connection for as long as this process lives.
		        Var giveUpMinutes As Integer = kPendingGiveUpMS / 60000
		        done = True
		        reason = "it was parked for over " + giveUpMinutes.ToString + " minutes"
		      End If
		    Catch e As RuntimeException
		      done = True
		      reason = "polling it failed: " + e.Message
		    End Try
		    
		    If done Then
		      LogVerbose("IDE request " + req.Tag + ": released, " + reason + ".")
		      Try
		        req.Sock.Close
		      Catch e As RuntimeException
		        // Nothing left to do with it.
		      End Try
		      mPending.RemoveAt(i)
		    End If
		    
		    i = i - 1
		  Wend
		  
		  Return mPending.Count
		End Function
	#tag EndMethod
	#tag Method, Flags = &h21
		Private Function PendingSummary() As String
		  /// One line per parked request: its tag, how long ago it was sent, and the start
		  /// of its script - enough to recognise "that was the build I started".
		  
		  Var lines() As String
		  For Each req As PendingRequest In mPending
		    Var ageS As Integer = Floor((System.Microseconds - req.SinceUS) / 1000000.0)
		    Var preview As String = req.Script.ReplaceLineEndings(" ").Trim
		    If preview.Length > 80 Then preview = preview.Left(77) + "..."
		    lines.Add("  " + req.Tag + " (sent " + ageS.ToString + "s ago): " + preview)
		  Next req
		  
		  Return String.FromArray(lines, EndOfLine)
		End Function
	#tag EndMethod

	#tag Property, Flags = &h0
		LastErrorMessage As String
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected mConnected As Boolean
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected mSocketPath As String
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected mTagCounter As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mTagPrefix As String
	#tag EndProperty


	#tag Property, Flags = &h21
		Private mParkedThisRequest As Boolean
	#tag EndProperty
	#tag Property, Flags = &h21
		Private mPending() As PendingRequest
	#tag EndProperty
	#tag Constant, Name = kPendingGiveUpMS, Type = Double, Dynamic = False, Default = \"7200000", Scope = Private, Description = 486F77206C6F6E672061207061726B656420736F636B65742069732068656C64206F70656E2077616974696E6720666F72207468652049444520746F20616E737765722C20696E206D696C6C697365636F6E647320283220686F757273292E
	#tag EndConstant
	
	#tag Constant, Name = kConnectTimeoutMS, Type = Double, Dynamic = False, Default = \"1500", Scope = Private
	#tag EndConstant
	
	#tag Constant, Name = kNoListenerPrefix, Type = String, Dynamic = False, Default = \"IPC socket not found", Scope = Private
	#tag EndConstant
	
	#tag Constant, Name = kAfterEndMarkerMS, Type = Double, Dynamic = False, Default = \"50", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kPartialPartMS, Type = Double, Dynamic = False, Default = \"1000", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kEndMarkerPrefix, Type = String, Dynamic = False, Default = \"xmcp-end:", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kSplitReplyWindowMS, Type = Double, Dynamic = False, Default = \"250", Scope = Private, Description = 486F77206C6F6E6720746F206B6565702072656164696E6720666F72206D6F726520706172747320616674657220746865206669727374206D61746368696E67207265706C79206672616D652C20696E206D696C6C697365636F6E64732E
	#tag EndConstant
	
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
			InitialValue=""
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
	#tag EndViewBehavior
End Class
#tag EndClass
